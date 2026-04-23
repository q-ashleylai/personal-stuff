# Church Analytics Dashboard — Cloud Migration Plan

## Context

DUMC (a church) is migrating its existing analytics dashboards (Power BI + NCG vendor-built) to Alibaba Cloud. The primary data source is **PCO (Planning Center Online)**, synced daily via API into a PostgreSQL/RDS database. A secondary source (**Chinese Power BI**) provides supplementary CN congregation data. Scale is medium (1-50GB) with daily/weekly refresh. The BI tool will be either Power BI or a new vendor (TBD). Everything must stay within Alibaba Cloud. Budget-conscious — no AnalyticDB needed.

**Data sources:**
- **PCO API** → `pco_*` tables (users, groups, events, attendance, check-ins, decisions, discipleship, serving)
- **Chinese Power BI** → supplementary CN-specific CG and serving data
- **User Requirements** → 7 modules defined in "Imperative 10: Analytic - User Requirement" document

## Recommended Architecture: Lightweight 3-Layer on RDS + Cron Job

```
┌─────────────────────────────────────────────────────────┐
│                   PRESENTATION LAYER                     │
│              Power BI / QuickBI / New Vendor              │
└──────────────────────┬──────────────────────────────────┘
                       │ reads from
┌──────────────────────▼──────────────────────────────────┐
│               SEMANTIC LAYER                            │
│          Separate "sem" schema in RDS                   │
│         Star schema: fact tables + dimension tables       │
│         Pre-aggregated, query-optimized                   │
└──────────────────────┬──────────────────────────────────┘
                       │ ETL (daily)
┌──────────────────────▼──────────────────────────────────┐
│                  TRANSFORM LAYER                         │
│              Cron Job + SQL Scripts (ETL)                  │
│         Clean, join, dedupe, business logic               │
└──────────────────────┬──────────────────────────────────┘
                       │ reads from
┌──────────────────────▼──────────────────────────────────┐
│                RAW / LANDING LAYER                        │
│              RDS / ApsaraDB (source data)                 │
│         Data as-is from migration, no transforms          │
└─────────────────────────────────────────────────────────┘
```

## What is a Star Schema?

A star schema is a **data model** optimized for analytics and reporting. It organizes tables into two types — **fact tables** (measurements) and **dimension tables** (descriptors) — with the fact table in the center and dimensions radiating outward like a star.

```
                    ┌────────────┐
                    │  dim_date  │
                    │   (WHEN)   │
                    └─────┬──────┘
                          │
┌────────────┐    ┌───────▼──────────┐    ┌──────────────────┐
│ dim_member │────│   FACT TABLES    │────│dim_congregation  │
│   (WHO)    │    │                  │    │ (WHICH CONGR.)   │
└────────────┘    └───────┬──────────┘    └──────────────────┘
                          │
                    ┌─────▼──────────┐
                    │ dim_cell_group │
                    │(WHICH CG/ZONE) │
                    └────────────────┘
```

### Summary: 4 Dimensions + 6 Facts

**Dimensions (descriptors — filter & group by):**

| Table | Source | Key Columns | Design Notes |
|---|---|---|---|
| `dim_date` | generated | year, quarter, month, week_of_year, day_of_week, weekend_flag | YYYYMMDD int key, ~3,650 rows for 10 years |
| `dim_congregation` | seed data (8 rows) | congregation_code, congregation_label | EN/BM/CN/MM/NP/TM/FP/NXG — no ETL needed |
| `dim_member` | `pco_users` | full_name, gender, age_group, membership, user_role, is_baptized, congregation_key | member_key = user_id (no surrogate key) |
| `dim_cell_group` | `pco_groups` (type 137505) | cg_name, zone, district, subzone, zone_leader, leader_member_key, age_group, frequency, cg_size, status, congregation_key | Zone/district/subzone denormalized here (no separate dim_zone — avoids extra joins) |

**Facts (measures — count & aggregate):**

| Table | Grain | Key Measures | Pillar | PCO Source |
|---|---|---|---|---|
| `fact_cg_attendance` | member × CG event | attended (0/1), user_role (member/visitor/leader) | Cell Group | `pco_attendance` + `pco_events` |
| `fact_cg_submission` | CG × event | submitted (0/1), cancelled (0/1) | Cell Group | `pco_events` (event_att_committed_at) |
| `fact_decisions` | decision form | form_id (112029/117917), form_title, congregation_key | Evangelism | `pco_new_decisions` |
| `fact_discipleship` | participant | status (In progress/Completed), started_date_key, completed_date_key | Evangelism, Training | `pco_discipleship_completion` |
| `fact_celebration_attendance` | check-in | kind (Guest/Regular/Volunteer), service_name, congregation_key | Celebration | `pco_checkin_attendance` |
| `fact_serving` | volunteer × date | team_name, ministry, position | Serving | `pco_serving_attendance` |

**Key design choices:**
- **No `dim_zone`** — zone/district/subzone are denormalized on `dim_cell_group` (avoids extra join for every CG query)
- **`dim_congregation` is a tiny seed table** (8 rows) — no ETL, just reference data
- **`member_key` = `user_id`** directly from PCO — no surrogate key generation
- All fact tables use `date_key` (INT YYYYMMDD) for consistent time slicing
- SQL definition: `02-semantic-layer/01-create-sem-schema.sql`

### Why Not Just Query Raw Tables Directly?

| Raw tables | Star schema |
|---|---|
| Normalized (many JOINs needed) | Pre-joined, fewer JOINs |
| No computed fields | Age groups, engagement tiers pre-calculated |
| Codes like `english` | Friendly labels like "English Congregation" |
| No date dimension | Easy to slice by week, month, quarter, year |
| Optimized for data entry | Optimized for dashboards |

### Examples

**Weekly CG Attendance by Zone** (Cell Group pillar):
```sql
SELECT cg.zone, d.year, d.week_of_year,
       SUM(f.attended) AS total_attended,
       COUNT(*) AS total_records
FROM sem.fact_cg_attendance f
JOIN sem.dim_cell_group cg ON f.cg_key = cg.cg_key
JOIN sem.dim_date d ON f.date_key = d.date_key
WHERE f.attended = 1
GROUP BY cg.zone, d.year, d.week_of_year;
```

**CG Submission Rate** (Cell Group pillar):
```sql
SELECT dc.congregation_label, d.year, d.week_of_year,
       SUM(f.submitted) AS submitted_count,
       COUNT(*) AS total_events,
       ROUND(SUM(f.submitted) * 100.0 / COUNT(*), 1) AS submission_rate_pct
FROM sem.fact_cg_submission f
JOIN sem.dim_cell_group cg ON f.cg_key = cg.cg_key
JOIN sem.dim_congregation dc ON cg.congregation_key = dc.congregation_key
JOIN sem.dim_date d ON f.date_key = d.date_key
WHERE f.cancelled = 0
GROUP BY dc.congregation_label, d.year, d.week_of_year;
```

**Decisions by Congregation** (Evangelism pillar):
```sql
SELECT dc.congregation_label, d.year, d.month,
       COUNT(*) AS total_decisions
FROM sem.fact_decisions f
JOIN sem.dim_congregation dc ON f.congregation_key = dc.congregation_key
JOIN sem.dim_date d ON f.date_key = d.date_key
GROUP BY dc.congregation_label, d.year, d.month;
```

**Celebration Attendance by Kind** (Celebration pillar):
```sql
SELECT dc.congregation_label, d.year, d.week_of_year,
       SUM(CASE WHEN f.kind = 'Regular' THEN 1 ELSE 0 END) AS regular_count,
       SUM(CASE WHEN f.kind = 'Guest' THEN 1 ELSE 0 END) AS guest_count,
       SUM(CASE WHEN f.kind = 'Volunteer' THEN 1 ELSE 0 END) AS volunteer_count,
       COUNT(*) AS total_checkins
FROM sem.fact_celebration_attendance f
JOIN sem.dim_congregation dc ON f.congregation_key = dc.congregation_key
JOIN sem.dim_date d ON f.date_key = d.date_key
GROUP BY dc.congregation_label, d.year, d.week_of_year;
```

**Serving Frequency Tiers** (Serving pillar):
```sql
SELECT
    CASE
        WHEN serve_count >= 4 THEN 'High (4+/month) - burnout risk'
        WHEN serve_count BETWEEN 1 AND 3 THEN 'Moderate (1-3/month) - consistent'
        ELSE 'Low (0/month) - capacity available'
    END AS frequency_tier,
    COUNT(*) AS member_count
FROM (
    SELECT f.member_key, COUNT(*) AS serve_count
    FROM sem.fact_serving f
    JOIN sem.dim_date d ON f.date_key = d.date_key
    WHERE d.year = 2026 AND d.month = 3
    GROUP BY f.member_key
) monthly
GROUP BY frequency_tier;
```

The dimension keys (`member_key`, `date_key`, `cg_key`, `congregation_key`) connect everything — they are the "arms" of the star. The daily ETL process keeps the star schema updated so dashboard queries stay fast and simple.

---

## Layer Details

### 4. Presentation Layer — BI Tool
- **Power BI**: Can connect to RDS via MySQL connector. Works well.
- **QuickBI**: Alibaba's native tool, tightest integration, lower cost.
- **New vendor**: As long as they support MySQL protocol, they can connect.

---

## DUMC 7 Pillars & Dashboard Metrics

The semantic layer is structured around DUMC's **7 pillars**. Each pillar has specific dashboard reports sourced from **NCG** (vendor system) and/or **Chinese Power BI**.

### Pillar 1: Membership
> *From User Requirement Module 1: "In XX congregation, what is the ratio of official church members, to cell group members, and to lost sheep?"*

| Dashboard Report | Source | Key Metrics (from PCO) |
|---|---|---|
| DUMC CG Size by Year | PCO | `pco_groups` (type_key=137505) grp_size by year |
| Staff Demographics | PCO | `pco_users` filtered by user_role containing 'Pastor'/'Elder' + staff list |
| Pastor Demographics | PCO | `pco_users` where user_role IN ('Pastor', 'Zone Pastor', etc.) |
| CG Leader Demographics | PCO | `pco_users` where user_role = 'Cell Group Leader' |
| CG Leader Age / Gender | PCO | Above + parsed user_birthdate → age_group, user_gender |
| Church Member % (TRAC) | PCO | user_membership='Church Member' ÷ total (Church+Cell+Visitor) |
| CG Member % | PCO | user_membership='Cell Member' ÷ total |
| Lost Sheep % | PCO | Church Members with no CG attendance in past 6 months ÷ total |

### Pillar 2: Cell Group
> *From User Requirement Module 2: "How consistent and healthy is member engagement and leadership accountability across our Cell Groups?"*

| Dashboard Report | Source | Key Metrics (from PCO) |
|---|---|---|
| Weekly CG Attendance [All Congregation] | PCO | `pco_attendance` att_status='1' WHERE group type_key=137505, by week |
| CG Health Analysis EN/BM/CN/MM/NP/TM | PCO | Attendance %, submission %, visitor count, leader visits — per congregation |
| Weekly CG Attendance Analysis By Zone | PCO | Attendance by `pco_groups.grp_tag_zone` |
| Average CG Attendance By Zone | PCO | AVG attendance per zone over time |
| Weekly CG Attendance Rate By CG | PCO | Attended ÷ total CG members per group per week |
| CG Submission Rate | PCO | Events where event_att_committed_at IS NOT NULL ÷ total CG events |
| Non-submission of CG Attendance | PCO | CG events WHERE event_att_committed_at IS NULL (not submitted) |
| Pastor Attendance Analysis | PCO | `pco_attendance` where att_user_role='leader' AND user_role='Pastor' |
| Zone Leader CG Attendance Analysis | PCO | Attendance where att_user_role='visitor' AND user_role='Zone Leader' |
| Weekly Count of Active CG Sessions | PCO | COUNT of CG events WHERE event_canceled='0' per week |
| CG Scheduled % | PCO | Total CG events ÷ total weeks × number of CGs |
| CG Cancelled count | PCO | COUNT WHERE event_canceled='1' |
| Visitor Visitation | PCO | att_user_role='visitor' AND user_membership='Visitor' count per CG |
| CN Cell Group metrics | Chinese Power BI | CN-specific CG data (supplementary) |
| CN CG Attendance | Chinese Power BI | CN-specific attendance (supplementary) |

### Pillar 3: Evangelism
> *From User Requirement Module 3: "How many people have made the decision to accept Christ, been baptized, or finished Discipleship 101?"*

| Dashboard Report | Source | Key Metrics (from PCO) |
|---|---|---|
| DUMC Decisions Churchwide | PCO | `pco_new_decisions` COUNT(*) — all forms |
| BM/CN/EN/MM/NP/TM/FP Decisions | PCO | Decisions by congregation (parsed from form context/user's group) |
| EN NXG CC Decisions | PCO | Decisions filtered by NXG/CC program context |
| Baptisms by Congregation | PCO | `pco_users` WHERE user_baptized IS NOT NULL, by congregation |
| D101 Completions | PCO | `pco_discipleship_completion` WHERE dc_workflow_completion='Completed' |
| Decision Forms: Outside (112029) vs Online (117917) | PCO | COUNT by nd_form_submitted value |

### Pillar 4: Serving
> *From User Requirement Module 5: "What proportion of people are actively serving, and how often are they serving?"*

| Dashboard Report | Source | Key Metrics (from PCO) |
|---|---|---|
| % Actively Serving | PCO | `pco_serving_teams_membership` active ÷ total congregation members |
| High-Frequency Servers (≥4/month) | PCO | `pco_serving_attendance` COUNT ≥ 4 in past month — burnout risk |
| Moderate-Frequency Servers (1-3/month) | PCO | COUNT 1-3 in past month — consistent servers |
| Low-Frequency Servers (0/month) | PCO | Members in teams but COUNT=0 in past month — capacity available |
| CN Serving data | Chinese Power BI | CN-specific serving data (supplementary) |
| CN Volunteer metrics | Chinese Power BI | CN-specific volunteer counts (supplementary) |

### Pillar 5: Celebration
> *From User Requirement Module 7: "What was this week's Celebration attendance, and how did it change percentage-wise compared to the previous week?"*

| Dashboard Report | Source | Key Metrics (from PCO) |
|---|---|---|
| Celebration Attendance In-Person & Livestream | PCO | `pco_checkin_attendance` (in-person) + `pco_checkin_event_time` cet_total_count; livestream from separate source |
| EN/BM/CN/MM/NP/TM Celebration Attendance | PCO | Check-in counts by service → congregation mapping |
| NXG / Activities Attendance | PCO | Check-in events filtered by NXG service types |
| Week-over-Week % Change | PCO | Current week headcount ÷ previous week headcount |
| Assimilation Rate | PCO | Newcomers who completed track and joined CG ÷ total newcomers |

### Pillar 6: Training
> *From User Requirement Module 4: "How effectively are members engaging with and progressing through training and leadership development pathways?"*

| Dashboard Report | Source | Key Metrics |
|---|---|---|
| Training Engagement % | PCO (pco_groups type_key=147987) | Members who attended Equip/Training class in past year ÷ total CG members |
| Leadership Track (L1/L2/L3) Completion | PCO (pco_groups) | Count of members who completed each leadership level |
| D&D Participation | PCO (pco_groups) | Members who attended specialized tracks (Church Education, Faith Formation) |

### Pillar 7: Mission
> *From User Requirement Module 6: "What is the level of missional training and participation in XX congregation?"*

| Dashboard Report | Source | Key Metrics |
|---|---|---|
| MCPP1 Completion % | PCO (pco_groups / pco_attendance) | Members who attended MCPP1 ÷ total congregation |
| MCPP2 Completion % | PCO (pco_groups / pco_attendance) | Members who attended MCPP2 ÷ total congregation |
| Mission Trip Participation | PCO (pco_events / pco_attendance) | Number of members involved in external mission trips |

### Congregation Abbreviations

| Code | Full Name |
|---|---|
| EN | English |
| BM | Bahasa Malaysia |
| CN | Chinese |
| MM | Myanmar |
| NP | Nepal |
| TM | Tamil |
| FP | Filipino |
| NXG | Next Generation (Youth) |
| CC | Campus Church |

---

## Detailed: Raw → ETL → Analytics Flow

Focus areas: All **7 pillars** — Membership, Cell Group, Evangelism, Training, Serving, Mission, Celebration.

### 1. RAW LAYER — PCO (Planning Center Online) Source Tables

The primary data source is **PCO** (Planning Center Online), synced daily via API into the `raw` schema. These tables are loaded **as-is** with no transformations. A secondary source (**Chinese Power BI**) provides supplementary CN-specific data.

> **Source:** "Data Dictionary for AWS PCO DB" document. Table/column names match the PCO API sync.

#### Core: Users (Members)

```sql
-- raw.pco_users
-- One row per person in the church system (members, visitors, staff, etc.)
user_id          INTEGER PK
user_first_name  VARCHAR(100) NOT NULL
user_last_name   VARCHAR(100) NOT NULL
user_name        VARCHAR(50)  NOT NULL     -- display name
user_given_name  VARCHAR(50)               -- preferred name
user_nickname    VARCHAR(50)
user_gender      VARCHAR(7)                -- NULL, 'Male', 'Female'
user_birthdate   VARCHAR(100)              -- date of birth (string format)
user_anniversary VARCHAR(100)
user_child       VARCHAR(100) NOT NULL     -- ' ' or '1' (is child)
user_membership  VARCHAR(100)              -- NULL, 'Church Member', 'Cell Member',
                                           --   'Visitor', 'Non-Attender', 'Affiliates',
                                           --   'Equipping Attender', 'Event Attender',
                                           --   'Participant', '(Archived) Church Member'
user_status      VARCHAR(100) NOT NULL     -- 'active' or 'inactive'
user_role        VARCHAR(50)               -- NULL, 'Pastor', 'Elder', 'Zone Leader',
                                           --   'Zone Pastor', 'Cell Group Leader',
                                           --   'Assistant Cell Group Leader',
                                           --   'Zone Leader | Pastor', 'Zone Leader | Elder',
                                           --   'Pastor | Elder'
user_link        VARCHAR(200) NOT NULL
user_created_at  VARCHAR(50)  NOT NULL
user_work_title  VARCHAR(500)
user_industry    VARCHAR(50)
user_baptized    VARCHAR(10)               -- NULL, 'Yes', 'Baptized', 'Baptised', 'HTBB', date
user_baptism_date VARCHAR(20)
user_medical_notes VARCHAR(1000)
```

#### Cell Group: Groups & Membership

```sql
-- raw.pco_groups
-- One row per group (Cell Groups, Leaders, Training, Ministry, etc.)
grp_id           INTEGER PK
grp_name         VARCHAR(100) NOT NULL
grp_type_key     INTEGER NOT NULL          -- 137505=Cell Groups, 162273=Leaders,
                                           --   147987=Training, 424122=Others,
                                           --   221572=Initiative, 327760=Archived,
                                           --   151990=PCO Group Training, 150510=Ministry
grp_link         VARCHAR(500) NOT NULL
grp_location     INTEGER
grp_contact_email VARCHAR(100)
grp_leader_user_key INTEGER               -- FK to pco_users (group leader)
grp_tag_zone     VARCHAR(100) NOT NULL     -- e.g. 'EN PJS1', 'CN NXG'
grp_tag_congregation VARCHAR(100)          -- 'EN - English', 'BM - Bahasa', 'CN - Chinese',
                                           --   'TM - Tamil', 'MM - Myanmar', 'NP - Nepali',
                                           --   'FP - Filipino', or ' '
grp_tag_age_group VARCHAR(100)             -- '12 and below', '13 - 17', '18 - 23',
                                           --   '24 - 35', '36 - 50', '66 and above', or ' '
grp_tag_freq     VARCHAR(100)              -- 'Weekly', 'Monthly', 'Twice Monthly', 'Varied', ' '
grp_tag_ministry VARCHAR(100)              -- e.g. 'CN Facility', 'EQ Level 2'
grp_size         INTEGER NOT NULL
grp_status       VARCHAR(20)               -- NULL, 'NEW', 'ARCHIEVED'
grp_zone_leader  VARCHAR(200)              -- e.g. 'EN MD - ZL: Pr Gilbert'
grp_tag_district VARCHAR(100)              -- e.g. 'BM - District 1'
grp_tag_subzone  VARCHAR(100) NOT NULL     -- e.g. 'CN ZL: Pr Samuel Tan'
grp_location_type_preference VARCHAR(20)   -- NULL

-- raw.pco_group_membership
-- Junction: which users belong to which groups
member_id        INTEGER PK
member_joined_date TIMESTAMPTZ NOT NULL
member_role      VARCHAR(20) NOT NULL      -- 'member' or 'leader'
member_grp_key   INTEGER FK (pco_groups)
member_user_key  INTEGER FK (pco_users)
member_user_link VARCHAR(500) NOT NULL
member_grp_link  VARCHAR(500) NOT NULL
```

#### Cell Group & Celebration: Events & Attendance

```sql
-- raw.pco_events
-- One row per scheduled event (CG meetings, celebrations, activities)
event_id         INTEGER PK
event_name       VARCHAR(200) NOT NULL
event_group_key  INTEGER FK (pco_groups)   -- which group this event belongs to
event_location_key INTEGER
event_startdatetime VARCHAR(30) NOT NULL
event_enddatetime VARCHAR(100) NOT NULL
event_canceled   VARCHAR(20) NOT NULL      -- '0' (not cancelled) or '1' (cancelled)
event_canceled_at VARCHAR(100)
event_reminders_sent VARCHAR(20) NOT NULL  -- '0' or '1'
event_reminders_sent_at VARCHAR(20)
event_description VARCHAR(4000)
event_att_committed_at VARCHAR(30)         -- when attendance was submitted (NULL = not submitted)
event_job_key    INTEGER
event_location_type_preference VARCHAR(20)

-- raw.pco_attendance
-- One row per user per event attended (CG + celebration attendance)
att_event_key    INTEGER FK (pco_events)
att_group_key    INTEGER FK (pco_groups)
att_user_key     INTEGER FK (pco_users)
att_user_role    VARCHAR(20) NOT NULL      -- 'member', 'visitor', 'leader', 'applicant'
att_status       VARCHAR(20) NOT NULL      -- '0' (didn't attend) or '1' (attended)
att_job_date     VARCHAR(50)               -- date data was pulled from PCO
```

#### Celebration: Check-in System

```sql
-- raw.pco_checkin_events
-- Check-in event definitions (celebration services, kids church, etc.)
ce_id            INTEGER PK
ce_name          VARCHAR(1000) NOT NULL
ce_frequency     VARCHAR(50) NOT NULL      -- 'Daily', 'Weekly', 'None'
ce_archived_at   VARCHAR(200)

-- raw.pco_checkin_event_time
-- Timing details for check-in events
cet_id           INTEGER PK
cet_day_of_week  INTEGER NOT NULL          -- 0=Sunday, 1=Monday, ..., 6=Saturday
cet_guest_count  INTEGER NOT NULL
cet_hour         INTEGER NOT NULL          -- 24H format
cet_minute       INTEGER NOT NULL
cet_shows_at     TIMESTAMP NOT NULL
cet_start_at     TIMESTAMPTZ NOT NULL
cet_total_count  INTEGER NOT NULL          -- headcount
cet_ce_event_key INTEGER FK (pco_checkin_events)
cet_eventperiod_key INTEGER NOT NULL

-- raw.pco_checkin_attendance
-- Individual check-in records (in-person celebration attendance)
ca_id            INTEGER PK
ca_checked_out_at TIMESTAMP
ca_confirmed_at  TIMESTAMP
ca_first_name    VARCHAR(200) NOT NULL
ca_last_name     VARCHAR(200) NOT NULL
ca_kind          VARCHAR(50) NOT NULL      -- 'Guest', 'Regular', 'Volunteer'
ca_number        INTEGER NOT NULL
ca_user_key      INTEGER FK (pco_users)
ca_eventperiod_key INTEGER NOT NULL
ca_ce_key        INTEGER FK (pco_checkin_events)
ca_checked_in_by_user_key INTEGER
ca_checked_out_by_user_key INTEGER
ca_created_at    TIMESTAMPTZ NOT NULL
```

#### Evangelism: Decisions & Discipleship

```sql
-- raw.pco_new_decisions
-- Evangelism decision form submissions
nd_id            INTEGER PK
nd_user_key      INTEGER FK (pco_users)
nd_user_name     VARCHAR(255) NOT NULL
nd_form_submitted INTEGER NOT NULL         -- 112029 = 'EN - Decision Form' (outside church)
                                           -- 117917 = 'EN - Decision Form (Online)' (during celebration)
nd_form_title    VARCHAR(255) NOT NULL
nd_submitted_at  DATE NOT NULL
nd_reason        VARCHAR(1000) NOT NULL    -- concatenated answers from the form

-- raw.pco_discipleship_completion
-- Discipleship workflow tracking (D101, new believer follow-up)
dc_id            INTEGER PK
dc_user_key      INTEGER FK (pco_users)
dc_user_name     VARCHAR(255) NOT NULL
dc_started_at    DATE NOT NULL             -- date added to workflow
dc_workflow_completion VARCHAR(50) NOT NULL -- 'In progress' or 'Completed'
dc_completed_at  DATE                      -- NULL if not yet completed
```

#### Serving: Teams & Attendance

```sql
-- raw.pco_serving_teams
-- Serving team definitions
st_team_id       INTEGER PK
st_team_name     VARCHAR(255) NOT NULL     -- e.g. 'Worship Team - Musicians'
st_service_type  VARCHAR(255) NOT NULL     -- parent ministry, e.g. 'DUMC EN NextGen'

-- raw.pco_serving_teams_membership
-- Which users belong to which serving teams
stm_id           INTEGER PK
stm_user_key     INTEGER FK (pco_users)
stm_team_key     INTEGER FK (pco_serving_teams)
stm_user_name    VARCHAR(255) NOT NULL

-- raw.pco_serving_attendance
-- When volunteers actually served
sa_id            INTEGER PK
sa_plan          INTEGER NOT NULL          -- unique event/plan ID
sa_user_key      INTEGER FK (pco_users)
sa_team_key      INTEGER FK (pco_serving_teams)
sa_user_name     VARCHAR(255) NOT NULL
sa_team_name     VARCHAR(255) NOT NULL
sa_service_type  VARCHAR(255) NOT NULL     -- parent ministry
sa_position      VARCHAR(255) NOT NULL     -- specific role (e.g. 'Drums')
sa_service_date  DATE NOT NULL
```

#### Infrastructure: Room Booking & ETL Config

```sql
-- raw.pco_rooms / raw.pco_room_booking
-- Room management (not used in semantic layer, retained for reference)

-- raw.run_config / raw.run_log
-- ETL job scheduling and execution logs
-- run_config: defines sync jobs (daily/weekly), curl commands, insert SQL
-- run_log: tracks job execution status ('RUNNING', 'DONE')
```

### 2. ETL LAYER — Cron Job + SQL Scripts

Each transformation is a **SQL script** executed by a cron job in dependency order:
**dimensions first, then facts**.

> **Note:** Two source systems feed into the raw layer:
> - **PCO (Planning Center Online)** — primary system for all congregations, synced via API into `pco_*` tables
> - **Chinese Power BI** — supplementary CN-specific data (CG metrics, serving, volunteers)
>
> The ETL must handle deduplication where CN data appears in both sources.

> **Note:** If ETL complexity grows (e.g., more fact tables, complex dependencies, need for retry/alerting), consider migrating to Alibaba Cloud DataWorks for built-in scheduling, dependency management, and monitoring.

```
Cron Job Execution Order (daily schedule):

DIMENSIONS (run in parallel — no dependencies between them):
┌──────────┐  ┌──────────┐  ┌──────────┐
│ dim_date │  │dim_member│  │  dim_cg  │
└────┬─────┘  └────┬─────┘  └────┬─────┘
     │             │             │
     └──────┬──────┴─────────────┘
            ▼
  dim_congregation = seed data (no ETL)

FACTS (run after dimensions):
┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐
│fact_cg_attendance│  │  fact_decisions   │  │fact_celebration   │
└────────┬─────────┘  └────────┬─────────┘  │  _attendance      │
         │                     │            └────────┬─────────┘
┌────────▼─────────┐  ┌───────▼──────────┐  ┌──────▼───────────┐
│fact_cg_submission│  │fact_discipleship │  │  fact_serving     │
└──────────────────┘  └──────────────────┘  └──────────────────┘
```

| ETL Step | Script File | PCO Source Tables | Description | Refresh |
|----------|-------------|-------------------|-------------|---------|
| 1. dim_date | `03-etl-transforms/01-dim-date.sql` | *(generated)* | Date spine: year, quarter, month, week_of_year, day_of_week, weekend_flag | INSERT IGNORE (append only) |
| 2. dim_member | `03-etl-transforms/02-dim-member.sql` | `pco_users` + `pco_group_membership` + `pco_groups` | Parse birthdate→age_group, map user_role, user_membership, derive congregation_key from group tags, is_baptized from user_baptized | Full refresh (truncate + reload) |
| 3. dim_cell_group | `03-etl-transforms/03-dim-cell-group.sql` | `pco_groups` (grp_type_key=137505) + `pco_group_membership` | CGs with zone, district, subzone, zone_leader (all denormalized from group tags), leader_member_key, congregation_key, age_group, frequency, size, status | Full refresh |
| 4. dim_congregation | *(no ETL — seed data)* | — | 8-row reference table (EN/BM/CN/MM/NP/TM/FP/NXG). Seeded in CREATE TABLE script, not refreshed. | Static seed |
| 5. fact_cg_attendance | `03-etl-transforms/04-fact-cg-attendance.sql` | `pco_attendance` + `pco_events` + `pco_groups` | Filter: grp_type_key=137505 (CG events only). Map att_status→attended, att_user_role→user_role, event_startdatetime→date_key | Incremental (watermark on att_job_date) |
| 6. fact_cg_submission | `03-etl-transforms/05-fact-cg-submission.sql` | `pco_events` + `pco_groups` | Filter: grp_type_key=137505. event_att_committed_at IS NOT NULL→submitted, event_canceled='1'→cancelled | Incremental (watermark on event_startdatetime) |
| 7. fact_decisions | `03-etl-transforms/06-fact-decisions.sql` | `pco_new_decisions` + `pco_users` | Map nd_submitted_at→date_key, nd_form_submitted→form_id, derive congregation_key from user's group | Incremental (watermark on nd_submitted_at) |
| 8. fact_discipleship | `03-etl-transforms/07-fact-discipleship.sql` | `pco_discipleship_completion` | Map dc_started_at→started_date_key, dc_completed_at→completed_date_key, dc_workflow_completion→status | Full refresh |
| 9. fact_celebration_attendance | `03-etl-transforms/08-fact-celebration-attendance.sql` | `pco_checkin_attendance` + `pco_checkin_events` | Map ca_created_at→date_key, ca_kind→kind, ce_name→service_name, derive congregation_key from service name | Incremental (watermark on ca_created_at) |
| 10. fact_serving | `03-etl-transforms/09-fact-serving.sql` | `pco_serving_attendance` + `pco_serving_teams` | Map sa_service_date→date_key, sa_user_key→member_key, join team name/ministry/position | Incremental (watermark on sa_service_date) |

Cron runner script: `05-dataworks-config/run-etl.sh`

### 3. SEMANTIC LAYER — Star Schema Tables

These are the target tables the BI tool reads from. Full CREATE TABLE definitions in:
- `02-semantic-layer/01-create-sem-schema.sql` — sem schema (4 dimensions + 6 facts)

| Table | Type | Grain | Pillars Served |
|-------|------|-------|----------------|
| `dim_date` | Dimension | One row per calendar date (year, quarter, month, week_of_year, day_of_week, weekend_flag) | All |
| `dim_member` | Dimension | One row per member (age_group, gender, user_role, membership, congregation_key, is_baptized) | All |
| `dim_cell_group` | Dimension | One row per CG (zone, district, subzone, zone_leader, leader, congregation_key, age_group, frequency, size, status) | Cell Group, Membership |
| `dim_congregation` | Dimension | 8-row seed table (EN/BM/CN/MM/NP/TM/FP/NXG → labels) | All |
| `fact_cg_attendance` | Fact | One row per member per CG event (attended, user_role) | Cell Group |
| `fact_cg_submission` | Fact | One row per CG per event (submitted, cancelled) | Cell Group |
| `fact_decisions` | Fact | One row per decision form (form_id, form_title, congregation_key) | Evangelism |
| `fact_discipleship` | Fact | One row per participant (status, started_date_key, completed_date_key) | Evangelism, Training |
| `fact_celebration_attendance` | Fact | One row per check-in (kind, service_name, congregation_key) | Celebration |
| `fact_serving` | Fact | One row per volunteer per serve date (team_name, ministry, position) | Serving |

### Data Lineage Summary

```
PCO RAW TABLE                       →  ETL TRANSFORM                    →  ANALYTICS TABLE
────────────────────────────────────────────────────────────────────────────────────────────────

DIMENSIONS:
(generated)                         →  date spine generation            →  dim_date
pco_users                           →  parse birthdate→age_group,       →  dim_member
  + pco_group_membership            →  map user_role, user_membership,  →    (age_group, gender, role,
  + pco_groups                      →  derive congregation from groups  →     membership, congregation_key,
                                    →  parse user_baptized→is_baptized  →     is_baptized)
pco_groups (type_key=137505)        →  parse tags: zone, district,      →  dim_cell_group
  + pco_group_membership            →  subzone, zone_leader, congr.,    →    (zone, district, subzone,
                                    →  age_group, freq, size, status    →     zone_leader, leader, size)
(seed data — no ETL)                →  static 8-row insert              →  dim_congregation

FACTS:
pco_attendance                      →  filter: grp_type_key=137505      →  fact_cg_attendance
  + pco_events                      →  att_status→attended              →    (member_key, cg_key, date_key,
  + pco_groups                      →  att_user_role→user_role          →     attended, user_role)
pco_events                          →  filter: grp_type_key=137505      →  fact_cg_submission
  + pco_groups                      →  event_att_committed_at→submitted →    (cg_key, date_key,
                                    →  event_canceled→cancelled         →     submitted, cancelled)
pco_new_decisions                   →  nd_form_submitted→form_id        →  fact_decisions
  + pco_users                       →  derive congregation_key          →    (member_key, date_key,
                                    →                                   →     form_id, congregation_key)
pco_discipleship_completion         →  dc_started_at→started_date_key   →  fact_discipleship
                                    →  dc_completed_at→completed_date_key   (member_key, status,
                                    →  dc_workflow_completion→status    →     started, completed)
pco_checkin_attendance              →  ca_kind→kind                     →  fact_celebration_attendance
  + pco_checkin_events              →  ce_name→service_name             →    (member_key, date_key, kind,
                                    →  derive congregation_key          →     service_name, congregation_key)
pco_serving_attendance              →  sa_service_date→date_key         →  fact_serving
  + pco_serving_teams               →  join team name, ministry, pos.   →    (member_key, date_key, team,
                                    →                                   →     ministry, position)
```

### Dashboard Queries by Pillar

See full query files organized by pillar:

#### Pillar 1: Membership
- `04-dashboard-queries/01-membership/01-cg-size-by-year.sql` — DUMC CG Size by Year (from dim_cell_group)
- `04-dashboard-queries/01-membership/02-staff-demographics.sql` — Staff demographics (dim_member WHERE user_role LIKE '%Pastor%' or staff)
- `04-dashboard-queries/01-membership/03-pastor-demographics.sql` — Pastor demographics (dim_member WHERE user_role IN ('Pastor', 'Zone Pastor'...))
- `04-dashboard-queries/01-membership/04-cg-leader-demographics.sql` — CG Leader demographics (dim_member WHERE user_role = 'Cell Group Leader')
- `04-dashboard-queries/01-membership/05-cg-leader-age-gender.sql` — CG Leader age/gender (age_group × gender pivot)
- `04-dashboard-queries/01-membership/06-membership-ratio.sql` — Church Member % / CG Member % / Lost Sheep %

#### Pillar 2: Cell Group
- `04-dashboard-queries/02-cell-group/01-weekly-cg-attendance-all.sql` — Weekly CG Attendance [All Congregation]
- `04-dashboard-queries/02-cell-group/02-cg-health-analysis.sql` — CG Health Analysis by congregation (EN/BM/CN/MM/NP/TM)
- `04-dashboard-queries/02-cell-group/03-weekly-cg-attendance-by-zone.sql` — Weekly CG Attendance Analysis By Zone
- `04-dashboard-queries/02-cell-group/04-avg-cg-attendance-by-zone.sql` — Average CG Attendance By Zone
- `04-dashboard-queries/02-cell-group/05-weekly-cg-attendance-rate.sql` — Weekly CG Attendance Rate By CG
- `04-dashboard-queries/02-cell-group/06-cg-submission-rate.sql` — CG Submission Rate
- `04-dashboard-queries/02-cell-group/07-non-submission-cg.sql` — Non-submission of CG Attendance
- `04-dashboard-queries/02-cell-group/08-pastor-attendance-analysis.sql` — Pastor Attendance Analysis
- `04-dashboard-queries/02-cell-group/09-zone-leader-cg-attendance.sql` — Zone Leader CG Attendance Analysis
- `04-dashboard-queries/02-cell-group/10-active-cg-sessions.sql` — Weekly Count of Active CG Sessions
- `04-dashboard-queries/02-cell-group/11-cn-cg-metrics.sql` — CN Cell Group metrics (Chinese Power BI)
- `04-dashboard-queries/02-cell-group/12-cn-cg-attendance.sql` — CN CG Attendance (Chinese Power BI)

#### Pillar 3: Evangelism
- `04-dashboard-queries/03-evangelism/01-decisions-churchwide.sql` — DUMC Decisions Churchwide (COUNT from fact_decisions)
- `04-dashboard-queries/03-evangelism/02-decisions-by-congregation.sql` — Decisions by congregation (BM/CN/EN/MM/NP/TM/FP)
- `04-dashboard-queries/03-evangelism/03-en-nxg-cc-decisions.sql` — EN NXG CC Decisions
- `04-dashboard-queries/03-evangelism/04-baptisms-by-congregation.sql` — Baptisms (dim_member WHERE is_baptized=1)
- `04-dashboard-queries/03-evangelism/05-d101-completions.sql` — D101 Completions (fact_discipleship WHERE status='Completed')
- `04-dashboard-queries/03-evangelism/06-decision-form-breakdown.sql` — Outside (112029) vs Online (117917) form breakdown

#### Pillar 4: Serving
- `04-dashboard-queries/04-serving/01-actively-serving-pct.sql` — % Actively Serving by congregation
- `04-dashboard-queries/04-serving/02-serving-frequency-tiers.sql` — High/Moderate/Low frequency server breakdown
- `04-dashboard-queries/04-serving/03-cn-serving-data.sql` — CN Serving data (Chinese Power BI supplement)
- `04-dashboard-queries/04-serving/04-cn-volunteer-metrics.sql` — CN Volunteer metrics (Chinese Power BI supplement)

#### Pillar 5: Celebration
- `04-dashboard-queries/05-celebration/01-celebration-attendance.sql` — Celebration Attendance by kind (Regular/Guest/Volunteer)
- `04-dashboard-queries/05-celebration/02-celebration-by-congregation.sql` — Celebration Attendance by congregation (EN/BM/CN/MM/NP/TM)
- `04-dashboard-queries/05-celebration/03-nxg-activities-attendance.sql` — NXG / Activities Attendance
- `04-dashboard-queries/05-celebration/04-week-over-week-change.sql` — Week-over-Week % change
- `04-dashboard-queries/05-celebration/05-assimilation-rate.sql` — Newcomer assimilation rate (Guest→CG member)

#### Pillar 6: Training
- `04-dashboard-queries/06-training/01-training-engagement.sql` — Training Engagement % (attended Equip/Training in past year ÷ CG members)
- `04-dashboard-queries/06-training/02-leadership-track-completion.sql` — Leadership Track L1/L2/L3 completion counts
- `04-dashboard-queries/06-training/03-dnd-participation.sql` — D&D / specialized track participation

#### Pillar 7: Mission
- `04-dashboard-queries/07-mission/01-mcpp1-completion.sql` — MCPP1 Completion % by congregation
- `04-dashboard-queries/07-mission/02-mcpp2-completion.sql` — MCPP2 Completion % by congregation
- `04-dashboard-queries/07-mission/03-mission-trip-participation.sql` — Mission Trip Participation count

#### Validation
- `04-dashboard-queries/99-validation/01-row-count-checks.sql` — row count checks across layers
- `04-dashboard-queries/99-validation/02-source-reconciliation.sql` — NCG vs Chinese Power BI dedup checks
- `04-dashboard-queries/99-validation/03-orphan-detection.sql` — orphan/missing key detection

## Steps to Implement

### Step 1: Finalize data migration to RDS
- Complete the migration of PCO tables into Alibaba Cloud RDS (see "Data Dictionary for AWS PCO DB")
- Key PCO tables: `pco_users`, `pco_groups`, `pco_group_membership`, `pco_events`, `pco_attendance`, `pco_checkin_attendance`, `pco_checkin_events`, `pco_new_decisions`, `pco_discipleship_completion`, `pco_serving_attendance`, `pco_serving_teams`, `pco_serving_teams_membership`
- Set up daily API sync using existing `run_config` / `run_log` infrastructure
- Integrate Chinese Power BI CN-specific data as supplementary tables

### Step 2: Design the star schema (data model)
- Review existing PCO data + Chinese Power BI dashboards to confirm all metrics are captured
- Map out fact tables and dimension tables as detailed in the "Raw → ETL → Analytics Flow" section above
- Document the grain of each fact table (see "Our Six Fact Tables" section)
- Start with the **Cell Group** pillar (highest number of metrics) then expand to other pillars
- Ensure CN data from Chinese Power BI integrates cleanly with NCG data (dedup strategy)

### Step 3: Set up cron job for ETL
- Create a shell script that runs the ETL SQL scripts in order (dimensions first, then facts)
- Schedule via cron on an ECS instance (e.g., daily at 4:00 AM before staff arrive)
- Add logging and basic email alerts on failure
- Consider upgrading to Alibaba Cloud DataWorks later if scheduling/monitoring needs grow

### Step 4: Create the semantic layer
- Create a `sem` schema in RDS
- Deploy the star schema tables with proper indexes
- Run the ETL cron job to populate them
- Validate data against existing dashboards for accuracy

### Step 5: Connect BI tool and rebuild dashboards
- Connect Power BI / QuickBI / new vendor to the `sem` schema (semantic layer)
- Recreate existing dashboard reports pointing to the star schema
- Rebuild dashboards organized by the **7 Pillars**:
  - **Membership**: CG size trends, staff/pastor/CG leader demographics
  - **Cell Group**: Weekly attendance (all/by zone/by CG), health analysis, submission rates, pastor & zone leader attendance, active session counts, CN-specific metrics
  - **Evangelism**: Churchwide decisions, decisions by congregation, NXG CC decisions
  - **Serving**: % actively serving, frequency tiers, CN serving/volunteer data
  - **Celebration**: Attendance by kind (Regular/Guest/Volunteer), by congregation, WoW change, assimilation
  - **Training**: Training engagement %, leadership track L1/L2/L3, D&D participation
  - **Mission**: MCPP1/MCPP2 completion %, mission trip participation
- Validate that numbers match the old dashboards

### Step 6: Testing and go-live
- Run old and new dashboards in parallel for 1-2 weeks
- Compare outputs to catch discrepancies
- Cut over once confident

## Cost Estimate

| Service | Estimated Cost |
|---------|---------------|
| RDS (already have) | Existing cost |
| Cron job (on existing ECS) | $0 (runs on existing infra) |
| DataWorks (if needed later) | Free tier likely sufficient; paid starts ~$50/mo |
| QuickBI (if chosen) | Starts ~$30/user/mo |
| **Total additional** | **~$0/mo** (cron) or **~$0-50/mo** (with DataWorks) |

Using a separate RDS schema instead of AnalyticDB keeps costs minimal — ideal for a church budget.

## Verification

- After Step 4: Run sample queries against sem tables and compare with raw data
- After Step 5: Side-by-side comparison of old vs new dashboards
- Ongoing: Monitor cron job logs for daily ETL success/failure

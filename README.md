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
>
> **SQL definitions:** [`01-raw-layer/`](01-raw-layer/) — contains the `CREATE TABLE` statements for all PCO source tables.

| Table | Description | Key Columns |
|---|---|---|
| `pco_users` | One row per person (members, visitors, staff) | user_id (PK), user_membership, user_status, user_role, user_baptized |
| `pco_groups` | Groups: Cell Groups, Leaders, Training, Ministry, etc. | grp_id (PK), grp_type_key, grp_tag_zone, grp_tag_congregation |
| `pco_group_membership` | Junction: users ↔ groups | member_id (PK), member_grp_key (FK), member_user_key (FK), member_role |
| `pco_events` | Scheduled events (CG meetings, celebrations) | event_id (PK), event_group_key (FK), event_canceled, event_att_committed_at |
| `pco_attendance` | User × event attendance records | att_event_key (FK), att_user_key (FK), att_user_role, att_status |
| `pco_checkin_events` | Check-in event definitions (services, kids church) | ce_id (PK), ce_name, ce_frequency |
| `pco_checkin_event_time` | Timing details for check-in events | cet_id (PK), cet_ce_event_key (FK), cet_total_count |
| `pco_checkin_attendance` | Individual check-in records (celebration attendance) | ca_id (PK), ca_user_key (FK), ca_ce_key (FK), ca_kind |
| `pco_new_decisions` | Evangelism decision form submissions | nd_id (PK), nd_user_key (FK), nd_form_submitted, nd_submitted_at |
| `pco_discipleship_completion` | Discipleship workflow tracking | dc_id (PK), dc_user_key (FK), dc_workflow_completion, dc_completed_at |
| `pco_serving_teams` | Serving team definitions | st_team_id (PK), st_team_name, st_service_type |
| `pco_serving_teams_membership` | Users ↔ serving teams | stm_id (PK), stm_user_key (FK), stm_team_key (FK) |
| `pco_serving_attendance` | When volunteers actually served | sa_id (PK), sa_user_key (FK), sa_team_key (FK), sa_service_date |
| `pco_rooms` | Room definitions | r_id (PK), r_name |
| `pco_room_booking` | Room booking records | rb_no (PK), rb_room_id (FK), rb_start_datetime |
| `pco_api_json` | Raw API response storage | pj_no (PK), pj_json, pj_run_key (FK) |
| `run_config` | ETL job scheduling configuration | run_id (PK), run_frequency, run_status |
| `run_log` | ETL job execution logs | rlog_id (PK), rlog_run_key (FK), rlog_run_status |

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
| 1. dim_date | `03-etl-transforms/01-dim-date.sql` | *(generated)* | Date spine: year, quarter, month, week_of_year, day_of_week, weekend_flag | INSERT ... ON CONFLICT DO NOTHING (append only) |
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

Query files in [`04-dashboard-queries/`](04-dashboard-queries/), one file per pillar with all related queries:

| File | Pillar | Key Queries |
|---|---|---|
| `01-membership.sql` | Membership | CG size by year, staff/pastor/CG leader demographics, membership ratio (Church Member % / CG Member % / Lost Sheep %) |
| `02-cell-group.sql` | Cell Group | Weekly CG attendance (all/by zone/by CG), CG health analysis, submission rate, non-submission list, pastor & zone leader attendance, active session counts |
| `03-evangelism.sql` | Evangelism | Decisions churchwide & by congregation, decision form breakdown (Outside 112029 vs Online 117917), baptisms by congregation, D101 completions |
| `04-serving.sql` | Serving | % actively serving by congregation, serving frequency tiers (High/Moderate/Low), serving by team/ministry |
| `05-celebration.sql` | Celebration | Attendance by kind (Regular/Guest/Volunteer), by congregation, week-over-week % change, NXG/activities attendance |
| `06-training.sql` | Training | Training engagement %, leadership track L1/L2/L3 completion, D&D participation |
| `07-mission.sql` | Mission | MCPP1/MCPP2 completion % by congregation, mission trip participation |
| `99-validation.sql` | Validation | Row count checks across layers, orphan/missing key detection, congregation distribution sanity check, CG attendance reconciliation |

### 4. PRESENTATION LAYER — BI Tool

- **Power BI**: Can connect to RDS via PostgreSQL connector. Works well.
- **QuickBI**: Alibaba's native tool, tightest integration, lower cost.
- **New vendor**: As long as they support PostgreSQL protocol, they can connect.

Configuration for ETL scheduling and database connections: [`05-dataworks-config/`](05-dataworks-config/)

## Steps to Implement

### Step 1: Finalize data migration to RDS
- Complete the migration of PCO tables into Alibaba Cloud RDS (see "Data Dictionary for AWS PCO DB")
- Key PCO tables: `pco_users`, `pco_groups`, `pco_group_membership`, `pco_events`, `pco_attendance`, `pco_checkin_attendance`, `pco_checkin_events`, `pco_new_decisions`, `pco_discipleship_completion`, `pco_serving_attendance`, `pco_serving_teams`, `pco_serving_teams_membership`
- Set up daily API sync using existing `run_config` / `run_log` infrastructure
- Integrate Chinese Power BI CN-specific data as supplementary tables

### Step 2: Design the star schema (data model)
- Review existing PCO data + Chinese Power BI dashboards to confirm all metrics are captured
- Map out fact tables and dimension tables as detailed in the "Raw → ETL → Analytics Flow" section above
- Document the grain of each fact table (see star schema summary table above)
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

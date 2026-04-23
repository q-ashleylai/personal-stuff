-- ============================================================
-- DUMC Analytics Dashboard — SEMANTIC LAYER (Star Schema)
-- Source: PCO (Planning Center Online) raw tables
-- This is the schema the BI tool connects to.
-- ============================================================

CREATE SCHEMA IF NOT EXISTS sem;

-- ============================================================
-- DIMENSION TABLES
-- ============================================================

-- --------------------------
-- dim_date — Date spine for time-based slicing
-- --------------------------
CREATE TABLE sem.dim_date (
    date_key       INT PRIMARY KEY,           -- YYYYMMDD, e.g. 20260418
    full_date      DATE NOT NULL UNIQUE,
    year           SMALLINT NOT NULL,
    quarter        SMALLINT NOT NULL,
    month          SMALLINT NOT NULL,
    month_name     VARCHAR(10) NOT NULL,       -- 'January', etc.
    week_of_year   SMALLINT NOT NULL,
    day_of_month   SMALLINT NOT NULL,
    day_of_week    SMALLINT NOT NULL,          -- 0=Sun, 1=Mon, ..., 6=Sat
    day_name       VARCHAR(10) NOT NULL,       -- 'Sunday', etc.
    weekend_flag   BOOLEAN NOT NULL,

    INDEX idx_year_month (year, month),
    INDEX idx_week (year, week_of_year)
);

-- --------------------------
-- dim_congregation — Lookup for congregation codes
-- One row per congregation type (EN, BM, CN, etc.)
-- --------------------------
CREATE TABLE sem.dim_congregation (
    congregation_key   SMALLINT PRIMARY KEY AUTO_INCREMENT,
    congregation_code  VARCHAR(10) NOT NULL UNIQUE,  -- 'EN', 'BM', 'CN', 'MM', 'NP', 'TM', 'FP', 'NXG'
    congregation_label VARCHAR(50) NOT NULL           -- 'English', 'Bahasa Malaysia', 'Chinese', etc.
);

-- Seed data
INSERT INTO sem.dim_congregation (congregation_code, congregation_label) VALUES
    ('EN', 'English'),
    ('BM', 'Bahasa Malaysia'),
    ('CN', 'Chinese'),
    ('MM', 'Myanmar'),
    ('NP', 'Nepali'),
    ('TM', 'Tamil'),
    ('FP', 'Filipino'),
    ('NXG', 'Next Generation');

-- --------------------------
-- dim_member — One row per person
-- Source: pco_users
-- --------------------------
CREATE TABLE sem.dim_member (
    member_key         INT PRIMARY KEY,            -- = pco_users.user_id
    first_name         VARCHAR(100) NOT NULL,
    last_name          VARCHAR(100) NOT NULL,
    full_name          VARCHAR(200) NOT NULL,
    gender             VARCHAR(10),                -- 'Male', 'Female', NULL
    date_of_birth      DATE,
    age_group          VARCHAR(20),                -- '12 and below', '13-17', '18-23', '24-35', '36-50', '51-65', '66 and above'
    membership         VARCHAR(50),                -- 'Church Member', 'Cell Member', 'Visitor', etc.
    user_role          VARCHAR(50),                -- 'Pastor', 'Zone Leader', 'Cell Group Leader', etc.
    user_status        VARCHAR(20) NOT NULL,        -- 'active', 'inactive'
    is_baptized        BOOLEAN,
    congregation_key   SMALLINT,                   -- FK dim_congregation (primary congregation)
    created_at         DATE,

    INDEX idx_membership (membership),
    INDEX idx_role (user_role),
    INDEX idx_congregation (congregation_key),
    INDEX idx_status (user_status),
    INDEX idx_age_group (age_group)
);

-- --------------------------
-- dim_cell_group — One row per cell group
-- Source: pco_groups WHERE grp_type_key = 137505
-- --------------------------
CREATE TABLE sem.dim_cell_group (
    cg_key             INT PRIMARY KEY,            -- = pco_groups.grp_id
    cg_name            VARCHAR(100) NOT NULL,
    congregation_key   SMALLINT,                   -- FK dim_congregation (from grp_tag_congregation)
    zone               VARCHAR(100),               -- from grp_tag_zone, e.g. 'EN PJS1'
    district           VARCHAR(100),               -- from grp_tag_district, e.g. 'BM - District 1'
    subzone            VARCHAR(100),               -- from grp_tag_subzone
    zone_leader        VARCHAR(200),               -- from grp_zone_leader
    leader_member_key  INT,                        -- FK dim_member (from grp_leader_user_key)
    age_group          VARCHAR(100),               -- from grp_tag_age_group
    frequency          VARCHAR(50),                -- from grp_tag_freq: 'Weekly', 'Monthly', etc.
    cg_size            INT NOT NULL,               -- from grp_size
    status             VARCHAR(20),                -- NULL, 'NEW', 'ARCHIEVED'

    INDEX idx_congregation (congregation_key),
    INDEX idx_zone (zone),
    INDEX idx_leader (leader_member_key)
);

-- ============================================================
-- FACT TABLES
-- ============================================================

-- --------------------------
-- fact_cg_attendance — Grain: one row per member per CG event
-- Source: pco_attendance + pco_events + pco_groups (type_key=137505)
-- Pillars: Cell Group, Membership (lost sheep calc)
-- --------------------------
CREATE TABLE sem.fact_cg_attendance (
    id                 BIGINT PRIMARY KEY AUTO_INCREMENT,
    date_key           INT NOT NULL,               -- FK dim_date
    member_key         INT NOT NULL,               -- FK dim_member (att_user_key)
    cg_key             INT NOT NULL,               -- FK dim_cell_group (att_group_key)
    event_id           INT NOT NULL,               -- pco_events.event_id
    attended           BOOLEAN NOT NULL,            -- att_status: '1'=true, '0'=false
    user_role          VARCHAR(20) NOT NULL,        -- att_user_role: 'member', 'visitor', 'leader'

    INDEX idx_date (date_key),
    INDEX idx_member (member_key),
    INDEX idx_cg (cg_key),
    INDEX idx_cg_date (cg_key, date_key)
);

-- --------------------------
-- fact_cg_submission — Grain: one row per CG per event
-- Source: pco_events + pco_groups (type_key=137505)
-- Pillar: Cell Group (submission rate, non-submission, active sessions)
-- --------------------------
CREATE TABLE sem.fact_cg_submission (
    id                 BIGINT PRIMARY KEY AUTO_INCREMENT,
    date_key           INT NOT NULL,               -- FK dim_date (event date)
    cg_key             INT NOT NULL,               -- FK dim_cell_group
    event_id           INT NOT NULL,               -- pco_events.event_id
    submitted          BOOLEAN NOT NULL,            -- event_att_committed_at IS NOT NULL
    cancelled          BOOLEAN NOT NULL,            -- event_canceled = '1'

    UNIQUE KEY uk_event (event_id),
    INDEX idx_date (date_key),
    INDEX idx_cg (cg_key),
    INDEX idx_cg_date (cg_key, date_key)
);

-- --------------------------
-- fact_decisions — Grain: one row per evangelism decision
-- Source: pco_new_decisions
-- Pillar: Evangelism
-- --------------------------
CREATE TABLE sem.fact_decisions (
    id                 BIGINT PRIMARY KEY AUTO_INCREMENT,
    date_key           INT NOT NULL,               -- FK dim_date (nd_submitted_at)
    member_key         INT,                        -- FK dim_member (nd_user_key)
    form_id            INT NOT NULL,               -- nd_form_submitted: 112029 or 117917
    form_title         VARCHAR(255) NOT NULL,       -- nd_form_title
    congregation_key   SMALLINT,                   -- FK dim_congregation (derived from user's group)

    INDEX idx_date (date_key),
    INDEX idx_form (form_id),
    INDEX idx_congregation (congregation_key)
);

-- --------------------------
-- fact_discipleship — Grain: one row per participant in workflow
-- Source: pco_discipleship_completion
-- Pillars: Evangelism (D101), Training
-- --------------------------
CREATE TABLE sem.fact_discipleship (
    id                 BIGINT PRIMARY KEY AUTO_INCREMENT,
    member_key         INT NOT NULL,               -- FK dim_member (dc_user_key)
    started_date_key   INT NOT NULL,               -- FK dim_date (dc_started_at)
    completed_date_key INT,                        -- FK dim_date (dc_completed_at, NULL if in progress)
    status             VARCHAR(50) NOT NULL,        -- 'In progress' or 'Completed'

    INDEX idx_member (member_key),
    INDEX idx_started (started_date_key),
    INDEX idx_status (status)
);

-- --------------------------
-- fact_celebration_attendance — Grain: one row per check-in
-- Source: pco_checkin_attendance + pco_checkin_events
-- Pillar: Celebration
-- --------------------------
CREATE TABLE sem.fact_celebration_attendance (
    id                 BIGINT PRIMARY KEY AUTO_INCREMENT,
    date_key           INT NOT NULL,               -- FK dim_date (ca_created_at date)
    member_key         INT,                        -- FK dim_member (ca_user_key, NULL for unlinked guests)
    checkin_event_key  INT NOT NULL,               -- pco_checkin_events.ce_id
    service_name       VARCHAR(255) NOT NULL,       -- ce_name
    kind               VARCHAR(50) NOT NULL,        -- ca_kind: 'Guest', 'Regular', 'Volunteer'
    congregation_key   SMALLINT,                   -- FK dim_congregation (derived from service name)

    INDEX idx_date (date_key),
    INDEX idx_kind (kind),
    INDEX idx_congregation (congregation_key),
    INDEX idx_date_congregation (date_key, congregation_key)
);

-- --------------------------
-- fact_serving — Grain: one row per volunteer per serve date
-- Source: pco_serving_attendance + pco_serving_teams
-- Pillar: Serving
-- --------------------------
CREATE TABLE sem.fact_serving (
    id                 BIGINT PRIMARY KEY AUTO_INCREMENT,
    date_key           INT NOT NULL,               -- FK dim_date (sa_service_date)
    member_key         INT NOT NULL,               -- FK dim_member (sa_user_key)
    team_id            INT NOT NULL,               -- pco_serving_teams.st_team_id
    team_name          VARCHAR(255) NOT NULL,       -- sa_team_name
    ministry           VARCHAR(255) NOT NULL,       -- sa_service_type (parent ministry)
    position           VARCHAR(255) NOT NULL,       -- sa_position (e.g. 'Drums')

    INDEX idx_date (date_key),
    INDEX idx_member (member_key),
    INDEX idx_team (team_id),
    INDEX idx_ministry (ministry)
);

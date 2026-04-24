-- ============================================================
-- Church Analytics Dashboard — SEMANTIC LAYER
-- Star schema: 4 dimensions + 6 fact tables
-- Target schema for BI tool queries
-- ============================================================

CREATE SCHEMA IF NOT EXISTS sem;

-- ============================================================
-- DIMENSIONS
-- ============================================================

-- --------------------------
-- dim_date — calendar date spine
-- --------------------------
CREATE TABLE sem.dim_date (
    date_key      INTEGER PRIMARY KEY,
    full_date     DATE NOT NULL,
    year          INTEGER NOT NULL,
    quarter       INTEGER NOT NULL,
    month         INTEGER NOT NULL,
    month_name    VARCHAR(20) NOT NULL,
    week_of_year  INTEGER NOT NULL,
    day_of_month  INTEGER NOT NULL,
    day_name      VARCHAR(20) NOT NULL,
    day_of_week   INTEGER NOT NULL,
    weekend_flag  VARCHAR(10) NOT NULL
);

-- --------------------------
-- dim_congregation — 8-row seed table (static reference data)
-- --------------------------
CREATE TABLE sem.dim_congregation (
    congregation_key   INTEGER PRIMARY KEY,
    congregation_code  VARCHAR(10) NOT NULL,
    congregation_label VARCHAR(50) NOT NULL
);

INSERT INTO sem.dim_congregation (congregation_key, congregation_code, congregation_label) VALUES
    (1, 'EN',  'EN - English'),
    (2, 'BM',  'BM - Bahasa'),
    (3, 'CN',  'CN - Chinese'),
    (4, 'MM',  'MM - Myanmar'),
    (5, 'NP',  'NP - Nepali'),
    (6, 'TM',  'TM - Tamil'),
    (7, 'FP',  'FP - Filipino'),
    (8, 'NXG', 'NXG - Next Generation');

-- --------------------------
-- dim_member — one row per person
-- member_key = user_id from pco_users (no surrogate key)
-- --------------------------
CREATE TABLE sem.dim_member (
    member_key        INTEGER PRIMARY KEY,
    full_name         VARCHAR(200) NOT NULL,
    first_name        VARCHAR(100) NOT NULL,
    last_name         VARCHAR(100) NOT NULL,
    gender            VARCHAR(7),
    age_group         VARCHAR(30),
    membership        VARCHAR(100),
    user_role         VARCHAR(50),
    is_baptized       BOOLEAN NOT NULL DEFAULT FALSE,
    congregation_key  INTEGER REFERENCES sem.dim_congregation(congregation_key),
    user_status       VARCHAR(100) NOT NULL,
    created_at        VARCHAR(50) NOT NULL
);

CREATE INDEX idx_dim_member_congregation ON sem.dim_member(congregation_key);
CREATE INDEX idx_dim_member_membership ON sem.dim_member(membership);
CREATE INDEX idx_dim_member_role ON sem.dim_member(user_role);

-- --------------------------
-- dim_cell_group — one row per CG (grp_type_key = 137505 only)
-- cg_key = grp_id from pco_groups (no surrogate key)
-- --------------------------
CREATE TABLE sem.dim_cell_group (
    cg_key             INTEGER PRIMARY KEY,
    cg_name            VARCHAR(100) NOT NULL,
    zone               VARCHAR(100),
    district           VARCHAR(100),
    subzone            VARCHAR(100),
    zone_leader        VARCHAR(200),
    leader_member_key  INTEGER REFERENCES sem.dim_member(member_key),
    age_group          VARCHAR(100),
    frequency          VARCHAR(100),
    cg_size            INTEGER NOT NULL,
    status             VARCHAR(20),
    congregation_key   INTEGER REFERENCES sem.dim_congregation(congregation_key)
);

CREATE INDEX idx_dim_cg_congregation ON sem.dim_cell_group(congregation_key);
CREATE INDEX idx_dim_cg_zone ON sem.dim_cell_group(zone);

-- ============================================================
-- FACTS
-- ============================================================

-- --------------------------
-- fact_cg_attendance — one row per member per CG event
-- Pillar: Cell Group
-- --------------------------
CREATE TABLE sem.fact_cg_attendance (
    member_key  INTEGER NOT NULL REFERENCES sem.dim_member(member_key),
    cg_key      INTEGER NOT NULL REFERENCES sem.dim_cell_group(cg_key),
    date_key    INTEGER NOT NULL REFERENCES sem.dim_date(date_key),
    event_key   INTEGER NOT NULL,
    attended    INTEGER NOT NULL,
    user_role   VARCHAR(20) NOT NULL
);

CREATE INDEX idx_fact_cga_date ON sem.fact_cg_attendance(date_key);
CREATE INDEX idx_fact_cga_cg ON sem.fact_cg_attendance(cg_key);
CREATE INDEX idx_fact_cga_member ON sem.fact_cg_attendance(member_key);

-- --------------------------
-- fact_cg_submission — one row per CG per event
-- Pillar: Cell Group
-- --------------------------
CREATE TABLE sem.fact_cg_submission (
    cg_key      INTEGER NOT NULL REFERENCES sem.dim_cell_group(cg_key),
    date_key    INTEGER NOT NULL REFERENCES sem.dim_date(date_key),
    event_key   INTEGER NOT NULL,
    submitted   INTEGER NOT NULL,
    cancelled   INTEGER NOT NULL
);

CREATE INDEX idx_fact_cgs_date ON sem.fact_cg_submission(date_key);
CREATE INDEX idx_fact_cgs_cg ON sem.fact_cg_submission(cg_key);

-- --------------------------
-- fact_decisions — one row per decision form submission
-- Pillar: Evangelism
-- --------------------------
CREATE TABLE sem.fact_decisions (
    decision_key      INTEGER PRIMARY KEY,
    member_key        INTEGER REFERENCES sem.dim_member(member_key),
    date_key          INTEGER NOT NULL REFERENCES sem.dim_date(date_key),
    form_id           INTEGER NOT NULL,
    form_title        VARCHAR(255) NOT NULL,
    congregation_key  INTEGER REFERENCES sem.dim_congregation(congregation_key),
    reason            VARCHAR(1000)
);

CREATE INDEX idx_fact_dec_date ON sem.fact_decisions(date_key);
CREATE INDEX idx_fact_dec_congregation ON sem.fact_decisions(congregation_key);

-- --------------------------
-- fact_discipleship — one row per participant in discipleship workflow
-- Pillar: Evangelism, Training
-- --------------------------
CREATE TABLE sem.fact_discipleship (
    discipleship_key    INTEGER PRIMARY KEY,
    member_key          INTEGER REFERENCES sem.dim_member(member_key),
    started_date_key    INTEGER NOT NULL REFERENCES sem.dim_date(date_key),
    completed_date_key  INTEGER REFERENCES sem.dim_date(date_key),
    status              VARCHAR(50) NOT NULL
);

CREATE INDEX idx_fact_disc_started ON sem.fact_discipleship(started_date_key);
CREATE INDEX idx_fact_disc_member ON sem.fact_discipleship(member_key);

-- --------------------------
-- fact_celebration_attendance — one row per check-in
-- Pillar: Celebration
-- --------------------------
CREATE TABLE sem.fact_celebration_attendance (
    checkin_key       INTEGER PRIMARY KEY,
    member_key        INTEGER REFERENCES sem.dim_member(member_key),
    date_key          INTEGER NOT NULL REFERENCES sem.dim_date(date_key),
    kind              VARCHAR(50) NOT NULL,
    service_name      VARCHAR(1000),
    congregation_key  INTEGER REFERENCES sem.dim_congregation(congregation_key)
);

CREATE INDEX idx_fact_cel_date ON sem.fact_celebration_attendance(date_key);
CREATE INDEX idx_fact_cel_congregation ON sem.fact_celebration_attendance(congregation_key);

-- --------------------------
-- fact_serving — one row per volunteer per serve date
-- Pillar: Serving
-- --------------------------
CREATE TABLE sem.fact_serving (
    serving_key  INTEGER PRIMARY KEY,
    member_key   INTEGER REFERENCES sem.dim_member(member_key),
    date_key     INTEGER NOT NULL REFERENCES sem.dim_date(date_key),
    team_name    VARCHAR(255) NOT NULL,
    ministry     VARCHAR(255) NOT NULL,
    position     VARCHAR(255) NOT NULL
);

CREATE INDEX idx_fact_srv_date ON sem.fact_serving(date_key);
CREATE INDEX idx_fact_srv_member ON sem.fact_serving(member_key);

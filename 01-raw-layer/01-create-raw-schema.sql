-- ============================================================
-- Church Analytics Dashboard — RAW LAYER
-- Schema and table creation for PCO (Planning Center Online) source data
-- Tables match the "Data Dictionary for AWS PCO DB" document
-- Data loaded as-is from PCO API sync — no transformations
-- ============================================================

CREATE SCHEMA IF NOT EXISTS raw;

-- --------------------------
-- pco_users
-- One row per person in the church system
-- --------------------------
CREATE TABLE raw.pco_users (
    user_id            INTEGER PRIMARY KEY,
    user_anniversary   VARCHAR(100),
    user_birthdate     VARCHAR(100),
    user_child         VARCHAR(100) NOT NULL,
    user_first_name    VARCHAR(100) NOT NULL,
    user_last_name     VARCHAR(100) NOT NULL,
    user_gender        VARCHAR(7),
    user_given_name    VARCHAR(50),
    user_medical_notes VARCHAR(1000),
    user_membership    VARCHAR(100),
    user_name          VARCHAR(50) NOT NULL,
    user_nickname      VARCHAR(50),
    user_status        VARCHAR(100) NOT NULL,
    user_link          VARCHAR(200) NOT NULL,
    user_created_at    VARCHAR(50) NOT NULL,
    user_role          VARCHAR(50),
    user_work_title    VARCHAR(500),
    user_industry      VARCHAR(50),
    user_baptized      VARCHAR(10),
    user_baptism_date  VARCHAR(20)
);

-- --------------------------
-- pco_groups
-- One row per group (Cell Groups, Leaders, Training, Ministry, etc.)
-- --------------------------
CREATE TABLE raw.pco_groups (
    grp_id                       INTEGER PRIMARY KEY,
    grp_name                     VARCHAR(100) NOT NULL,
    grp_type_key                 INTEGER NOT NULL,
    grp_link                     VARCHAR(500) NOT NULL,
    grp_location                 INTEGER,
    grp_contact_email            VARCHAR(100),
    grp_leader_user_key          INTEGER REFERENCES raw.pco_users(user_id),
    grp_tag_zone                 VARCHAR(100) NOT NULL,
    grp_tag_congregation         VARCHAR(100),
    grp_tag_age_group            VARCHAR(100),
    grp_tag_freq                 VARCHAR(100),
    grp_tag_ministry             VARCHAR(100),
    grp_size                     INTEGER NOT NULL,
    grp_status                   VARCHAR(20),
    grp_zone_leader              VARCHAR(200),
    grp_tag_district             VARCHAR(100),
    grp_tag_subzone              VARCHAR(100) NOT NULL,
    grp_location_type_preference VARCHAR(20)
);

-- --------------------------
-- pco_group_membership
-- Junction: which users belong to which groups
-- --------------------------
CREATE TABLE raw.pco_group_membership (
    member_id          INTEGER PRIMARY KEY,
    member_joined_date TIMESTAMPTZ NOT NULL,
    member_role        VARCHAR(20) NOT NULL,
    member_grp_key     INTEGER REFERENCES raw.pco_groups(grp_id),
    member_user_key    INTEGER REFERENCES raw.pco_users(user_id),
    member_user_link   VARCHAR(500) NOT NULL,
    member_grp_link    VARCHAR(500) NOT NULL
);

-- --------------------------
-- pco_events
-- One row per scheduled event (CG meetings, celebrations, activities)
-- --------------------------
CREATE TABLE raw.pco_events (
    event_id                       INTEGER PRIMARY KEY,
    event_name                     VARCHAR(200) NOT NULL,
    event_group_key                INTEGER REFERENCES raw.pco_groups(grp_id),
    event_location_key             INTEGER,
    event_startdatetime            VARCHAR(30) NOT NULL,
    event_canceled                 VARCHAR(20) NOT NULL,
    event_canceled_at              VARCHAR(100),
    event_enddatetime              VARCHAR(100) NOT NULL,
    event_reminders_sent           VARCHAR(20) NOT NULL,
    event_reminders_sent_at        VARCHAR(20),
    event_description              VARCHAR(4000),
    event_att_committed_at         VARCHAR(30),
    event_job_key                  INTEGER,
    event_location_type_preference VARCHAR(20)
);

-- --------------------------
-- pco_attendance
-- One row per user per event (CG + celebration attendance)
-- --------------------------
CREATE TABLE raw.pco_attendance (
    att_event_key INTEGER REFERENCES raw.pco_events(event_id),
    att_group_key INTEGER REFERENCES raw.pco_groups(grp_id),
    att_user_key  INTEGER REFERENCES raw.pco_users(user_id),
    att_user_role VARCHAR(20) NOT NULL,
    att_status    VARCHAR(20) NOT NULL,
    att_job_date  VARCHAR(50)
);

-- --------------------------
-- pco_checkin_events
-- Check-in event definitions (celebration services, kids church, etc.)
-- --------------------------
CREATE TABLE raw.pco_checkin_events (
    ce_id          INTEGER PRIMARY KEY,
    ce_name        VARCHAR(1000) NOT NULL,
    ce_frequency   VARCHAR(50) NOT NULL,
    ce_archived_at VARCHAR(200)
);

-- --------------------------
-- pco_checkin_event_time
-- Timing details for check-in events
-- --------------------------
CREATE TABLE raw.pco_checkin_event_time (
    cet_id              INTEGER PRIMARY KEY,
    cet_day_of_week     INTEGER NOT NULL,
    cet_guest_count     INTEGER NOT NULL,
    cet_hour            INTEGER NOT NULL,
    cet_minute          INTEGER NOT NULL,
    cet_shows_at        TIMESTAMP NOT NULL,
    cet_start_at        TIMESTAMPTZ NOT NULL,
    cet_total_count     INTEGER NOT NULL,
    cet_ce_event_key    INTEGER REFERENCES raw.pco_checkin_events(ce_id),
    cet_eventperiod_key INTEGER NOT NULL
);

-- --------------------------
-- pco_checkin_attendance
-- Individual check-in records (in-person celebration attendance)
-- --------------------------
CREATE TABLE raw.pco_checkin_attendance (
    ca_id                    INTEGER PRIMARY KEY,
    ca_checked_out_at        TIMESTAMP,
    ca_confirmed_at          TIMESTAMP,
    ca_first_name            VARCHAR(200) NOT NULL,
    ca_last_name             VARCHAR(200) NOT NULL,
    ca_kind                  VARCHAR(50) NOT NULL,
    ca_number                INTEGER NOT NULL,
    ca_user_key              INTEGER REFERENCES raw.pco_users(user_id),
    ca_eventperiod_key       INTEGER NOT NULL,
    ca_ce_key                INTEGER REFERENCES raw.pco_checkin_events(ce_id),
    ca_checked_in_by_user_key  INTEGER,
    ca_checked_out_by_user_key INTEGER,
    ca_created_at            TIMESTAMPTZ NOT NULL
);

-- --------------------------
-- pco_new_decisions
-- Evangelism decision form submissions
-- --------------------------
CREATE TABLE raw.pco_new_decisions (
    nd_id             INTEGER PRIMARY KEY,
    nd_user_key       INTEGER REFERENCES raw.pco_users(user_id),
    nd_user_name      VARCHAR(255) NOT NULL,
    nd_form_submitted INTEGER NOT NULL,
    nd_form_title     VARCHAR(255) NOT NULL,
    nd_submitted_at   DATE NOT NULL,
    nd_reason         VARCHAR(1000) NOT NULL
);

-- --------------------------
-- pco_discipleship_completion
-- Discipleship workflow tracking
-- --------------------------
CREATE TABLE raw.pco_discipleship_completion (
    dc_id                    INTEGER PRIMARY KEY,
    dc_user_key              INTEGER REFERENCES raw.pco_users(user_id),
    dc_user_name             VARCHAR(255) NOT NULL,
    dc_started_at            DATE NOT NULL,
    dc_workflow_completion   VARCHAR(50) NOT NULL,
    dc_completed_at          DATE
);

-- --------------------------
-- pco_serving_teams
-- Serving team definitions
-- --------------------------
CREATE TABLE raw.pco_serving_teams (
    st_team_id      INTEGER PRIMARY KEY,
    st_team_name    VARCHAR(255) NOT NULL,
    st_service_type VARCHAR(255) NOT NULL
);

-- --------------------------
-- pco_serving_teams_membership
-- Which users belong to which serving teams
-- --------------------------
CREATE TABLE raw.pco_serving_teams_membership (
    stm_id        INTEGER PRIMARY KEY,
    stm_user_key  INTEGER REFERENCES raw.pco_users(user_id),
    stm_team_key  INTEGER REFERENCES raw.pco_serving_teams(st_team_id),
    stm_user_name VARCHAR(255) NOT NULL
);

-- --------------------------
-- pco_serving_attendance
-- When volunteers actually served
-- --------------------------
CREATE TABLE raw.pco_serving_attendance (
    sa_id           INTEGER PRIMARY KEY,
    sa_plan         INTEGER NOT NULL,
    sa_user_key     INTEGER REFERENCES raw.pco_users(user_id),
    sa_team_key     INTEGER REFERENCES raw.pco_serving_teams(st_team_id),
    sa_user_name    VARCHAR(255) NOT NULL,
    sa_team_name    VARCHAR(255) NOT NULL,
    sa_service_type VARCHAR(255) NOT NULL,
    sa_position     VARCHAR(255) NOT NULL,
    sa_service_date DATE NOT NULL
);

-- --------------------------
-- pco_rooms
-- Room definitions
-- --------------------------
CREATE TABLE raw.pco_rooms (
    r_id        INTEGER PRIMARY KEY,
    r_name      VARCHAR(100) NOT NULL,
    r_path_name VARCHAR(500) NOT NULL
);

-- --------------------------
-- pco_room_booking
-- Room booking records
-- --------------------------
CREATE TABLE raw.pco_room_booking (
    rb_no             INTEGER PRIMARY KEY,
    rb_event_key      INTEGER NOT NULL,
    rb_start_datetime TIMESTAMPTZ NOT NULL,
    rb_end_datetime   TIMESTAMPTZ NOT NULL,
    rb_room_id        INTEGER REFERENCES raw.pco_rooms(r_id)
);

-- --------------------------
-- pco_api_json
-- Raw API response storage
-- --------------------------
CREATE TABLE raw.pco_api_json (
    pj_no          INTEGER PRIMARY KEY,
    pj_datetime    TIMESTAMP NOT NULL,
    pj_json        JSONB NOT NULL,
    pj_curl_link   VARCHAR(1000),
    pj_job_id      INTEGER,
    pj_run_key     INTEGER REFERENCES raw.run_config(run_id),
    pj_part        INTEGER,
    pj_hash_status VARCHAR(10)
);

-- --------------------------
-- run_config
-- ETL job scheduling configuration
-- --------------------------
CREATE TABLE raw.run_config (
    run_id             INTEGER PRIMARY KEY,
    run_name           VARCHAR(100) NOT NULL,
    run_curl           VARCHAR(2048) NOT NULL,
    run_procedure      INTEGER NOT NULL,
    run_sequence       INTEGER NOT NULL,
    run_frequency      VARCHAR(10) NOT NULL,
    run_status         BOOLEAN NOT NULL,
    run_at             VARCHAR(20) NOT NULL,
    run_insert_sql     VARCHAR(4000) NOT NULL,
    run_table          VARCHAR(4000) NOT NULL,
    run_need_staging   BOOLEAN NOT NULL,
    run_load_method    INTEGER NOT NULL,
    run_load_datefield VARCHAR(150)
);

-- --------------------------
-- run_log
-- ETL job execution logs
-- --------------------------
CREATE TABLE raw.run_log (
    rlog_id        INTEGER PRIMARY KEY,
    rlog_timestamp TIMESTAMP NOT NULL,
    rlog_run_key   INTEGER REFERENCES raw.run_config(run_id),
    rlog_run_status VARCHAR(10) NOT NULL
);

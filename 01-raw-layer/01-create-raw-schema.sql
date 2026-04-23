-- ============================================================
-- Church Analytics Dashboard — RAW LAYER
-- Schema and table creation for source data (as-is from migration)
-- ============================================================

CREATE SCHEMA IF NOT EXISTS raw;

-- --------------------------
-- Members
-- --------------------------
CREATE TABLE raw.members (
    member_id         INT PRIMARY KEY,
    first_name        VARCHAR(100),
    last_name         VARCHAR(100),
    email             VARCHAR(255),
    phone             VARCHAR(50),
    date_of_birth     DATE,
    gender            VARCHAR(10),
    join_date         DATE,
    membership_status VARCHAR(20),   -- 'active', 'inactive', 'visitor', 'transferred'
    address           VARCHAR(255),
    campus            VARCHAR(50),
    created_at        DATETIME,
    updated_at        DATETIME
);

-- --------------------------
-- Congregations
-- --------------------------
CREATE TABLE raw.congregations (
    congregation_id   INT PRIMARY KEY,
    congregation_date DATE,
    congregation_time TIME,
    congregation_type VARCHAR(50),   -- 'english', 'chinese', 'bm', 'tamil', 'youth', 'special'
    campus            VARCHAR(50),
    speaker           VARCHAR(100),
    language          VARCHAR(20),   -- 'English', 'Chinese', 'BM', 'Tamil'
    created_at        DATETIME
);

-- --------------------------
-- Attendance Records
-- --------------------------
CREATE TABLE raw.attendance_records (
    attendance_id   INT PRIMARY KEY,
    member_id       INT,
    congregation_id INT,
    check_in_time   DATETIME,
    check_in_method VARCHAR(20),   -- 'manual', 'qr_code', 'app', 'kiosk'
    created_at      DATETIME
);

-- --------------------------
-- Ministries
-- --------------------------
CREATE TABLE raw.ministries (
    ministry_id      INT PRIMARY KEY,
    ministry_name    VARCHAR(100),
    ministry_type    VARCHAR(50),   -- 'serving', 'fellowship', 'discipleship'
    leader_member_id INT,
    status           VARCHAR(20)
);

-- --------------------------
-- Ministry Members (junction table)
-- --------------------------
CREATE TABLE raw.ministry_members (
    ministry_member_id INT PRIMARY KEY,
    ministry_id        INT,
    member_id          INT,
    role               VARCHAR(50),   -- 'leader', 'volunteer', 'member'
    joined_date        DATE,
    left_date          DATE
);

-- --------------------------
-- Cell Groups
-- --------------------------
CREATE TABLE raw.cell_groups (
    group_id         INT PRIMARY KEY,
    group_name       VARCHAR(100),
    group_type       VARCHAR(50),   -- 'bible_study', 'prayer', 'fellowship', 'youth'
    leader_member_id INT,
    campus           VARCHAR(50),
    meeting_day      VARCHAR(10),
    status           VARCHAR(20)
);

-- --------------------------
-- Cell Group Members (junction table)
-- --------------------------
CREATE TABLE raw.cell_group_members (
    cg_member_id INT PRIMARY KEY,
    group_id     INT,
    member_id    INT,
    role         VARCHAR(50),   -- 'leader', 'co-leader', 'member'
    joined_date  DATE,
    left_date    DATE
);

-- --------------------------
-- Cell Group Attendance
-- --------------------------
CREATE TABLE raw.cell_group_attendance (
    cg_attendance_id INT PRIMARY KEY,
    group_id         INT,
    member_id        INT,
    meeting_date     DATE,
    attended         BOOLEAN
);

-- --------------------------
-- Events
-- --------------------------
CREATE TABLE raw.events (
    event_id    INT PRIMARY KEY,
    event_name  VARCHAR(200),
    event_type  VARCHAR(50),   -- 'retreat', 'conference', 'outreach', 'social', 'training'
    start_date  DATE,
    end_date    DATE,
    ministry_id INT,
    campus      VARCHAR(50)
);

-- --------------------------
-- Event Registrations
-- --------------------------
CREATE TABLE raw.event_registrations (
    registration_id   INT PRIMARY KEY,
    event_id          INT,
    member_id         INT,
    registration_date DATE,
    attended          BOOLEAN
);

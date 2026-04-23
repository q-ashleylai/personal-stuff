#!/bin/bash
# ============================================================
# Church Analytics Dashboard — Daily ETL Runner
# Runs all ETL scripts in dependency order
# Schedule via cron: 0 4 * * * /path/to/run-etl.sh
# ============================================================

set -e

# --- Configuration ---
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-3306}"
DB_USER="${DB_USER:-etl_runner}"
DB_PASS="${DB_PASS:-changeme}"
SCRIPT_DIR="$(cd "$(dirname "$0")/../03-etl-transforms" && pwd)"
VALIDATION_DIR="$(cd "$(dirname "$0")/../04-dashboard-queries" && pwd)"

LOG_PREFIX="[church-etl $(date '+%Y-%m-%d %H:%M:%S')]"

run_sql() {
    local label="$1"
    local file="$2"
    echo "$LOG_PREFIX Running: $label ($file)"
    mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" < "$file"
    echo "$LOG_PREFIX Completed: $label"
}

echo "$LOG_PREFIX ========== ETL START =========="

# --- Step 1: Dimensions (no dependencies between them) ---
echo "$LOG_PREFIX --- Dimensions ---"
run_sql "dim_date"         "$SCRIPT_DIR/01-dim-date.sql"
run_sql "dim_member"       "$SCRIPT_DIR/02-dim-member.sql"
run_sql "dim_congregation" "$SCRIPT_DIR/03-dim-congregation.sql"
run_sql "dim_ministry"     "$SCRIPT_DIR/04-dim-ministry.sql"

# --- Step 2: Facts (depend on dimensions) ---
echo "$LOG_PREFIX --- Facts ---"
run_sql "fact_attendance"          "$SCRIPT_DIR/05-fact-attendance.sql"
run_sql "fact_member_engagement"   "$SCRIPT_DIR/06-fact-member-engagement.sql"

# --- Step 3: Validation ---
echo "$LOG_PREFIX --- Validation ---"
run_sql "validation_queries" "$VALIDATION_DIR/03-validation-queries.sql"

echo "$LOG_PREFIX ========== ETL COMPLETE =========="

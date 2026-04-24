#!/bin/bash
# ============================================================
# Church Analytics Dashboard — Daily ETL Runner
# Runs all ETL scripts in dependency order
# Schedule via cron: 0 4 * * * /path/to/run-etl.sh
# ============================================================

set -e

# --- Configuration ---
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_USER="${DB_USER:-etl_runner}"
DB_NAME="${DB_NAME:-church_analytics}"
SCRIPT_DIR="$(cd "$(dirname "$0")/../03-etl-transforms" && pwd)"
VALIDATION_DIR="$(cd "$(dirname "$0")/../04-dashboard-queries" && pwd)"

LOG_PREFIX="[church-etl $(date '+%Y-%m-%d %H:%M:%S')]"

run_sql() {
    local label="$1"
    local file="$2"
    echo "$LOG_PREFIX Running: $label ($file)"
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f "$file"
    echo "$LOG_PREFIX Completed: $label"
}

echo "$LOG_PREFIX ========== ETL START =========="

# --- Step 1: Dimensions (no dependencies between them) ---
echo "$LOG_PREFIX --- Dimensions ---"
run_sql "dim_date"       "$SCRIPT_DIR/01-dim-date.sql"
run_sql "dim_member"     "$SCRIPT_DIR/02-dim-member.sql"
run_sql "dim_cell_group" "$SCRIPT_DIR/03-dim-cell-group.sql"
# dim_congregation is seed data in 02-semantic-layer/01-create-sem-schema.sql (no daily ETL)

# --- Step 2: Facts (depend on dimensions) ---
echo "$LOG_PREFIX --- Facts ---"
run_sql "fact_cg_attendance"           "$SCRIPT_DIR/04-fact-cg-attendance.sql"
run_sql "fact_cg_submission"           "$SCRIPT_DIR/05-fact-cg-submission.sql"
run_sql "fact_decisions"               "$SCRIPT_DIR/06-fact-decisions.sql"
run_sql "fact_discipleship"            "$SCRIPT_DIR/07-fact-discipleship.sql"
run_sql "fact_celebration_attendance"   "$SCRIPT_DIR/08-fact-celebration-attendance.sql"
run_sql "fact_serving"                 "$SCRIPT_DIR/09-fact-serving.sql"

# --- Step 3: Validation ---
echo "$LOG_PREFIX --- Validation ---"
run_sql "validation_queries" "$VALIDATION_DIR/99-validation.sql"

echo "$LOG_PREFIX ========== ETL COMPLETE =========="

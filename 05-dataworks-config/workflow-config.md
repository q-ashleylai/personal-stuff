# ETL Workflow Configuration — Cron Job

## Cron Job Setup

### Shell Script

Use the `run-etl.sh` script (in this folder) to execute all ETL steps in order.

### Cron Schedule

Add to crontab on your ECS instance:

```bash
# Run church analytics ETL daily at 4:00 AM
0 4 * * * /path/to/church-analytics-dashboard/05-dataworks-config/run-etl.sh >> /var/log/church-etl.log 2>&1
```

### Execution Order

```
DIMENSIONS (no dependencies between them):
[01-dim-date] ─────────┐
[02-dim-member] ────────┤
[03-dim-cell-group] ────┤
dim_congregation ───────┤  (seed data — no daily ETL)
                        │
FACTS (depend on dimensions):
                        ├──→ [04-fact-cg-attendance]
                        ├──→ [05-fact-cg-submission]
                        ├──→ [06-fact-decisions]
                        ├──→ [07-fact-discipleship]
                        ├──→ [08-fact-celebration-attendance]
                        ├──→ [09-fact-serving]
                        │
                        └──→ [99-validation]
```

Dimensions run first (can be parallel), then facts (depend on dimensions), then validation.

### Alerts

On failure, the shell script logs the error and can optionally send an email alert.

### PostgreSQL Connection

The script connects to RDS (PostgreSQL) using:
- **Host**: Your RDS endpoint (e.g., `pgm-xxxxx.pg.rds.aliyuncs.com`)
- **Port**: 5432
- **Database**: `church_analytics`
- **User**: ETL user with read on `raw`, read/write on `sem`

```sql
-- Create ETL user
CREATE USER etl_runner WITH PASSWORD '<strong-password>';
GRANT USAGE ON SCHEMA raw TO etl_runner;
GRANT SELECT ON ALL TABLES IN SCHEMA raw TO etl_runner;
GRANT USAGE, CREATE ON SCHEMA sem TO etl_runner;
GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE ON ALL TABLES IN SCHEMA sem TO etl_runner;
```

### BI Tool Connection (read-only)

```sql
-- Create read-only BI user
CREATE USER bi_reader WITH PASSWORD '<strong-password>';
GRANT USAGE ON SCHEMA sem TO bi_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA sem TO bi_reader;
```

## Future Consideration

If ETL complexity grows (more fact tables, complex dependencies, retry logic, monitoring dashboards), consider migrating to **Alibaba Cloud DataWorks** for built-in scheduling, dependency management, and alerting.

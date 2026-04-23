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
[01-dim-date] ────────┐
[02-dim-member] ──────┤
[03-dim-congregation] ─┼──→ [05-fact-attendance] ──→ [validation]
[04-dim-ministry] ────┤──→ [06-fact-member-engagement] ──→ [validation]
                      └─────────────────────────────────────┘
```

Dimensions run first (can be parallel), then facts (depend on dimensions), then validation.

### Alerts

On failure, the shell script logs the error and can optionally send an email alert.

### MySQL Connection

The script connects to RDS using:
- **Host**: Your RDS endpoint (e.g., `rm-xxxxx.mysql.rds.aliyuncs.com`)
- **Port**: 3306
- **User**: ETL user with read on `raw`, read/write on `analytics`

```sql
-- Create ETL user
CREATE USER 'etl_runner'@'%' IDENTIFIED BY '<strong-password>';
GRANT SELECT ON raw.* TO 'etl_runner'@'%';
GRANT SELECT, INSERT, DELETE, DROP, CREATE ON analytics.* TO 'etl_runner'@'%';
FLUSH PRIVILEGES;
```

### BI Tool Connection (read-only)

```sql
-- Create read-only BI user
CREATE USER 'bi_reader'@'%' IDENTIFIED BY '<strong-password>';
GRANT SELECT ON analytics.* TO 'bi_reader'@'%';
FLUSH PRIVILEGES;
```

## Future Consideration

If ETL complexity grows (more fact tables, complex dependencies, retry logic, monitoring dashboards), consider migrating to **Alibaba Cloud DataWorks** for built-in scheduling, dependency management, and alerting.

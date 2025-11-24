# Monitor de Bloqueos en PostgreSQL

Consultas SQL para análisis de bloqueos, bloqueadores y tiempos de espera.

---

## 1. Ver bloqueos actuales

```sql
SELECT  
    pid,
    usename,
    application_name,
    wait_event_type,
    wait_event,
    state,
    query_start,
    now() - query_start AS running_for,
    query
FROM pg_stat_activity
WHERE wait_event_type = 'Lock'
ORDER BY query_start;
```

## 2. Identificar quién bloquea a quién

```sql
SELECT
    bl.pid AS blocked_pid,
    bl.query AS blocked_query,
    now() - bl.query_start AS blocked_duration,
    lk.pid AS blocking_pid,
    lk.query AS blocking_query,
    now() - lk.query_start AS blocking_duration
FROM pg_stat_activity bl
JOIN pg_locks bl_lk ON bl.pid = bl_lk.pid AND NOT bl_lk.granted
JOIN pg_locks lk_lk ON bl_lk.locktype = lk_lk.locktype
    AND bl_lk.DATABASE IS NOT DISTINCT FROM lk_lk.DATABASE
    AND bl_lk.relation IS NOT DISTINCT FROM lk_lk.relation
    AND bl_lk.page IS NOT DISTINCT FROM lk_lk.page
    AND bl_lk.tuple IS NOT DISTINCT FROM lk_lk.tuple
    AND bl_lk.virtualxid IS NOT DISTINCT FROM lk_lk.virtualxid
    AND bl_lk.transactionid IS NOT DISTINCT FROM lk_lk.transactionid
    AND bl_lk.classid IS NOT DISTINCT FROM lk_lk.classid
    AND bl_lk.objid IS NOT DISTINCT FROM lk_lk.objid
    AND bl_lk.objsubid IS NOT DISTINCT FROM lk_lk.objsubid
JOIN pg_stat_activity lk ON lk_lk.pid = lk.pid
WHERE bl_lk.granted = false;
```

## 3. Ver locks por tabla

```sql
SELECT 
    locktype,
    relation::regclass AS table,
    mode,
    granted,
    pid,
    pg_stat_activity.query,
    pg_stat_activity.state,
    pg_stat_activity.query_start,
    now() - pg_stat_activity.query_start AS running_for
FROM pg_locks
JOIN pg_stat_activity ON pg_locks.pid = pg_stat_activity.pid
WHERE relation IS NOT NULL
ORDER BY relation, granted DESC;
```

## 4. Tiempo de espera usando pg_blocking_pids()

```sql
SELECT
    pid,
    query,
    now() - query_start AS running_for,
    pg_blocking_pids(pid) AS blocking_pids
FROM pg_stat_activity
WHERE cardinality(pg_blocking_pids(pid)) > 0;
```

## 5. Ver sentencia del bloqueador

```sql
SELECT 
    pid,
    query_start,
    now() - query_start AS duration,
    query
FROM pg_stat_activity
WHERE pid IN (
    SELECT unnest(pg_blocking_pids(pid))
    FROM pg_stat_activity
);
```

## 6. Sesiones ejecutando más de 3 minutos

```sql
SELECT 
    pid,
    usename,
    datname,
    state,
    wait_event,
    now() - query_start AS running_for,
    query
FROM pg_stat_activity
WHERE now() - query_start > interval '3 minutes'
ORDER BY running_for DESC;
```

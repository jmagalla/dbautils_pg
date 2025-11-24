# Monitor de Bloqueos en PostgreSQL  
Consultas SQL del 1 al 6 para análisis de bloqueos, bloqueadores y tiempos de espera, con comentarios y ejemplos de salida.

---

# 1. Ver bloqueos actuales  

Esta consulta muestra todas las sesiones que se encuentran actualmente esperando un lock. Es el primer punto para detectar contención de recursos.

## Qué muestra
- Sesiones cuyo `wait_event_type = 'Lock'`.
- Tiempo que llevan esperando.
- SQL que originó la espera.

## SQL
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

## Ejemplo de salida
```
 pid  | usename  | application_name | wait_event_type | wait_event   | state  | running_for |                query
------+----------+------------------+-----------------+--------------+--------+-------------+-----------------------------------------
 9821 | reportes | psql             | Lock            | relation     | active | 00:02:13    | UPDATE usuario SET estado='A' WHERE id=1
```

---

# 2. Identificar quién bloquea a quién  

Permite identificar la relación **bloqueado → bloqueador**, incluyendo el SQL de ambos procesos.

## Qué muestra
- PID del proceso bloqueado.
- PID del proceso bloqueador.
- Tiempo de ejecución.
- Consultas involucradas en el bloqueo.

## SQL
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

## Ejemplo de salida
```
blocked_pid | blocked_duration | blocked_query                     | blocking_pid | blocking_duration | blocking_query
------------+------------------+----------------------------------+--------------+-------------------+-------------------------------------------
      9821  | 00:02:13         | UPDATE usuario SET ...           |     9773     | 00:05:41          | ALTER TABLE usuario ADD COLUMN x int
```

---

# 3. Ver locks a nivel de tabla  

Lista todos los locks activos, mostrando el tipo de lock (mode), la tabla y si está concedido.

## Qué muestra
- Locks concedidos y no concedidos.
- Tipo de lock (Share, Exclusive, RowExclusive…).
- Qué proceso tiene el lock y cuál es su consulta.

## SQL
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

## Ejemplo de salida
```
 locktype |  table   |      mode       | granted |  pid  | state  | running_for |                 query
----------+----------+-----------------+---------+-------+--------+-------------+-----------------------------------------------
 relation | usuario  | RowExclusiveLock| t       | 9773  | active | 00:05:41    | ALTER TABLE usuario ADD COLUMN x int
 relation | usuario  | AccessShareLock | f       | 9821  | active | 00:02:13    | UPDATE usuario SET ...
```

---

# 4. Ver tiempo de espera usando pg_blocking_pids()  

Consulta simple para ver si un proceso está bloqueado y quién lo bloquea.

## Qué muestra
- El PID del bloqueador.
- La consulta bloqueada.
- Tiempo de ejecución.

## SQL
```sql
SELECT
    pid,
    query,
    now() - query_start AS running_for,
    pg_blocking_pids(pid) AS blocking_pids
FROM pg_stat_activity
WHERE cardinality(pg_blocking_pids(pid)) > 0;
```

## Ejemplo de salida
```
 pid  | running_for | blocking_pids |               query
------+-------------+----------------+-----------------------------------------
 9821 | 00:02:13    | {9773}         | UPDATE usuario SET estado='A' WHERE id=1
```

---

# 5. Ver la sentencia del bloqueador  

Muestra directamente la consulta de los procesos que están bloqueando a otros.

## Qué muestra
- PID del bloqueador.
- Consulta activa.
- Tiempo de ejecución.

## SQL
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

## Ejemplo de salida
```
 pid  | duration |                 query
------+----------+----------------------------------------------
 9773 | 00:05:41 | ALTER TABLE usuario ADD COLUMN x int
```

---

# 6. Ver sesiones que llevan más de X tiempo ejecutando  

Ayuda a detectar consultas largas que pueden causar bloqueos o retenciones de recursos.

## Qué muestra
- Sesiones activas por más de 3 minutos.
- Estado, evento de espera y consulta ejecutada.

## SQL
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

## Ejemplo de salida
```
 pid  | usename  |    state    | running_for |               query
------+----------+-------------+-------------+-----------------------------------------
 9773 | admin    | active      | 00:05:41    | ALTER TABLE usuario ADD COLUMN x int
 9821 | reportes | active      | 00:02:13    | UPDATE usuario SET ...
```

---

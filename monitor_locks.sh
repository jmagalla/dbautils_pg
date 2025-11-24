# CONFIGURACIÓN
PGUSER="admpsql"
PGDB="postgres"
PGHOST="localhost"
PGPORT="5432"

INTERVAL=10   # segundos

clear
echo "===== Monitor de Bloqueos PostgreSQL (cada $INTERVAL s) ====="
echo ""

while true; do
    date '+%Y-%m-%d %H:%M:%S'
    echo "------------------------------------------------------------"
    echo "  Sesiones bloqueadas"
    echo "------------------------------------------------------------"

    psql "postgresql://$PGUSER@$PGHOST:$PGPORT/$PGDB" -X -A -F ' | ' -c "
        SELECT 
            pid,
            now() - query_start AS wait_time,
            pg_blocking_pids(pid) AS blockers,
            state,
            wait_event_type,
            wait_event
        FROM pg_stat_activity
        WHERE cardinality(pg_blocking_pids(pid)) > 0;
    "

    echo ""
    echo "------------------------------------------------------------"
    echo "  Relación bloqueado → bloqueador (queries)"
    echo "------------------------------------------------------------"

    psql "postgresql://$PGUSER@$PGHOST:$PGPORT/$PGDB" -X -A -F ' | ' -c "
        SELECT
            bl.pid AS blocked_pid,
            now() - bl.query_start AS blocked_for,
            LEFT(bl.query,200) AS blocked_query,
            lk.pid AS blocking_pid,
            now() - lk.query_start AS blocking_for,
            LEFT(lk.query,200) AS blocking_query
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
    "

    echo ""
    echo "------------------------------------------------------------"
    echo "  Locks activos por tabla"
    echo "------------------------------------------------------------"

    psql "postgresql://$PGUSER@$PGHOST:$PGPORT/$PGDB" -X -A -F ' | ' -c "
        SELECT 
            locktype,
            relation::regclass AS table,
            mode,
            granted,
            pid
--            , LEFT(pg_stat_activity.query,150) AS query
        FROM pg_locks
        JOIN pg_stat_activity USING (pid)
        WHERE relation IS NOT NULL
        ORDER BY granted DESC, relation;
    "

    echo ""
    echo "============================================================"
    sleep $INTERVAL
    clear
done

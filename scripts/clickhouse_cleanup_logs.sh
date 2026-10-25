#!/bin/bash
# =============================================================================
# clickhouse_cleanup_logs.sh - Drop stale ClickHouse system log tables
# =============================================================================
# When the ClickHouse image is upgraded and a system log schema changes, the
# server renames the old table to <name>_N (e.g. trace_log_1) and creates a new
# one. Renamed tables are never written to or dropped, and often have no TTL,
# so they accumulate forever. This script drops them, plus tables of logs that
# are disabled in clickhouse/config.d/system_log_ttl.xml.
#
# Usage: Called automatically by apply_update.sh, or: bash scripts/clickhouse_cleanup_logs.sh
# =============================================================================

set -e

source "$(dirname "$0")/utils.sh"
init_paths
load_env

# Logs disabled via remove="1" in clickhouse/config.d/system_log_ttl.xml
DISABLED_LOGS="'trace_log','opentelemetry_span_log','query_metric_log'"

if ! is_profile_active "langfuse"; then
    exit 0
fi

ch_query() {
    docker exec -i clickhouse sh -c 'clickhouse-client -u "$CLICKHOUSE_USER" --password "$CLICKHOUSE_PASSWORD" -n'
}

# Wait for ClickHouse to accept queries (it may still be starting after an update)
for _ in $(seq 1 30); do
    if echo "SELECT 1" | ch_query >/dev/null 2>&1; then
        break
    fi
    sleep 2
done

tables=$(echo "SELECT name FROM system.tables WHERE database = 'system' AND (match(name, '_log_[0-9]+\$') OR name IN ($DISABLED_LOGS))" | ch_query) || {
    log_warning "ClickHouse is not reachable, skipping system log cleanup."
    exit 0
}

if [ -z "$tables" ]; then
    exit 0
fi

for table in $tables; do
    echo "DROP TABLE IF EXISTS system.\`$table\` SYNC" | ch_query
done
log_success "Dropped stale ClickHouse system log tables: $(echo $tables | tr ' ' ',')"

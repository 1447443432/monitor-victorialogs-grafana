#!/bin/sh
set -e

###############################################################################
# All-in-one Entrypoint
# - VictoriaLogs
# - Grafana
###############################################################################

export TZ="${TZ:-Asia/Shanghai}"
export GOMEMLIMIT="${GOMEMLIMIT:-2GiB}"
export MONITOR_AUTH_USERNAME="${MONITOR_AUTH_USERNAME:-myuser}"
export MONITOR_AUTH_PASSWORD="${MONITOR_AUTH_PASSWORD:-mypassword}"
MONITOR_SERVICES="${MONITOR_SERVICES:-all}"

case "$MONITOR_SERVICES" in
  all) START_VL=true; START_GF=true ;;
  victorialogs) START_VL=true; START_GF=false ;;
  grafana) START_VL=false; START_GF=true ;;
  *)
    echo "Invalid MONITOR_SERVICES: $MONITOR_SERVICES (expected all, victorialogs, or grafana)." >&2
    exit 2
    ;;
esac

if [ "$START_VL" = true ]; then
  echo "============================================================================="
  echo ">>> Starting VictoriaLogs..."
  echo "============================================================================="

  /usr/local/victorialogs/victoria-logs-prod \
    -storageDataPath="${VL_STORAGE_DATA_PATH:-/data/victorialogs}" \
    -httpListenAddr="${VL_HTTP_LISTEN_ADDR:-:9428}" \
    -httpAuth.username="$MONITOR_AUTH_USERNAME" \
    -httpAuth.password="$MONITOR_AUTH_PASSWORD" \
    -retentionPeriod="${VL_RETENTION_PERIOD:-30d}" \
    -retention.maxDiskSpaceUsageBytes="${VL_RETENTION_DISK_USAGE:-50GiB}" \
    -memory.allowedPercent="${VL_MEMORY_ALLOWED_PERCENT:-2}" \
    -maxConcurrentInserts="${VL_MAX_CONCURRENT_INSERTS:-4}" \
    -search.maxConcurrentRequests="${VL_MAX_CONCURRENT_REQUESTS:-2}" \
    -search.maxQueryDuration="${VL_SEARCH_MAX_QUERY_DURATION:-30s}" \
    -search.maxQueryTimeRange="${VL_SEARCH_MAX_QUERY_TIMERANGE:-24h}" \
    -search.maxQueueDuration="${VL_SEARCH_MAX_QUEUE_DURATION:-5s}" \
    -search.logSlowQueryDuration="${VL_SEARCH_LOG_SLOW_QUERY_DURATION:-3s}" \
    -insert.maxLineSizeBytes="${VL_INSERT_MAX_LINE_SIZE_BYTES:-262144}" \
    -insert.maxFieldsPerLine="${VL_INSERT_MAX_FIELDS_PER_LINE:-300}" \
    -syslog.extraFields.tcp="${VL_SYSLOG_EXTRA_FIELDS_TCP:-{\"job\":\"rsyslog\"}}" \
    -loggerLevel="${VL_LOGGER_LEVEL:-INFO}" &

  VL_PID="$!"
else
  echo ">>> VictoriaLogs disabled (MONITOR_SERVICES=$MONITOR_SERVICES)."
fi

if [ "$START_GF" = true ]; then
  echo
  echo "============================================================================="
  echo ">>> Initializing Grafana plugins..."
  echo "============================================================================="

  mkdir -p /usr/local/grafana/data/plugins

  echo ">>> Refreshing VictoriaLogs Grafana plugin..."

  rm -rf /usr/local/grafana/data/plugins/victoriametrics-logs-datasource

  cp -r \
    /opt/grafana-plugins/victoriametrics-logs-datasource \
    /usr/local/grafana/data/plugins/

  rm -f /usr/local/grafana/data/plugins/victoriametrics-logs-datasource/MANIFEST.txt

  echo
  echo "============================================================================="
  echo ">>> Starting Grafana..."
  echo "============================================================================="

###############################################################################
# Grafana 基础配置
###############################################################################

  export GF_SERVER_ROOT_URL="${GRAFANA_SERVER_ROOT_URL:-%(protocol)s://%(domain)s:%(http_port)s/privatedeploy/mdy/monitor/grafana/}"

  export GF_SERVER_SERVE_FROM_SUB_PATH="${GRAFANA_SERVER_SERVE_FROM_SUB_PATH:-true}"

###############################################################################
# Grafana 管理员账号
###############################################################################

  export GF_SECURITY_ADMIN_USER="${GRAFANA_ADMIN_USER:-admin}"

  export GF_SECURITY_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-admin@123456}"

###############################################################################
# Grafana 插件
###############################################################################

  export GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS="${GRAFANA_ALLOW_UNSIGNED_PLUGINS:-victoriametrics-logs-datasource}"

###############################################################################
# Grafana 默认首页 Dashboard
###############################################################################

  export GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH="${GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH:-/usr/local/grafana/conf/provisioning/dashboards/home-page-tags.json}"

###############################################################################
# VictoriaLogs Datasource
###############################################################################

  export GRAFANA_VL_DATASOURCE_URL="${GRAFANA_VL_DATASOURCE_URL:-http://127.0.0.1:9428}"

  export GRAFANA_VL_BASIC_AUTH_USER="$MONITOR_AUTH_USERNAME"

  export GRAFANA_VL_BASIC_AUTH_PASSWORD="$MONITOR_AUTH_PASSWORD"

###############################################################################
# 启动 Grafana
###############################################################################

  /usr/local/grafana/bin/grafana \
    server \
    --homepath=/usr/local/grafana &

  GF_PID="$!"
else
  echo ">>> Grafana disabled (MONITOR_SERVICES=$MONITOR_SERVICES)."
fi

echo
echo "============================================================================="
echo ">>> HAP Monitor Started"
echo "============================================================================="

###############################################################################
# 优雅退出
###############################################################################

trap 'kill "${VL_PID:-}" "${GF_PID:-}" 2>/dev/null || true; wait' TERM INT

###############################################################################
# 进程守护
###############################################################################

while true; do

  if [ "$START_VL" = true ] && ! kill -0 "$VL_PID" 2>/dev/null; then
    echo ">>> VictoriaLogs exited."
    exit 1
  fi

  if [ "$START_GF" = true ] && ! kill -0 "$GF_PID" 2>/dev/null; then
    echo ">>> Grafana exited."
    exit 1
  fi

  sleep 3

done

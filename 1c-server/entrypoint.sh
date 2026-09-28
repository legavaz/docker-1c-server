#!/bin/bash
set -euo pipefail

V8_VERSION="${V8_VERSION:-8.3.27.2342}"
V8_BIN="/opt/1cv8/x86_64/${V8_VERSION}"

ONEC_DATA_DIR="${ONEC_DATA_DIR:-/home/usr1cv8/.1cv8/1C/1cv8}"
ONEC_LOG_DIR="${ONEC_LOG_DIR:-/var/log/1c}"
ONEC_AGENT_PORT="${ONEC_AGENT_PORT:-1540}"
ONEC_REGPORT="${ONEC_REGPORT:-1541}"
ONEC_RANGE="${ONEC_RANGE:-1560:1591}"
ONEC_SECLEV="${ONEC_SECLEV:-0}"
ONEC_PING_PERIOD="${ONEC_PING_PERIOD:-1000}"
ONEC_PING_TIMEOUT="${ONEC_PING_TIMEOUT:-5000}"
ONEC_DEBUG="${ONEC_DEBUG:-}"
ONEC_START_RAS="${ONEC_START_RAS:-1}"
ONEC_RAS_PORT="${ONEC_RAS_PORT:-1545}"

if [ ! -x "${V8_BIN}/ragent" ]; then
  echo "ERROR: ragent not found at ${V8_BIN}/ragent" >&2
  exit 1
fi

mkdir -p "${ONEC_DATA_DIR}" "${ONEC_LOG_DIR}"
chown -R usr1cv8:grp1cv8 /home/usr1cv8 "${ONEC_LOG_DIR}" 2>/dev/null || true

cat <<EOF
1C:Enterprise server ${V8_VERSION}
  binary      : ${V8_BIN}/ragent
  data dir    : ${ONEC_DATA_DIR}
  log dir     : ${ONEC_LOG_DIR}
  agent port  : ${ONEC_AGENT_PORT}
  regport     : ${ONEC_REGPORT}
  rph range   : ${ONEC_RANGE}
  seclev      : ${ONEC_SECLEV}
  ras         : ${ONEC_START_RAS} (port ${ONEC_RAS_PORT})
  debug       : ${ONEC_DEBUG:-off}
EOF

DEBUG_ARGS=()
if [ -n "${ONEC_DEBUG}" ]; then
  # shellcheck disable=SC2206
  DEBUG_ARGS=(${ONEC_DEBUG})
fi

RAS_PID=""
if [ "${ONEC_START_RAS}" = "1" ] && [ -x "${V8_BIN}/ras" ]; then
  runuser -u usr1cv8 -- "${V8_BIN}/ras" cluster --port="${ONEC_RAS_PORT}" &
  RAS_PID=$!
  trap 'if [ -n "${RAS_PID}" ]; then kill "${RAS_PID}" 2>/dev/null || true; fi' TERM INT
fi

exec runuser -u usr1cv8 -- "${V8_BIN}/ragent" \
  -d "${ONEC_DATA_DIR}" \
  -port "${ONEC_AGENT_PORT}" \
  -regport "${ONEC_REGPORT}" \
  -range "${ONEC_RANGE}" \
  -seclev "${ONEC_SECLEV}" \
  -pingPeriod "${ONEC_PING_PERIOD}" \
  -pingTimeout "${ONEC_PING_TIMEOUT}" \
  "${DEBUG_ARGS[@]}"

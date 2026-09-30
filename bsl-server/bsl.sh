#!/usr/bin/env bash
# BSL Language Server (batch) helper, run this ON THE VM.
#
# Usage:
#   ./bsl.sh analyze [SUBDIR] [REPORTER...]   # analyze sources (read-only)
#   ./bsl.sh format  <SRC> [SRC...]           # format sources (writes files!)
#   ./bsl.sh version                          # server version
#   ./bsl.sh raw <args...>                    # arbitrary args to the jar
#
# Env:
#   IMAGE      image tag           (default: bsl-language-server:latest)
#   SRC_ROOT   host dir with 1C sources mounted at /work   (default: /srv/rep)
#   REPORT_DIR host dir for reports mounted at /reports    (default: /srv/bsl-reports)
#   CONFIG     path to .bsl-language-server.json            (default: <script dir>/config/.bsl-language-server.json)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${IMAGE:-bsl-language-server:latest}"
SRC_ROOT="${SRC_ROOT:-/srv/rep}"
REPORT_DIR="${REPORT_DIR:-/srv/bsl-reports}"
CONFIG="${CONFIG:-${SCRIPT_DIR}/config/.bsl-language-server.json}"

mkdir -p "${REPORT_DIR}"

DOCKER_ARGS=(
  --rm
  --user "$(id -u):$(id -g)"
  -v "${SRC_ROOT}:/work"
  -v "${REPORT_DIR}:/reports"
  -v "${CONFIG}:/config/.bsl-language-server.json:ro"
  -v bsl-cache:/home/bsl/.bsl-language-server
)

cmd="${1:-analyze}"
shift || true

case "${cmd}" in
  analyze)
    subdir="${1:-}"; shift || true
    if [ -z "${subdir}" ]; then
      echo "Использование: $0 analyze <ПОДКАТАЛОГ_В_${SRC_ROOT}> [reporter...]" >&2
      exit 1
    fi
    reporters=("$@")
    if [ "${#reporters[@]}" -eq 0 ]; then
      reporters=(json console)
    fi
    rep_args=()
    for r in "${reporters[@]}"; do rep_args+=(-r "${r}"); done
    set -x
    docker run "${DOCKER_ARGS[@]}" "${IMAGE}" \
      analyze -c /config/.bsl-language-server.json \
              -s "/work/${subdir}" \
              "${rep_args[@]}" -o /reports
    ;;
  format)
    if [ "$#" -eq 0 ]; then
      echo "Использование: $0 format <SRC> [SRC...]  (пути относительно ${SRC_ROOT})" >&2
      exit 1
    fi
    fmt_args=()
    for s in "$@"; do fmt_args+=("-s" "/work/${s}"); done
    set -x
    docker run "${DOCKER_ARGS[@]}" "${IMAGE}" format "${fmt_args[@]}"
    ;;
  version|--version|-v)
    docker run --rm "${IMAGE}" version
    ;;
  raw)
    set -x
    docker run "${DOCKER_ARGS[@]}" "${IMAGE}" "$@"
    ;;
  *)
    echo "Использование: $0 analyze|format|version|raw ..." >&2
    exit 1
    ;;
esac

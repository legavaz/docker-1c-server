#!/usr/bin/env bash
# Проверить произвольный каталог с .bsl-скриптами и получить отчёт.
# Запуск на VM. Каталог с кодом передаётся первым аргументом (любой путь на VM),
# он монтируется в контейнер как /work:ro и анализируется. Результат — /reports.
#
# Использование:
#   ./bsl-check.sh <каталог_с_bsl> [reporter...]
#   ./bsl-check.sh /srv/rep/task_git_file210 json console
#
# По умолчанию reporter: json console. Отчёты — в REPORT_DIR (default /srv/bsl-reports).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${IMAGE:-bsl-language-server:latest}"
REPORT_DIR="${REPORT_DIR:-/srv/bsl-reports}"
CONFIG="${CONFIG:-${SCRIPT_DIR}/config/.bsl-language-server.json}"

SRC="${1:-}"
if [ -z "${SRC}" ]; then
  echo "Использование: $0 <каталог_с_bsl_скриптами> [reporter...]" >&2
  exit 1
fi
shift || true

if [ ! -d "${SRC}" ]; then
  echo "ОШИБКА: каталог не найден: ${SRC}" >&2
  exit 1
fi

reporters=("$@")
if [ "${#reporters[@]}" -eq 0 ]; then
  reporters=(json console)
fi
rep_args=()
for r in "${reporters[@]}"; do rep_args+=(-r "${r}"); done

mkdir -p "${REPORT_DIR}"

echo "Проверяю: ${SRC}"
echo "Отчёты:   ${REPORT_DIR}"

docker run --rm \
  --user "$(id -u):$(id -g)" \
  -v "${SRC}:/work:ro" \
  -v "${REPORT_DIR}:/reports" \
  -v "${CONFIG}:/config/.bsl-language-server.json:ro" \
  -v bsl-cache:/home/bsl/.bsl-language-server \
  "${IMAGE}" \
  analyze -c /config/.bsl-language-server.json -s /work "${rep_args[@]}" -o /reports

echo "=== Готово. Отчёт: ${REPORT_DIR}/bsl-json.json ==="

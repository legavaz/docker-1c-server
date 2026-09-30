#!/usr/bin/env bash
# Проверить каталог ИЛИ отдельные .bsl-файлы и получить отчёт.
# Запуск на VM.
#
# Использование:
#   ./bsl-check.sh <каталог_с_bsl> [reporter...]
#   ./bsl-check.sh <файл1.bsl> [<файл2.bsl> ...] [reporter...]   # только файлы
#   ./bsl-check.sh --files <файл1> [<файл2> ...] --reporters json console
#
# Отчёты — в REPORT_DIR (default /srv/bsl-reports).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${IMAGE:-bsl-language-server:latest}"
REPORT_DIR="${REPORT_DIR:-/srv/bsl-reports}"
CONFIG="${CONFIG:-${SCRIPT_DIR}/config/.bsl-language-server.json}"

# Разбор аргументов: список путей + список репортеров (эвристика по расширению)
paths=()
reporters=()
for a in "$@"; do
  case "${a,,}" in
    *.bsl|*.os) paths+=("${a}") ;;
    json|console|junit|tslint|generic) reporters+=("${a}") ;;
    *) paths+=("${a}") ;;
  esac
done

if [ "${#paths[@]}" -eq 0 ]; then
  echo "Использование: $0 <каталог|файл.bsl> [...] [json console ...]" >&2
  exit 1
fi
if [ "${#reporters[@]}" -eq 0 ]; then
  reporters=(json console)
fi
rep_args=()
for r in "${reporters[@]}"; do rep_args+=(-r "${r}"); done

mkdir -p "${REPORT_DIR}"

# Определяем режим: все пути — файлы, или есть хотя бы один каталог.
any_dir=false
for p in "${paths[@]}"; do
  if [ ! -e "${p}" ]; then echo "ОШИБКА: не найдено: ${p}" >&2; exit 1; fi
  if [ -d "${p}" ]; then any_dir=true; fi
done

# Для анализа файлов собираем их в общий "корень" (BSL analyze принимает -s каталог).
if [ "${any_dir}" = false ]; then
  # Каждый файл получаем в отдельном подкаталоге с ЧИТАЕМЫМ именем, чтобы в отчёте
  # путь был понятным, а одноимённые модули из разных мест не конфликтовали.
  # Имя каталога — basename родительской пары (обычно имя объекта) + короткий хэш.
  stage="$(mktemp -d /tmp/bsl-files-XXXXXX)"
  for p in "${paths[@]}"; do
    h="$(printf '%s' "${p}" | md5sum | cut -c1-8)"
    parent="$(basename "$(dirname "${p}")")"
    sub="${parent}_${h}"
    mkdir -p "${stage}/${sub}"
    cp -f "${p}" "${stage}/${sub}/$(basename "${p}")"
  done
  analyze_root="${stage}"
  cleanup() { rm -rf "${stage}"; }
  trap cleanup EXIT
else
  analyze_root="${paths[0]}"
fi

echo "Проверяю: ${analyze_root}"
echo "Репортеры: ${reporters[*]}"
echo "Отчёты:    ${REPORT_DIR}"

docker run --rm \
  --user "$(id -u):$(id -g)" \
  -v "${analyze_root}:/work:ro" \
  -v "${REPORT_DIR}:/reports" \
  -v "${CONFIG}:/config/.bsl-language-server.json:ro" \
  -v bsl-cache:/home/bsl/.bsl-language-server \
  "${IMAGE}" \
  analyze -c /config/.bsl-language-server.json -s /work "${rep_args[@]}" -o /reports

echo "=== Готово. Отчёт: ${REPORT_DIR}/bsl-json.json ==="

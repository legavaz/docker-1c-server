#!/usr/bin/env bash
# Запуск смоук-теста на VM с токеном из файла .token (ничего не печатает, кроме отчёта).
set -uo pipefail
cd "$(dirname "$0")/.."
bash tests/smoke.sh "$(cat .token)" 8080

#!/usr/bin/env bash
# Смоук-тест уже развёрнутого сервиса (стек Portainer), токен берётся из файла на VM.
set -euo pipefail
cd "$(dirname "$0")"
bash smoke.sh "$(cat .token)" "${1:-8080}"

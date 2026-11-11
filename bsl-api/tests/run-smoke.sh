#!/usr/bin/env bash
# Поднять тестовый контейнер и прогнать смоук-тест (запускать на VM).
set -euo pipefail
cd /home/kali/bsl-api
bash start-test.sh
sleep 15
bash smoke.sh "$(cat /tmp/bsl-test-token)" 8080

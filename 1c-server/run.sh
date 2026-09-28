#!/usr/bin/env bash
# Start/stop 1C:Enterprise server container on the VM.
# Usage: ./run.sh up|down|logs|ps|rac
set -euo pipefail

IMAGE="${IMAGE:-1c-server:8.3.27.2342}"
NAME="${NAME:-1c-server}"

case "${1:-up}" in
  up)
    docker rm -f "${NAME}" 2>/dev/null || true
    # ВАЖНО: не добавлять --hostname при --network host — ragent падает и контейнер уходит в рестарт.
    docker run -d \
      --name "${NAME}" \
      --restart unless-stopped \
      --network host \
      -e ONEC_RANGE=1560:1591 \
      -v 1c-data:/home/usr1cv8/.1cv8 \
      -v 1c-logs:/var/log/1c \
      "${IMAGE}"
    ;;
  down)
    docker rm -f "${NAME}"
    ;;
  logs)
    docker logs -f "${NAME}"
    ;;
  ps)
    docker ps -a --filter "name=${NAME}"
    ;;
  rac)
    shift || true
    docker exec "${NAME}" /opt/1cv8/x86_64/8.3.27.2342/rac "$@"
    ;;
  *)
    echo "Usage: $0 up|down|logs|ps|rac [args]" >&2
    exit 1
    ;;
esac

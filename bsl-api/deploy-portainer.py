#!/usr/bin/env python3
"""Создать/обновить стек Portainer «bsl» из docker-compose.yml (запускать на VM).

Секреты читаются из файлов (chmod 600), а не из аргументов командной строки:
  --password-file  файл с паролем Portainer
  --token-file     файл с BSL_SERVICE_TOKEN

Пример:
  python3 deploy-portainer.py --url http://localhost:9000 --user opencode \
      --password-file ~/.portainer.pass --token-file ~/bsl-api/.token \
      --compose docker-compose.yml --stack bsl
"""

import argparse
import json
import pathlib
import sys
import urllib.error
import urllib.request


def request(method, url, data=None, headers=None):
    body = None if data is None else json.dumps(data).encode("utf-8")
    req = urllib.request.Request(url, data=body, method=method, headers=headers or {})
    if body is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            raw = resp.read().decode("utf-8")
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        raise SystemExit(f"HTTP {e.code} {method} {url}: {e.read().decode('utf-8', 'replace')[:500]}")


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--url", required=True)
    p.add_argument("--user", required=True)
    p.add_argument("--password-file", required=True, type=pathlib.Path)
    p.add_argument("--token-file", required=True, type=pathlib.Path)
    p.add_argument("--compose", required=True, type=pathlib.Path)
    p.add_argument("--stack", default="bsl")
    p.add_argument("--endpoint-name", default="local")
    args = p.parse_args()

    password = args.password_file.read_text(encoding="utf-8").strip()
    token = args.token_file.read_text(encoding="utf-8").strip()
    compose = args.compose.read_text(encoding="utf-8")
    base = args.url.rstrip("/")

    auth = request("POST", f"{base}/api/auth", {"Username": args.user, "Password": password})
    jwt = auth["jwt"]
    headers = {"Authorization": f"Bearer {jwt}"}

    endpoints = request("GET", f"{base}/api/endpoints", headers=headers)
    endpoint = next((e for e in endpoints if e.get("Name") == args.endpoint_name), endpoints[0])
    endpoint_id = endpoint["Id"]

    stacks = request("GET", f"{base}/api/stacks", headers=headers)
    existing = next((s for s in stacks if s.get("Name") == args.stack), None)

    env = [{"name": "BSL_SERVICE_TOKEN", "value": token}]
    if existing:
        payload = {"StackFileContent": compose, "Env": env, "Prune": False, "PullImage": False}
        request("PUT", f"{base}/api/stacks/{existing['Id']}?endpointId={endpoint_id}",
                payload, headers=headers)
        print(f"stack '{args.stack}' updated (id={existing['Id']})")
    else:
        payload = {"Name": args.stack, "StackFileContent": compose, "Env": env}
        res = request("POST", f"{base}/api/stacks?type=2&method=string&endpointId={endpoint_id}",
                      payload, headers=headers)
        print(f"stack '{args.stack}' created (id={res.get('Id')})")


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as e:  # noqa: BLE001
        sys.exit(f"ошибка: {e}")

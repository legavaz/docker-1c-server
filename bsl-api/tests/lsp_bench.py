#!/usr/bin/env python3
"""Замер: тёплый BSL LS (режим lsp, stdio) с hbk — время инициализации и время каждой проверки.

Запуск на VM:  python3 lsp_bench.py [N_проверок]
Ничего не сохраняет, кроме временных файлов в /tmp/lsp-bench.
"""

import json
import os
import queue
import subprocess
import sys
import threading
import time

IMAGE = "bsl-language-server:latest"
CONFIG_DIR = "/home/kali/bsl-docker/config"
PLATFORM_DIR = "/home/kali/bsl-platform/bin"
WORK_DIR = "/tmp/lsp-bench/work"
ERR_LOG = "/tmp/lsp-bench/stderr.log"

MODULE = (
    "Процедура Тест()\n"
    "    Массив = Новый Массив;\n"
    "    Массив.НесуществующийМетод();\n"
    "    Результат = СтрНайти();\n"
    "КонецПроцедуры\n"
)


class Lsp:
    """Чтение сообщений сервера в отдельном потоке, чтобы ожидание имело таймаут."""

    def __init__(self, proc):
        self.proc = proc
        self.next_id = 1
        self.inbox = queue.Queue()
        threading.Thread(target=self._reader, daemon=True).start()

    def _read_one(self):
        headers = b""
        while not headers.endswith(b"\r\n\r\n"):
            ch = self.proc.stdout.read(1)
            if not ch:
                return None
            headers += ch
        length = int(
            [h for h in headers.decode().split("\r\n") if h.lower().startswith("content-length")][0]
            .split(":", 1)[1]
        )
        return json.loads(self.proc.stdout.read(length).decode("utf-8"))

    def _reader(self):
        while True:
            msg = self._read_one()
            self.inbox.put(msg)
            if msg is None:
                return

    def send(self, msg):
        body = json.dumps(msg, ensure_ascii=False).encode("utf-8")
        self.proc.stdin.write(b"Content-Length: %d\r\n\r\n" % len(body) + body)
        self.proc.stdin.flush()

    def request(self, method, params):
        rid = self.next_id
        self.next_id += 1
        self.send({"jsonrpc": "2.0", "id": rid, "method": method, "params": params})
        return rid

    def notify(self, method, params):
        self.send({"jsonrpc": "2.0", "method": method, "params": params})

    def wait(self, predicate, timeout=180):
        deadline = time.monotonic() + timeout
        while True:
            left = deadline - time.monotonic()
            if left <= 0:
                raise TimeoutError("не дождались ответа")
            try:
                msg = self.inbox.get(timeout=left)
            except queue.Empty:
                raise TimeoutError("не дождались ответа")
            if msg is None:
                raise EOFError("сервер закрыл stdout")
            if predicate(msg):
                return msg


def main():
    runs = int(sys.argv[1]) if len(sys.argv) > 1 else 5
    os.makedirs(WORK_DIR, exist_ok=True)
    os.makedirs(os.path.dirname(ERR_LOG), exist_ok=True)

    cmd = [
        "docker", "run", "--rm", "-i",
        "-v", f"{CONFIG_DIR}:/config:ro",
        "-v", f"{PLATFORM_DIR}:/opt/1c/bin:ro",
        "-v", f"{WORK_DIR}:/work",
        IMAGE, "lsp", "-c", "/config/.bsl-language-server.json",
    ]
    err = open(ERR_LOG, "w")
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=err)
    lsp = Lsp(proc)

    t0 = time.monotonic()
    init_id = lsp.request("initialize", {
        "processId": None,
        "rootUri": "file:///work",
        "workspaceFolders": [{"uri": "file:///work", "name": "work"}],
        "capabilities": {},
    })
    lsp.wait(lambda m: m.get("id") == init_id)
    lsp.notify("initialized", {})
    print(f"init (разбор hbk, один раз): {time.monotonic() - t0:.2f} s")

    results = []
    for i in range(runs):
        uri = f"file:///work/m{i}.bsl"
        t = time.monotonic()
        lsp.notify("textDocument/didOpen", {
            "textDocument": {"uri": uri, "languageId": "bsl", "version": 1, "text": MODULE},
        })
        lsp.notify("textDocument/didSave", {"textDocument": {"uri": uri}, "text": MODULE})
        msg = lsp.wait(lambda m: m.get("method") == "textDocument/publishDiagnostics"
                       and m.get("params", {}).get("uri") == uri)
        dt = time.monotonic() - t
        # сервер может публиковать диагностики порциями: дочитываем до тишины 2 с
        quiet_until = time.monotonic() + 2.0
        while time.monotonic() < quiet_until:
            try:
                m2 = lsp.wait(lambda m: m.get("method") == "textDocument/publishDiagnostics"
                              and m.get("params", {}).get("uri") == uri, timeout=max(0.1, quiet_until - time.monotonic()))
                msg = m2
            except TimeoutError:
                break
        codes = sorted({d.get("code", {}).get("left", d.get("code")) if isinstance(d.get("code"), dict)
                        else d.get("code") for d in msg["params"]["diagnostics"]})
        results.append(dt)
        print(f"run {i + 1}: {dt:.2f} s, диагностик {len(msg['params']['diagnostics'])}, коды: {codes}")
        lsp.notify("textDocument/didClose", {"textDocument": {"uri": uri}})

    if results:
        print(f"итог: min {min(results):.2f} s, max {max(results):.2f} s, "
              f"avg {sum(results) / len(results):.2f} s (без учёта init)")

    shut_id = lsp.request("shutdown", None)
    lsp.wait(lambda m: m.get("id") == shut_id, timeout=30)
    lsp.notify("exit", None)
    proc.stdin.close()
    proc.wait(timeout=30)
    err.close()


if __name__ == "__main__":
    main()

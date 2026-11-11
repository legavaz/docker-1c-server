"""BSL check service: POST /check (текст) и POST /check/file (файл .bsl), журнал и веб-страница."""

import hmac
import json
import os
import re
import shutil
import subprocess
import time
import uuid
from pathlib import Path

from fastapi import Depends, FastAPI, File, Form, HTTPException, Request, UploadFile
from fastapi.responses import HTMLResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, Field

from .journal import TICKET_MAX, USER_MAX, Journal
from .normalize import normalize

TOKEN = os.environ.get("BSL_SERVICE_TOKEN", "")
MAX_BYTES = int(os.environ.get("BSL_MAX_BYTES", str(2 * 1024 * 1024)))
TIMEOUT_SEC = int(os.environ.get("BSL_TIMEOUT_SEC", "120"))
RETENTION_DAYS = int(os.environ.get("BSL_RETENTION_DAYS", "30"))
CONFIG = os.environ.get("BSL_CONFIG", "/config/.bsl-language-server.json")
JAVA_OPTS = os.environ.get("BSL_JAVA_OPTS", "-Xmx2g -XX:+UseSerialGC").split()
JIRA_BASE_URL = os.environ.get("BSL_JIRA_BASE_URL", "")
JAR = "/opt/bsl/bsl-language-server.jar"
WORK = Path(os.environ.get("BSL_WORK", "/tmp/bsl"))
DATA = Path(os.environ.get("BSL_DATA", "/data"))

if not TOKEN:
    raise RuntimeError("BSL_SERVICE_TOKEN не задан")

FILENAME_RE = re.compile(r"^[\w .\-]{1,120}\.(bsl|os)$", re.IGNORECASE)
CONTROL_RE = re.compile(r"[\x00-\x1f\x7f]")

app = FastAPI(title="BSL check service", version="1.0.2")
journal = Journal(DATA / "journal.db", RETENTION_DAYS)
WORK.mkdir(parents=True, exist_ok=True)


bearer = HTTPBearer(auto_error=False, description="Общий токен команды (BSL_SERVICE_TOKEN)")


def require_token(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer),
) -> None:
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise HTTPException(status_code=401, detail="нужен заголовок Authorization: Bearer <token>")
    if not hmac.compare_digest(credentials.credentials, TOKEN):
        raise HTTPException(status_code=401, detail="неверный токен")


def clean_user(raw: str | None) -> str:
    """Обязательное имя пользователя: до 150 символов, без управляющих символов."""
    value = (raw or "").strip()
    if not value:
        raise HTTPException(status_code=422, detail="поле user обязательно")
    if len(value) > USER_MAX:
        raise HTTPException(status_code=422, detail=f"поле user длиннее {USER_MAX} символов")
    if CONTROL_RE.search(value):
        raise HTTPException(status_code=422, detail="поле user содержит недопустимые символы")
    return value


def clean_ticket(raw: str | None) -> str:
    """Необязательный номер задачи: до 50 символов, пустое значение = не указан."""
    value = (raw or "").strip()
    if len(value) > TICKET_MAX:
        raise HTTPException(status_code=422, detail=f"поле ticket длиннее {TICKET_MAX} символов")
    if CONTROL_RE.search(value):
        raise HTTPException(status_code=422, detail="поле ticket содержит недопустимые символы")
    return value


def check_filename(name: str) -> str:
    base = Path(name).name
    if not FILENAME_RE.match(base):
        raise HTTPException(status_code=400, detail="допустимы только имена *.bsl и *.os")
    return base


def run_bsl(files: dict[str, bytes]) -> dict:
    job = WORK / uuid.uuid4().hex
    src, out = job / "src", job / "out"
    src.mkdir(parents=True)
    out.mkdir()
    try:
        for name, data in files.items():
            (src / name).write_bytes(data)
        cmd = ["java", *JAVA_OPTS, "-jar", JAR, "analyze",
               "-c", CONFIG, "-s", str(src), "-r", "json", "-o", str(out)]
        try:
            proc = subprocess.run(cmd, capture_output=True, text=True,
                                  timeout=TIMEOUT_SEC, encoding="utf-8", errors="replace")
        except subprocess.TimeoutExpired:
            raise HTTPException(status_code=504, detail=f"превышен таймаут {TIMEOUT_SEC} с")
        report_path = out / "bsl-json.json"
        if proc.returncode != 0 or not report_path.exists():
            tail = (proc.stderr or proc.stdout)[-800:]
            raise HTTPException(status_code=500, detail=f"ошибка анализа: {tail}")
        return json.loads(report_path.read_text(encoding="utf-8"))
    finally:
        shutil.rmtree(job, ignore_errors=True)


def do_check(request: Request, files: dict[str, bytes], source: str,
             user: str, ticket: str) -> dict:
    started = time.monotonic()
    size = sum(len(b) for b in files.values())
    if size > MAX_BYTES:
        raise HTTPException(status_code=413, detail=f"размер больше {MAX_BYTES} байт")
    if size == 0:
        raise HTTPException(status_code=400, detail="пустой вход")
    client = request.client.host if request.client else None
    filename = ", ".join(files)
    try:
        result = normalize(run_bsl(files))
        status = "ok"
    except HTTPException as e:
        journal.add({"client": client, "source": source, "filename": filename,
                     "size": size, "status": f"error:{e.status_code}", "user": user,
                     "ticket": ticket,
                     "duration_ms": int((time.monotonic() - started) * 1000)})
        raise
    duration_ms = int((time.monotonic() - started) * 1000)
    journal.add({
        "client": client, "source": source, "filename": filename, "size": size,
        "status": status, "valid": result["valid"], "user": user, "ticket": ticket,
        "errors": result["summary"]["errors"], "warnings": result["summary"]["warnings"],
        "info": result["summary"]["info"], "hints": result["summary"]["hints"],
        "duration_ms": duration_ms, "top_codes": result["top_codes"],
    })
    result["duration_ms"] = duration_ms
    result["files"] = list(files)
    result["user"] = user
    result["ticket"] = ticket or None
    return result


class TextCheck(BaseModel):
    filename: str = Field(default="Module.bsl", max_length=120)
    text: str = Field(min_length=1)
    user: str = Field(min_length=1, max_length=USER_MAX,
                      description="Имя пользователя (обязательно), до 150 символов")
    ticket: str | None = Field(default=None, max_length=TICKET_MAX,
                               description="Номер задачи в Jira (необязательно), до 50 символов")


@app.get("/health")
def health() -> dict:
    return {"status": "ok", "retention_days": RETENTION_DAYS, "timeout_sec": TIMEOUT_SEC,
            "max_bytes": MAX_BYTES, "user_max": USER_MAX, "ticket_max": TICKET_MAX,
            "jira_base_url": JIRA_BASE_URL}


@app.post("/check", dependencies=[Depends(require_token)])
def check_text(body: TextCheck, request: Request) -> dict:
    name = check_filename(body.filename)
    user = clean_user(body.user)
    ticket = clean_ticket(body.ticket)
    return do_check(request, {name: body.text.encode("utf-8")}, source="text",
                    user=user, ticket=ticket)


@app.post("/check/file", dependencies=[Depends(require_token)])
async def check_file(
    request: Request,
    file: UploadFile = File(...),
    user: str = Form(..., description="Имя пользователя (обязательно), до 150 символов"),
    ticket: str | None = Form(None, description="Номер задачи в Jira (необязательно), до 50 символов"),
) -> dict:
    name = check_filename(file.filename or "Module.bsl")
    clean_u = clean_user(user)
    clean_t = clean_ticket(ticket)
    data = await file.read(MAX_BYTES + 1)
    return do_check(request, {name: data}, source="file", user=clean_u, ticket=clean_t)


@app.get("/api/journal", dependencies=[Depends(require_token)])
def api_journal(limit: int = 100, offset: int = 0,
                user: str | None = None, ticket: str | None = None) -> list[dict]:
    limit = max(1, min(limit, 500))
    return journal.list(limit=limit, offset=max(0, offset),
                        user=(user or "").strip() or None,
                        ticket=(ticket or "").strip() or None)


@app.get("/api/stats", dependencies=[Depends(require_token)])
def api_stats(days: int = 30, user: str | None = None, ticket: str | None = None) -> dict:
    return journal.stats(days=max(1, min(days, RETENTION_DAYS)),
                         user=(user or "").strip() or None,
                         ticket=(ticket or "").strip() or None)


@app.get("/ui", response_class=HTMLResponse)
def ui() -> str:
    return (Path(__file__).parent / "ui.html").read_text(encoding="utf-8")

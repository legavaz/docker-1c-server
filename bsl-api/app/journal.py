"""Журнал проверок: SQLite, без текста кода, с ретенцией по дням.

Поля user (обязательное в API, до 150) и ticket (необязательное, до 50) — для разбивки статистики.
"""

import json
import sqlite3
from datetime import datetime, timedelta, timezone
from pathlib import Path

USER_MAX = 150
TICKET_MAX = 50

MIGRATIONS = [
    "ALTER TABLE checks ADD COLUMN user TEXT NOT NULL DEFAULT ''",
    "ALTER TABLE checks ADD COLUMN ticket TEXT NOT NULL DEFAULT ''",
    "CREATE INDEX IF NOT EXISTS idx_checks_user ON checks(user)",
    "CREATE INDEX IF NOT EXISTS idx_checks_ticket ON checks(ticket)",
]


class Journal:
    def __init__(self, db_path: Path, retention_days: int):
        self.db_path = db_path
        self.retention_days = retention_days
        db_path.parent.mkdir(parents=True, exist_ok=True)
        with self._connect() as con:
            con.execute(
                """CREATE TABLE IF NOT EXISTS checks (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    ts TEXT NOT NULL,
                    client TEXT,
                    source TEXT,
                    filename TEXT,
                    size INTEGER,
                    status TEXT,
                    valid INTEGER,
                    errors INTEGER,
                    warnings INTEGER,
                    info INTEGER,
                    hints INTEGER,
                    duration_ms INTEGER,
                    top_codes TEXT
                )"""
            )
            con.execute("CREATE INDEX IF NOT EXISTS idx_checks_ts ON checks(ts)")
            self._migrate(con)

    def _migrate(self, con: sqlite3.Connection) -> None:
        for stmt in MIGRATIONS:
            try:
                con.execute(stmt)
            except sqlite3.OperationalError as e:
                if "duplicate column" in str(e).lower():
                    continue
                raise

    def _connect(self):
        con = sqlite3.connect(self.db_path, timeout=10)
        con.row_factory = sqlite3.Row
        return con

    def add(self, row: dict) -> None:
        now = datetime.now(timezone.utc)
        cutoff = (now - timedelta(days=self.retention_days)).isoformat()
        with self._connect() as con:
            con.execute(
                """INSERT INTO checks (ts, client, source, filename, size, status, valid,
                    errors, warnings, info, hints, duration_ms, top_codes, user, ticket)
                    VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
                (
                    now.isoformat(),
                    row.get("client"),
                    row.get("source"),
                    row.get("filename"),
                    row.get("size"),
                    row.get("status"),
                    1 if row.get("valid") else 0,
                    row.get("errors", 0),
                    row.get("warnings", 0),
                    row.get("info", 0),
                    row.get("hints", 0),
                    row.get("duration_ms"),
                    json.dumps(row.get("top_codes", []), ensure_ascii=False),
                    row.get("user") or "",
                    row.get("ticket") or "",
                ),
            )
            con.execute("DELETE FROM checks WHERE ts < ?", (cutoff,))

    @staticmethod
    def _filters(user: str | None, ticket: str | None, since: str | None = None):
        clauses, params = [], []
        if since:
            clauses.append("ts >= ?")
            params.append(since)
        if user:
            clauses.append("user = ?")
            params.append(user)
        if ticket:
            clauses.append("ticket = ?")
            params.append(ticket)
        where = ("WHERE " + " AND ".join(clauses)) if clauses else ""
        return where, params

    def list(self, limit: int = 100, offset: int = 0, user: str | None = None,
             ticket: str | None = None) -> list[dict]:
        where, params = self._filters(user, ticket)
        with self._connect() as con:
            rows = con.execute(
                f"SELECT * FROM checks {where} ORDER BY id DESC LIMIT ? OFFSET ?",
                (*params, limit, offset),
            ).fetchall()
        return [dict(r) for r in rows]

    def stats(self, days: int, user: str | None = None, ticket: str | None = None) -> dict:
        since = (datetime.now(timezone.utc) - timedelta(days=days)).isoformat()
        where, params = self._filters(user, ticket, since)
        with self._connect() as con:
            total = con.execute(
                f"""SELECT COUNT(*) AS n,
                       COALESCE(SUM(valid),0) AS valid_n,
                       COALESCE(SUM(errors),0) AS errors,
                       COALESCE(SUM(warnings),0) AS warnings,
                       COALESCE(AVG(duration_ms),0) AS avg_ms
                   FROM checks {where}""",
                params,
            ).fetchone()
            per_day = con.execute(
                f"""SELECT substr(ts,1,10) AS day, COUNT(*) AS checks,
                       COALESCE(SUM(errors),0) AS errors,
                       COALESCE(SUM(warnings),0) AS warnings
                   FROM checks {where} GROUP BY day ORDER BY day""",
                params,
            ).fetchall()
            codes_rows = con.execute(
                f"SELECT top_codes FROM checks {where}", params
            ).fetchall()
            by_user = self._group(con, "user", since)
            by_ticket = self._group(con, "ticket", since)
            values = self._distinct(con, since)
        codes: dict[str, int] = {}
        for r in codes_rows:
            for code, n in json.loads(r["top_codes"] or "[]"):
                codes[code] = codes.get(code, 0) + n
        top = sorted(codes.items(), key=lambda kv: kv[1], reverse=True)[:10]
        n = total["n"]
        return {
            "days": days,
            "filter": {"user": user or None, "ticket": ticket or None},
            "checks": n,
            "valid_share": round(total["valid_n"] / n, 3) if n else None,
            "errors": total["errors"],
            "warnings": total["warnings"],
            "avg_duration_ms": round(total["avg_ms"]),
            "per_day": [dict(r) for r in per_day],
            "top_codes": top,
            "by_user": by_user,
            "by_ticket": by_ticket,
            "values": values,
        }

    @staticmethod
    def _group(con: sqlite3.Connection, column: str, since: str) -> list[dict]:
        rows = con.execute(
            f"""SELECT {column} AS key, COUNT(*) AS checks,
                   COALESCE(SUM(errors),0) AS errors,
                   COALESCE(SUM(warnings),0) AS warnings,
                   COALESCE(SUM(info),0) AS info,
                   COALESCE(SUM(hints),0) AS hints,
                   COALESCE(AVG(duration_ms),0) AS avg_ms
               FROM checks WHERE ts >= ? AND {column} <> ''
               GROUP BY {column} ORDER BY checks DESC""",
            (since,),
        ).fetchall()
        result = []
        for r in rows:
            item = dict(r)
            item["avg_duration_ms"] = round(item.pop("avg_ms"))
            result.append(item)
        return result

    @staticmethod
    def _distinct(con: sqlite3.Connection, since: str) -> dict:
        users = [r["v"] for r in con.execute(
            "SELECT DISTINCT user AS v FROM checks WHERE ts >= ? AND user <> '' ORDER BY user",
            (since,)).fetchall()]
        tickets = [r["v"] for r in con.execute(
            "SELECT DISTINCT ticket AS v FROM checks WHERE ts >= ? AND ticket <> '' ORDER BY ticket",
            (since,)).fetchall()]
        return {"users": users, "tickets": tickets}

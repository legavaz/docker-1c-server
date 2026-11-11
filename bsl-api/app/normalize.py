"""Приведение JSON-отчёта BSL Language Server к формату API."""

from collections import Counter
from urllib.parse import unquote

SEVERITY_BUCKET = {
    "Error": "errors",
    "Warning": "warnings",
    "Information": "info",
    "Hint": "hints",
}


def _file_name(path: str) -> str:
    return unquote(path).rsplit("/", 1)[-1]


def normalize(report: dict) -> dict:
    buckets = {"errors": [], "warnings": [], "info": [], "hints": []}
    codes: Counter = Counter()

    for fi in report.get("fileinfos", []):
        name = _file_name(fi.get("path", ""))
        for d in fi.get("diagnostics", []):
            severity = d.get("severity", "Information")
            start = (d.get("range") or {}).get("start") or {}
            item = {
                "file": name,
                "line": start.get("line", 0) + 1,
                "column": start.get("character", 0) + 1,
                "code": d.get("code"),
                "message": d.get("message"),
                "severity": severity,
            }
            buckets[SEVERITY_BUCKET.get(severity, "info")].append(item)
            if d.get("code"):
                codes[d["code"]] += 1

    summary = {k: len(v) for k, v in buckets.items()}
    return {
        "valid": summary["errors"] == 0,
        "summary": summary,
        "errors": buckets["errors"],
        "warnings": buckets["warnings"],
        "top_codes": codes.most_common(5),
        "text": _text_report(buckets, summary),
    }


def _text_report(buckets: dict, summary: dict) -> str:
    lines = [
        f"Ошибок: {summary['errors']}, предупреждений: {summary['warnings']}, "
        f"информации: {summary['info']}, подсказок: {summary['hints']}",
        "",
    ]
    for key, label in (("errors", "ОШИБКА"), ("warnings", "ПРЕДУПРЕЖДЕНИЕ")):
        for it in buckets[key]:
            lines.append(
                f"[{label}] {it['file']}:{it['line']}:{it['column']} "
                f"{it['code']} — {it['message']}"
            )
    if summary["errors"] == 0 and summary["warnings"] == 0:
        lines.append("Замечаний уровня ошибка и предупреждение нет.")
    return "\n".join(lines)

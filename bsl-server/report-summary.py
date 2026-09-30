import json
import sys
from collections import Counter

path = sys.argv[1] if len(sys.argv) > 1 else "/srv/bsl-reports/bsl-json.json"
with open(path, encoding="utf-8") as f:
    d = json.load(f)

files = d.get("fileinfos", [])
total = 0
sev = Counter()
codes = Counter()
for fi in files:
    for diag in fi.get("diagnostics", []):
        total += 1
        sev[diag.get("severity", "?")] += 1
        c = diag.get("code")
        if isinstance(c, dict):
            c = c.get("left") or c.get("right") or "?"
        codes[c] += 1

print("files:", len(files))
print("diagnostics:", total)
print("severity:", dict(sev))
print("top codes:")
for code, n in codes.most_common(15):
    print("  ", n, code)

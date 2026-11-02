#!/usr/bin/env bash
# Usage: scripts/check-secrets.sh [--ci]
# Scans the index: what the next commit would contain, so unstaged edits are ignored.
# Fails on: GitHub token prefixes, JWT-shaped strings, private IPv4 addresses and
# em dashes (U+2014). Without --ci it also fails on every literal in
# local/denylist.txt and on every value of 4 or more characters in
# local/Secrets.local.xcconfig, except http and https, and fails if either file
# is missing (scripts/bootstrap.sh creates them). local/ is resolved against the
# main checkout, so git worktrees work.
# --ci runs only the pattern rules, for CI where local/ does not exist.
# Prints file:line and the rule name only, never the matched value.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
if want_help "$@"; then show_usage "${BASH_SOURCE[0]}"; exit 0; fi

need_cmd python3 "Install python3."
need_cmd git "Install git."
cd "$PANE_ROOT"

ci=0
for arg in "$@"; do
  case "$arg" in
    --ci) ci=1 ;;
    *) die "unknown argument: $arg" ;;
  esac
done

common_dir="$(git rev-parse --path-format=absolute --git-common-dir)"
CHECK_SECRETS_CI="$ci" CHECK_SECRETS_LOCAL="$(dirname "$common_dir")/local" python3 - <<'PY'
import os
import re
import subprocess
import sys
from pathlib import Path

EM_DASH = chr(0x2014)
OCTET = r"(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)"
PATTERNS = [
    ("GitHub token", re.compile(r"\b(?:gh[pousr]_[A-Za-z0-9]{10,}|github_pat_[A-Za-z0-9_]{10,})")),
    ("JWT-shaped string", re.compile(r"eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.")),
    (
        "private IPv4 address",
        re.compile(
            r"(?<![\d.])(?:10\.%(o)s\.%(o)s\.%(o)s|172\.(?:1[6-9]|2\d|3[01])\.%(o)s\.%(o)s|192\.168\.%(o)s\.%(o)s)(?![\d]|\.\d)"
            % {"o": OCTET}
        ),
    ),
]
IGNORED_SECRET_VALUES = {"http", "https"}
MIN_SECRET_LENGTH = 4


def git(*args):
    return subprocess.run(["git", *args], capture_output=True, check=True).stdout


def names(raw):
    return [n for n in raw.decode("utf-8", "surrogateescape").split("\0") if n]


def read_denylist(path):
    literals = []
    for raw in path.read_text().splitlines():
        value = raw.strip()
        if value and not value.startswith("#"):
            literals.append(value)
    return literals


def read_secret_values(path):
    values = []
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("//") or "=" not in line:
            continue
        value = line.split("=", 1)[1].strip().strip("\"'")
        if len(value) >= MIN_SECRET_LENGTH and value not in IGNORED_SECRET_VALUES:
            values.append(value)
    return values


files = sorted(names(git("ls-files", "-z")))

local = Path(os.environ["CHECK_SECRETS_LOCAL"])
ci = os.environ["CHECK_SECRETS_CI"] == "1"
literals = []
if not ci:
    deny_path = local / "denylist.txt"
    secrets_path = local / "Secrets.local.xcconfig"
    missing = [p.name for p in (deny_path, secrets_path) if not p.is_file()]
    if missing:
        print("check-secrets: missing local/%s; run scripts/bootstrap.sh" % ", local/".join(missing), file=sys.stderr)
        sys.exit(1)
    literals += [(v, "value from local denylist") for v in read_denylist(deny_path)]
    literals += [(v, "value from local secrets file") for v in read_secret_values(secrets_path)]

problems = set()
for name in files:
    try:
        data = git("show", ":" + name)
    except subprocess.CalledProcessError:
        continue
    if b"\0" in data:
        continue
    text = data.decode("utf-8", "replace")
    for number, line in enumerate(text.splitlines(), start=1):
        if EM_DASH in line:
            problems.add((name, number, "em dash"))
        for rule, pattern in PATTERNS:
            if pattern.search(line):
                problems.add((name, number, rule))
        for literal, rule in literals:
            if literal in line:
                problems.add((name, number, rule))

if problems:
    for name, number, rule in sorted(problems):
        print("%s:%d: %s" % (name, number, rule))
    print("check-secrets: %d problem(s)" % len(problems), file=sys.stderr)
    sys.exit(1)

print("check-secrets: clean (%d files, %s)" % (len(files), "patterns only" if ci else "patterns and local values"))
PY

#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMP_DIR="$(mktemp -d)"
failures=0

cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

run_test() {
  local name="$1"
  shift

  if "$@"; then
    printf 'PASS: %s\n' "$name"
  else
    printf 'FAIL: %s\n' "$name" >&2
    failures=$((failures + 1))
  fi
}

check_eval_manifest() {
  python3 -m json.tool "$SKILL_DIR/evals/evals.json" >/dev/null
}

check_analysis() {
  local repo="$TEMP_DIR/analysis-repo"
  mkdir -p "$repo"

  cat > "$repo/package.json" <<'JSON'
{
  "scripts": {
    "test": "node --test",
    "build": "node build.js",
    "lint": "node lint.js"
  }
}
JSON
  touch "$repo/package-lock.json" "$repo/yarn.lock"
  mkdir -p "$repo/docs"
  touch "$repo/docs/install.md" "$repo/INSTALL.md"

  bash "$SCRIPT_DIR/analyze-repo.sh" "$repo" 2>/dev/null |
    python3 -c '
import json
import sys

data = json.load(sys.stdin)
assert data["test_command"] == "yarn test"
assert data["build_command"] == "node build.js"
assert data["lint_command"] == "node lint.js"
assert data["lockfiles"] == ["package-lock.json", "yarn.lock"]
assert data["install_docs"] == ["docs/install.md", "INSTALL.md"]
'
}

check_verification_plan() {
  local repo="$TEMP_DIR/verification-repo"
  mkdir -p "$repo/.agent-setup"

  cat > "$repo/.agent-setup/analyze.json" <<'JSON'
{
  "test_command": "npm test",
  "build_command": "unknown-command --check",
  "env_template": false
}
JSON
  cat > "$repo/Makefile" <<'MAKEFILE'
export VERSION := 1
override OPTION := default
%.o: %.c
test lint:
	@true
test:
	@true
MAKEFILE

  bash "$SCRIPT_DIR/verify-setup.sh" "$repo" 2>/dev/null |
    python3 -c '
import json
import sys

plan = json.load(sys.stdin)
assert plan["commands"][0]["category"] == "review"
assert plan["commands"][1]["category"] == "safe"
assert plan["makefile_targets"] == ["test", "lint"]
'
}

check_dry_run_flags() {
  local repo="$TEMP_DIR/dry-run-repo"
  mkdir -p "$repo/.agent-setup"

  cat > "$repo/.agent-setup/analyze.json" <<'JSON'
{
  "install_command": "make deploy",
  "build_command": "terraform apply",
  "test_command": "kubectl apply -f config.yaml",
  "lint_command": "npm publish",
  "env_template": false
}
JSON

  bash "$SCRIPT_DIR/verify-setup.sh" "$repo" 2>/dev/null |
    python3 -c '
import json
import sys

plan = json.load(sys.stdin)
commands = {entry["command"]: entry for entry in plan["commands"]}
assert commands["make deploy"]["dry_run_flag"] == "--dry-run"
assert commands["terraform apply"]["dry_run_flag"] == "plan"
assert commands["kubectl apply -f config.yaml"]["dry_run_flag"] == "--dry-run=client"
assert commands["npm publish"]["dry_run_flag"] == "--dry-run"
'
}

check_invalid_repo_path() {
  local invalid_path="$TEMP_DIR/missing-repo"
  local stderr_file="$TEMP_DIR/invalid-repo.stderr"

  if bash "$SCRIPT_DIR/analyze-repo.sh" "$invalid_path" >/dev/null 2>"$stderr_file"; then
    return 1
  fi

  python3 - "$stderr_file" <<'PY'
from pathlib import Path
import sys

stderr = Path(sys.argv[1]).read_text()
assert '{"error":"cannot enter repository path"}' in stderr
PY
}

run_test "eval manifest parses" check_eval_manifest
run_test "analysis detects nested scripts and lockfiles" check_analysis
run_test "verification preserves review risk and finds root Makefile" check_verification_plan
run_test "verification reports dry-run flags" check_dry_run_flags
run_test "analysis reports invalid repository paths" check_invalid_repo_path

if (( failures > 0 )); then
  exit 1
fi

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

  bash "$SCRIPT_DIR/analyze-repo.sh" "$repo" 2>/dev/null |
    python3 -c '
import json
import sys

data = json.load(sys.stdin)
assert data["test_command"] == "yarn test"
assert data["build_command"] == "node build.js"
assert data["lint_command"] == "node lint.js"
assert data["lockfiles"] == ["package-lock.json", "yarn.lock"]
'
}

check_verification_plan() {
  local repo="$TEMP_DIR/verification-repo"
  mkdir -p "$repo/.agent-setup"

  cat > "$repo/.agent-setup/analyze.json" <<'JSON'
{
  "test_command": "npm test && npm publish",
  "env_template": false
}
JSON
  cat > "$repo/Makefile" <<'MAKEFILE'
test:
	@true
lint:
	@true
MAKEFILE

  bash "$SCRIPT_DIR/verify-setup.sh" "$repo" 2>/dev/null |
    python3 -c '
import json
import sys

plan = json.load(sys.stdin)
assert plan["commands"][0]["category"] == "review"
assert plan["makefile_targets"] == ["test", "lint"]
'
}

run_test "eval manifest parses" check_eval_manifest
run_test "analysis detects nested scripts and lockfiles" check_analysis
run_test "verification preserves review risk and finds root Makefile" check_verification_plan

if (( failures > 0 )); then
  exit 1
fi

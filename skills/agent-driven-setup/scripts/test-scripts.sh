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

write_analysis_fingerprint() {
  local repo="$1"
  python3 - "$repo" <<'PY'
import hashlib
from pathlib import Path
import sys

root = Path(sys.argv[1])
digest = hashlib.sha256()
for name in ("package.json", "Makefile"):
    path = root / name
    digest.update(name.encode())
    if path.is_file():
        digest.update(b"\0present\0")
        digest.update(path.read_bytes())
    else:
        digest.update(b"\0missing\0")

output = root / ".agent-setup" / "analyze.inputs.sha256"
output.write_text(digest.hexdigest() + "\n", encoding="ascii")
PY
}

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

check_analysis_uses_package_runner_for_tests() {
  local repo="$TEMP_DIR/npm-script-repo"
  mkdir -p "$repo"

  cat > "$repo/package.json" <<'JSON'
{
  "scripts": {
    "test": "jest"
  }
}
JSON

  bash "$SCRIPT_DIR/analyze-repo.sh" "$repo" 2>/dev/null |
    python3 -c '
import json
import sys

data = json.load(sys.stdin)
assert data["test_command"] == "npm test"
'
}

check_analysis_reads_utf8_package_json() {
  local repo="$TEMP_DIR/utf8-package-repo"
  mkdir -p "$repo"

  python3 - "$repo/package.json" <<'PY'
import json
from pathlib import Path
import sys

Path(sys.argv[1]).write_bytes(
    json.dumps(
        {
            "description": "日本語",
            "scripts": {
                "build": "npm run compile",
                "lint": "npm run check",
            },
        },
        ensure_ascii=False,
    ).encode("utf-8")
)
PY

  LC_ALL=C PYTHONUTF8=0 PYTHONCOERCECLOCALE=0 \
    bash "$SCRIPT_DIR/analyze-repo.sh" "$repo" 2>/dev/null |
    python3 -c '
import json
import sys

data = json.load(sys.stdin)
assert data["build_command"] == "npm run compile"
assert data["lint_command"] == "npm run check"
'
}

check_analysis_ignores_makefile_variable_assignments() {
  local repo="$TEMP_DIR/makefile-variable-repo"
  mkdir -p "$repo"
  cat > "$repo/Makefile" <<'MAKEFILE'
test := true
build = true
lint ?= true
MAKEFILE

  bash "$SCRIPT_DIR/analyze-repo.sh" "$repo" 2>/dev/null |
    python3 -c '
import json
import sys

data = json.load(sys.stdin)
assert data["test_command"] is None
assert data["build_command"] is None
assert data["lint_command"] is None
'
}

check_analysis_detects_space_indented_test_target() {
  local repo="$TEMP_DIR/space-indented-test-repo"
  mkdir -p "$repo"
  printf '%s\n' '  test :' > "$repo/Makefile"

  bash "$SCRIPT_DIR/analyze-repo.sh" "$repo" 2>/dev/null |
    python3 -c '
import json
import sys

data = json.load(sys.stdin)
assert data["test_command"] == "make test"
'
}

check_analysis_requires_existing_lockfiles() {
  local root="$TEMP_DIR/lockfile-repos"
  local python_repo="$root/python"
  local pipenv_repo="$root/pipenv"
  local cargo_repo="$root/cargo"
  local go_repo="$root/go"
  local ruby_repo="$root/ruby"
  local pipenv_present_repo="$root/pipenv-present"
  local cargo_present_repo="$root/cargo-present"
  local go_present_repo="$root/go-present"
  local ruby_present_repo="$root/ruby-present"

  mkdir -p "$python_repo" "$pipenv_repo" "$cargo_repo" "$go_repo" \
    "$ruby_repo" "$pipenv_present_repo" "$cargo_present_repo" \
    "$go_present_repo" "$ruby_present_repo"
  touch "$python_repo/pyproject.toml"
  touch "$pipenv_repo/pyproject.toml" "$pipenv_repo/Pipfile"
  touch "$cargo_repo/Cargo.toml"
  touch "$go_repo/go.mod"
  touch "$ruby_repo/Gemfile"
  touch "$pipenv_present_repo/pyproject.toml" "$pipenv_present_repo/Pipfile" \
    "$pipenv_present_repo/Pipfile.lock"
  touch "$cargo_present_repo/Cargo.toml" "$cargo_present_repo/Cargo.lock"
  touch "$go_present_repo/go.mod" "$go_present_repo/go.sum"
  touch "$ruby_present_repo/Gemfile" "$ruby_present_repo/Gemfile.lock"

  for repo in "$python_repo" "$pipenv_repo" "$cargo_repo" "$go_repo" \
    "$ruby_repo" "$pipenv_present_repo" "$cargo_present_repo" \
    "$go_present_repo" "$ruby_present_repo"; do
    bash "$SCRIPT_DIR/analyze-repo.sh" "$repo" 2>/dev/null > "$repo/analyze.json"
  done

  python3 - "$python_repo/analyze.json" "$pipenv_repo/analyze.json" \
    "$cargo_repo/analyze.json" "$go_repo/analyze.json" \
    "$ruby_repo/analyze.json" "$pipenv_present_repo/analyze.json" \
    "$cargo_present_repo/analyze.json" "$go_present_repo/analyze.json" \
    "$ruby_present_repo/analyze.json" <<'PY'
import json
from pathlib import Path
import sys

data = [json.loads(Path(path).read_text()) for path in sys.argv[1:]]
assert data[0]["lockfiles"] == []
assert data[1]["lockfiles"] == []
assert data[2]["lockfiles"] == []
assert data[3]["lockfiles"] == []
assert data[4]["lockfiles"] == []
assert data[5]["lockfiles"] == ["Pipfile.lock"]
assert data[6]["lockfiles"] == ["Cargo.lock"]
assert data[7]["lockfiles"] == ["go.sum"]
assert data[8]["lockfiles"] == ["Gemfile.lock"]
PY
}

check_analysis_detects_git_worktree_metadata() {
  local repo="$TEMP_DIR/git-repo"
  local worktree="$TEMP_DIR/git-worktree"

  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email test@example.invalid
  git -C "$repo" config user.name "Agent Setup Test"
  touch "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -qm initial
  git -C "$repo" branch -M main
  git -C "$repo" remote add origin https://example.invalid/agent-driven-setup.git
  git -C "$repo" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
  git -C "$repo" worktree add -q -b review-worktree "$worktree" main

  [[ -f "$worktree/.git" ]] || return 1

  bash "$SCRIPT_DIR/analyze-repo.sh" "$worktree" 2>/dev/null |
    python3 -c '
import json
import sys

data = json.load(sys.stdin)
assert data["git_remote"] == "https://example.invalid/agent-driven-setup.git"
assert data["default_branch"] == "main"
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
  write_analysis_fingerprint "$repo"

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
assert commands["terraform apply"]["dry_run_flag"] is None
assert commands["terraform apply"]["dry_run_command"] == "terraform plan"
assert commands["kubectl apply -f config.yaml"]["dry_run_flag"] == "--dry-run=client"
assert commands["npm publish"]["dry_run_flag"] == "--dry-run"
'
}

check_verification_requires_command_boundaries() {
  local repo="$TEMP_DIR/command-boundary-repo"
  mkdir -p "$repo/.agent-setup"

  cat > "$repo/.agent-setup/analyze.json" <<'JSON'
{
  "install_command": "makemigrations",
  "build_command": "npm testevil",
  "test_command": "make test",
  "lint_command": "npm publish"
}
JSON

  bash "$SCRIPT_DIR/verify-setup.sh" "$repo" 2>/dev/null |
    python3 -c '
import json
import sys

plan = json.load(sys.stdin)
commands = {entry["command"]: entry for entry in plan["commands"]}
assert commands["makemigrations"]["dry_run_flag"] is None
assert commands["npm testevil"]["category"] == "review"
assert commands["make test"]["category"] == "safe"
'
}

check_verification_handles_non_utf8_makefile() {
  local repo="$TEMP_DIR/non-utf8-makefile-repo"
  mkdir -p "$repo/.agent-setup"

  cat > "$repo/.agent-setup/analyze.json" <<'JSON'
{
  "env_template": false
}
JSON
  python3 - "$repo/Makefile" <<'PY'
from pathlib import Path
import sys

Path(sys.argv[1]).write_bytes(b"# caf\xe9\ncheck:\n\t@true\n")
PY

  bash "$SCRIPT_DIR/verify-setup.sh" "$repo" 2>/dev/null |
    python3 -c '
import json
import sys

plan = json.load(sys.stdin)
assert plan["makefile_targets"] == ["check"]
'
}

check_verification_reads_utf8_analysis_json() {
  local repo="$TEMP_DIR/utf8-analysis-repo"
  mkdir -p "$repo/.agent-setup"

  python3 - "$repo/.agent-setup/analyze.json" <<'PY'
import json
from pathlib import Path
import sys

Path(sys.argv[1]).write_bytes(
    json.dumps(
        {"test_command": "npm test", "readme": "\u65e5\u672c\u8a9e"},
        ensure_ascii=False,
    ).encode("utf-8")
)
PY

  LC_ALL=C PYTHONUTF8=0 bash "$SCRIPT_DIR/verify-setup.sh" "$repo" 2>/dev/null |
    python3 -c '
import json
import sys

plan = json.load(sys.stdin)
assert plan["commands"][0]["command"] == "npm test"
'
}

check_verification_rejects_shell_syntax_in_safe_commands() {
  local repo="$TEMP_DIR/shell-syntax-repo"
  mkdir -p "$repo/.agent-setup"

  cat > "$repo/.agent-setup/analyze.json" <<'JSON'
{
  "install_command": "npm test ; printf unsafe",
  "build_command": "make check > build.log",
  "test_command": "npm test && printf unsafe | cat > test.log",
  "lint_command": "npm run lint $(printf unsafe)"
}
JSON

  bash "$SCRIPT_DIR/verify-setup.sh" "$repo" 2>/dev/null |
    python3 -c '
import json
import sys

plan = json.load(sys.stdin)
commands = {entry["command"]: entry for entry in plan["commands"]}
assert all(entry["category"] == "review" for entry in commands.values())
'
}

check_verification_reanalyzes_changed_inputs() {
  local repo="$TEMP_DIR/changed-inputs-repo"
  mkdir -p "$repo"

  cat > "$repo/package.json" <<'JSON'
{
  "scripts": {
    "lint": "npm run lint-a"
  }
}
JSON
  printf '%s\n' 'test:' > "$repo/Makefile"
  bash "$SCRIPT_DIR/verify-setup.sh" "$repo" 2>/dev/null >/dev/null

  cat > "$repo/package.json" <<'JSON'
{
  "scripts": {
    "lint": "npm run lint-b"
  }
}
JSON
  printf '%s\n' 'lint test:' > "$repo/Makefile"

  bash "$SCRIPT_DIR/verify-setup.sh" "$repo" 2>/dev/null |
    python3 -c '
import json
import sys

plan = json.load(sys.stdin)
commands = {entry["phase"]: entry["command"] for entry in plan["commands"]}
assert commands["lint"] == "npm run lint-b"
assert plan["makefile_targets"] == ["lint", "test"]
'
}

check_analysis_detects_multi_target_test_rule() {
  local repo="$TEMP_DIR/multi-target-test-repo"
  mkdir -p "$repo"
  printf '%s\n' 'test lint:' > "$repo/Makefile"

  bash "$SCRIPT_DIR/analyze-repo.sh" "$repo" 2>/dev/null |
    python3 -c '
import json
import sys

data = json.load(sys.stdin)
assert data["test_command"] == "make test"
'
}

check_analysis_detects_multi_target_rules_in_any_order() {
  local repo="$TEMP_DIR/multi-target-order-repo"
  mkdir -p "$repo"
  printf '%s\n' 'lint test build:' > "$repo/Makefile"

  bash "$SCRIPT_DIR/analyze-repo.sh" "$repo" 2>/dev/null |
    python3 -c '
import json
import sys

data = json.load(sys.stdin)
assert data["test_command"] == "make test"
assert data["build_command"] == "make build"
assert data["lint_command"] == "make lint"
'
}

check_analysis_detects_test_target_with_space_before_colon() {
  local repo="$TEMP_DIR/spaced-test-target-repo"
  mkdir -p "$repo"
  printf '%s\n' 'test :' > "$repo/Makefile"

  bash "$SCRIPT_DIR/analyze-repo.sh" "$repo" 2>/dev/null |
    python3 -c '
import json
import sys

data = json.load(sys.stdin)
assert data["test_command"] == "make test"
'
}

check_invalid_repo_path() {
  local invalid_path="$TEMP_DIR/missing-repo"
  local analyze_stderr_file="$TEMP_DIR/analyze-invalid-repo.stderr"
  local verify_stderr_file="$TEMP_DIR/verify-invalid-repo.stderr"

  if bash "$SCRIPT_DIR/analyze-repo.sh" "$invalid_path" >/dev/null 2>"$analyze_stderr_file"; then
    return 1
  fi

  if bash "$SCRIPT_DIR/verify-setup.sh" "$invalid_path" >/dev/null 2>"$verify_stderr_file"; then
    return 1
  fi

  python3 - "$analyze_stderr_file" "$verify_stderr_file" <<'PY'
from pathlib import Path
import sys

for stderr_path in sys.argv[1:]:
    stderr = Path(stderr_path).read_text()
    assert '{"error":"cannot enter repository path"}' in stderr
PY
}

check_analysis_failure_does_not_poison_cache() {
  local repo="$TEMP_DIR/failed-analysis-repo"
  local fake_bin="$TEMP_DIR/fake-bin"
  local first_stderr_file="$TEMP_DIR/failed-analysis.stderr"

  mkdir -p "$repo" "$fake_bin"
  cat > "$fake_bin/python3" <<'PYTHON'
#!/bin/sh
exit 1
PYTHON
  chmod +x "$fake_bin/python3"

  if PATH="$fake_bin:$PATH" bash "$SCRIPT_DIR/verify-setup.sh" "$repo" >/dev/null 2>"$first_stderr_file"; then
    return 1
  fi

  [[ ! -e "$repo/.agent-setup/analyze.json" ]] || return 1
  bash "$SCRIPT_DIR/verify-setup.sh" "$repo" >/dev/null 2>"$TEMP_DIR/retry-analysis.stderr"
}

run_test "eval manifest parses" check_eval_manifest
run_test "analysis detects nested scripts and lockfiles" check_analysis
run_test "analysis uses package runner for npm tests" check_analysis_uses_package_runner_for_tests
run_test "analysis reads UTF-8 package metadata" check_analysis_reads_utf8_package_json
run_test "analysis ignores Makefile variable assignments" check_analysis_ignores_makefile_variable_assignments
run_test "analysis detects space-indented test targets" check_analysis_detects_space_indented_test_target
run_test "analysis reports only existing lockfiles" check_analysis_requires_existing_lockfiles
run_test "analysis detects Git worktree metadata" check_analysis_detects_git_worktree_metadata
run_test "verification preserves review risk and finds root Makefile" check_verification_plan
run_test "verification reports dry-run flags" check_dry_run_flags
run_test "verification respects command boundaries" check_verification_requires_command_boundaries
run_test "verification handles non-UTF-8 Makefiles" check_verification_handles_non_utf8_makefile
run_test "verification reads UTF-8 analysis JSON" check_verification_reads_utf8_analysis_json
run_test "verification rejects shell syntax in safe commands" check_verification_rejects_shell_syntax_in_safe_commands
run_test "verification reanalyzes changed inputs" check_verification_reanalyzes_changed_inputs
run_test "analysis detects multi-target test rules" check_analysis_detects_multi_target_test_rule
run_test "analysis detects multi-target rules in any order" check_analysis_detects_multi_target_rules_in_any_order
run_test "analysis detects test targets with spaced colons" check_analysis_detects_test_target_with_space_before_colon
run_test "analysis reports invalid repository paths" check_invalid_repo_path
run_test "verification retries after analysis failure without stale cache" check_analysis_failure_does_not_poison_cache

if (( failures > 0 )); then
  exit 1
fi

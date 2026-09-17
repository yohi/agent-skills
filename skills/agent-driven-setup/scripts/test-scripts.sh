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
for name in (
    "package.json",
    "package-lock.json",
    "yarn.lock",
    "pnpm-lock.yaml",
    "bun.lockb",
    "pyproject.toml",
    "poetry.lock",
    "Pipfile",
    "Pipfile.lock",
    "Cargo.toml",
    "Cargo.lock",
    "go.mod",
    "go.sum",
    "Gemfile",
    "Gemfile.lock",
    ".env.example",
    ".env.sample",
    "Makefile",
):
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
assert data["complexity_triggers"] == []
'
}

check_analysis_emits_complexity_triggers() {
  local repo="$TEMP_DIR/complex-trigger-repo"
  mkdir -p "$repo"

  # MCP runtime config (mcp.json)
  cat > "$repo/mcp.json" <<'JSON'
{
  "mcpServers": {
    "local": {
      "command": "agent-setup-mcp-stdio-readonly"
    }
  }
}
JSON

  # Multiple config writers: .env.example, config/settings.yaml, and a setup script
  mkdir -p "$repo/config"
  touch "$repo/.env.example"
  cat > "$repo/config/settings.yaml" <<'YAML'
server:
  port: 3000
YAML
  cat > "$repo/config/setup.sh" <<'SH'
#!/bin/bash
set -euo pipefail
# writes both .env.example and config/settings.yaml
SH

  # Webhook URL referenced in docs
  mkdir -p "$repo/docs"
  cat > "$repo/docs/web|hooks.md" <<'MD'
Notifications are delivered to https://hooks.example.invalid/abc123 and
also POSTed to https://webhooks.example.invalid/notify.
MD

  bash "$SCRIPT_DIR/analyze-repo.sh" "$repo" 2>/dev/null |
    python3 -c '
import json
import sys

data = json.load(sys.stdin)
ids = [t["id"] for t in data["complexity_triggers"]]
assert sorted(ids) == sorted(["mcp-runtime", "multiple-config-writers", "webhook-url"]), ids
for t in data["complexity_triggers"]:
    assert set(t) == {"id", "evidence", "note"}, t
    assert all(isinstance(v, str) and v for v in t.values())
    assert "install_docs" in data
    if t["id"] == "webhook-url":
        assert t["evidence"] == "docs/web|hooks.md", t
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

check_analysis_ignores_recipe_lines_with_colons() {
  local repo="$TEMP_DIR/makefile-recipe-repo"
  mkdir -p "$repo"
  printf '%s\n' 'all:' $'\techo test: generated' > "$repo/Makefile"

  bash "$SCRIPT_DIR/analyze-repo.sh" "$repo" 2>/dev/null |
    python3 -c '
import json
import sys

data = json.load(sys.stdin)
assert data["test_command"] is None
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
assert "enhanced_workflow" not in plan
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
  write_analysis_fingerprint "$repo"

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
  write_analysis_fingerprint "$repo"

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
  write_analysis_fingerprint "$repo"

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
  write_analysis_fingerprint "$repo"

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
  bash "$SCRIPT_DIR/verify-setup.sh" "$repo" 2>/dev/null >/dev/null || return 1

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

check_verification_reanalyzes_changed_non_node_inputs() {
  local repo="$TEMP_DIR/changed-non-node-inputs-repo"
  mkdir -p "$repo"
  touch "$repo/pyproject.toml"

  bash "$SCRIPT_DIR/verify-setup.sh" "$repo" 2>/dev/null >/dev/null || return 1
  touch "$repo/poetry.lock"

  bash "$SCRIPT_DIR/verify-setup.sh" "$repo" 2>/dev/null |
    python3 -c '
import json
import sys

plan = json.load(sys.stdin)
commands = {entry["phase"]: entry["command"] for entry in plan["commands"]}
assert commands["install"] == "poetry install"
'
}

check_verification_reanalyzes_changed_env_templates() {
  local template repo with_template without_template

  for template in .env.example .env.sample; do
    repo="$TEMP_DIR/changed-env-template-${template#.env.}-repo"
    with_template="$TEMP_DIR/with-${template#.env.}.json"
    without_template="$TEMP_DIR/without-${template#.env.}.json"
    mkdir -p "$repo"

    bash "$SCRIPT_DIR/verify-setup.sh" "$repo" 2>/dev/null >/dev/null
    touch "$repo/$template"
    bash "$SCRIPT_DIR/verify-setup.sh" "$repo" 2>/dev/null >"$with_template"
    rm "$repo/$template"
    bash "$SCRIPT_DIR/verify-setup.sh" "$repo" 2>/dev/null >"$without_template"

    python3 - "$with_template" "$without_template" <<'PY'
import json
import sys

with_template = json.load(open(sys.argv[1], encoding="utf-8"))
without_template = json.load(open(sys.argv[2], encoding="utf-8"))
note = "Repository has an env template; verify secrets are handled per the secret policy before running any integration test."
assert note in with_template["notes"]
assert note not in without_template["notes"]
PY
  done
}

check_verification_reanalyzes_without_fingerprint() {
  local repo="$TEMP_DIR/missing-fingerprint-repo"
  mkdir -p "$repo/.agent-setup"
  touch "$repo/pyproject.toml"
  cat > "$repo/.agent-setup/analyze.json" <<'JSON'
{
  "install_command": "stale-install"
}
JSON

  bash "$SCRIPT_DIR/verify-setup.sh" "$repo" 2>/dev/null |
    python3 -c '
import json
import sys

plan = json.load(sys.stdin)
assert plan["commands"][0]["command"] == "pip install -e ."
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

check_verification_includes_space_indented_targets() {
  local repo="$TEMP_DIR/space-indented-verification-repo"
  mkdir -p "$repo"
  printf '%s\n' '  test :' > "$repo/Makefile"

  bash "$SCRIPT_DIR/verify-setup.sh" "$repo" 2>/dev/null |
    python3 -c '
import json
import sys

plan = json.load(sys.stdin)
assert plan["makefile_targets"] == ["test"]
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

check_setup_contract_required_runtime_fields() {
  local contract_dir="$TEMP_DIR/contract-red"
  mkdir -p "$contract_dir"

  python3 - "$contract_dir" <<'PY'
import copy
import sys
from pathlib import Path

import yaml

root = Path(sys.argv[1])
contract = {
    "setup_contract_schema_version": 1,
    "setup_intent": "test",
    "setup_target": {
        "mcp_main": {
            "target_type": "mcp",
            "canonical_source": {
                "kind": "repository_path",
                "value": "server",
                "ref_mode": "not_applicable",
            },
            "runtime": {"mode": "in_process"},
        }
    },
    "complexity_triggers": [],
    "configuration_branches": [{"id": "main", "layers": [{"id": "choice", "kind": "choice"}]}],
    "installation": {"mcp_main": []},
    "registration": {"mcp_main": []},
    "discovery": {"mcp_main": []},
    "activation": {"mcp_main": []},
    "verification": {
        "targets": {
            "mcp_main": {
                "target_type": "mcp",
                "items": [{
                    "id": "mcp.initialize",
                    "phase": "initialize",
                    "target_type": "mcp",
                    "required_for_e2e": True,
                    "probe": {"kind": "mcp_request", "request": "initialize"},
                }],
            }
        }
    },
    "handoffs": {},
    "external_effects": {"mutation_surfaces": []},
}

def validate(data):
    target = data["setup_target"]["mcp_main"]
    runtime = target.get("runtime")
    if runtime is None:
        raise ValueError("setup_target.mcp_main.runtime is required")
    if runtime.get("mode") == "process":
        for field in ("command", "safety"):
            if field not in runtime or runtime[field] is None:
                raise ValueError(f"process runtime.{field} is required")

valid = root / "valid.yaml"
valid.write_text(yaml.safe_dump(contract), encoding="utf-8")
missing_runtime = copy.deepcopy(contract)
del missing_runtime["setup_target"]["mcp_main"]["runtime"]
missing_runtime_path = root / "missing-runtime.yaml"
missing_runtime_path.write_text(yaml.safe_dump(missing_runtime), encoding="utf-8")
missing_process_field = copy.deepcopy(contract)
missing_process_field["setup_target"]["mcp_main"]["runtime"] = {"mode": "process", "safety": "read_only"}
missing_process_path = root / "missing-process-command.yaml"
missing_process_path.write_text(yaml.safe_dump(missing_process_field), encoding="utf-8")
missing_process_safety = copy.deepcopy(contract)
missing_process_safety["setup_target"]["mcp_main"]["runtime"] = {"mode": "process", "command": ["server"]}
missing_safety_path = root / "missing-process-safety.yaml"
missing_safety_path.write_text(yaml.safe_dump(missing_process_safety), encoding="utf-8")

validate(yaml.safe_load(valid.read_text(encoding="utf-8")))
for path in (missing_runtime_path, missing_process_path, missing_safety_path):
    try:
        validate(yaml.safe_load(path.read_text(encoding="utf-8")))
    except ValueError:
        continue
    raise AssertionError(f"expected rejection: {path.name}")
PY
}

check_setup_contract_fixture() {
  python3 - "$SKILL_DIR/references/fixtures/example-setup-contract.yaml" <<'PY'
import re
import sys
from pathlib import Path

import yaml

data = yaml.safe_load(Path(sys.argv[1]).read_text(encoding="utf-8"))
required = {
    "setup_contract_schema_version", "setup_intent", "setup_target",
    "complexity_triggers", "configuration_branches", "installation",
    "registration", "discovery", "activation", "verification", "handoffs",
    "external_effects",
}
assert required <= data.keys()
assert data["setup_contract_schema_version"] == 1
targets = data["setup_target"]
assert set(targets) == set(data["verification"]["targets"])
assert data["configuration_branches"]
target_types = {"skill", "mcp", "plugin", "hook", "cli", "service", "other/custom"}
source_kinds = {"repository_path", "url", "registry", "external_resource"}
ref_modes = {"immutable", "mutable", "not_applicable"}
phases = {"installation", "registration", "discovery", "activation", "runtime_start", "initialize", "tool_discovery", "representative_operation"}
layer_kinds = {
    "choice", "installer", "cli", "env", "settings", "generated_config",
    "registration", "discovery", "runtime_consumer", "activation",
    "representative_operation", "verification",
}
safety_values = {"read_only", "mutating", "unknown"}
capability_id = re.compile(r"[a-z][a-z0-9_-]*\Z")

for target_id, target in targets.items():
    assert re.fullmatch(r"[a-z][a-z0-9_-]*", target_id)
    assert target["target_type"] in target_types
    source = target["canonical_source"]
    assert source["kind"] in source_kinds and source["value"]
    assert source["ref_mode"] in ref_modes
    if source["ref_mode"] == "not_applicable":
        assert "ref" not in source or source["ref"] is None
    else:
        assert source.get("ref")
    assert target["runtime"]["mode"] == "process"
    assert target["runtime"]["command"] == ["agent-setup-mcp-stdio-readonly"]
    assert target["runtime"]["safety"] == "read_only"
    assert target["runtime"]["command"] and all(isinstance(arg, str) and arg for arg in target["runtime"]["command"])
    assert target["runtime"]["safety"] in safety_values
    verification_target = data["verification"]["targets"][target_id]
    assert verification_target["target_type"] == target["target_type"]
    items = verification_target["items"]
    item_ids = [item["id"] for item in items]
    assert items
    assert len(item_ids) == len(set(item_ids))
    item_id_set = set(item_ids)
    for item in items:
        assert item["phase"] in phases
        capabilities = item.get("required_capabilities", [])
        assert all(capability_id.fullmatch(cap) for cap in capabilities)
        assert len(capabilities) == len(set(capabilities))
        blocked_by = item.get("blocked_by", [])
        assert set(blocked_by) <= item_id_set
        assert item["id"] not in blocked_by
        probe = item["probe"]
        if probe["kind"] == "command":
            assert probe["argv"] and all(isinstance(arg, str) and arg for arg in probe["argv"])
            assert probe["safety"] in safety_values
        elif probe["kind"] == "agent_action":
            assert probe["action"] in {"discovery", "activation"}
            adapter = probe["adapter"]
            assert adapter["kind"] == "command" and adapter["argv"]
            assert all(isinstance(arg, str) and arg for arg in adapter["argv"])
            assert adapter["stdin"] in {"prompt", "empty"}
            assert adapter["safety"] in safety_values
            if adapter["stdin"] == "prompt":
                assert probe.get("prompt")
            else:
                assert "prompt" not in probe
        else:
            assert probe["kind"] == "mcp_request"
            if probe["request"] == "representative_tool_call":
                assert probe["tool"] and isinstance(probe["arguments"], dict)
                assert probe["safety"] in safety_values
                if probe["safety"] == "read_only":
                    assert "mutation_surface_id" not in probe
                else:
                    assert probe["safety"] in {"mutating", "unknown"}
                    assert probe["mutation_surface_id"]
            else:
                assert probe["request"] in {"initialize", "tool_discovery"}
                assert not any(field in probe for field in ("tool", "arguments", "safety", "mutation_surface_id"))

    def visit(item_id, visiting, visited):
        assert item_id not in visiting
        if item_id in visited:
            return
        visiting.add(item_id)
        for dependency in next(item for item in items if item["id"] == item_id).get("blocked_by", []):
            visit(dependency, visiting, visited)
        visiting.remove(item_id)
        visited.add(item_id)

    visited = set()
    for item_id in item_ids:
        visit(item_id, set(), visited)

for phase_name in ("installation", "registration", "discovery", "activation"):
    for target_id, entries in data[phase_name].items():
        assert target_id in targets
        for entry in entries:
            assert entry["id"] and "reference" in entry
            reference = entry["reference"]
            if reference["kind"] == "path":
                assert reference["path"]
            else:
                assert reference["kind"] == "external_resource" and reference["value"]
            if "verification_item_id" in entry:
                assert entry["verification_item_id"] in {
                    item["id"] for item in data["verification"]["targets"][target_id]["items"]
                }
            if "handoff_id" in entry:
                assert entry["handoff_id"] in data["handoffs"]

for branch in data["configuration_branches"]:
    assert branch["layers"]
    assert len({layer["id"] for layer in branch["layers"]}) == len(branch["layers"])
    for layer in branch["layers"]:
        assert layer["kind"] in layer_kinds

surfaces = {surface["id"]: surface for surface in data["external_effects"]["mutation_surfaces"]}
assert surfaces
for surface in surfaces.values():
    assert surface["scope"] in {"repository", "user_local", "global", "external"}
    assert surface["kind"] in {"path", "glob", "external_resource"} and surface["value"]
    if surface["scope"] == "external":
        assert surface["kind"] == "external_resource"
    if surface["scope"] in {"repository", "user_local"}:
        assert surface["kind"] in {"path", "glob"}
surface = surfaces["temporary-mcp-resource"]
assert surface["scope"] == "external"
assert surface["snapshot"] == "required"
assert surface["cleanup_required"] is True
temporary = next(
    item for item in data["verification"]["targets"]["mcp_main"]["items"]
    if item["id"] == "mcp.temporary-fixture"
)
assert temporary["probe"]["mutation_surface_id"] in surfaces
PY
}

write_audit_contract() {
  local path="$1"
  local variant="${2:-valid}"

  python3 - "$path" "$variant" <<'PY'
import copy
import sys
from pathlib import Path

import yaml

path = Path(sys.argv[1])
variant = sys.argv[2]
contract = {
    "setup_contract_schema_version": 1,
    "setup_intent": "Test deterministic contract auditing",
    "setup_target": {
        "cli_main": {
            "target_type": "cli",
            "canonical_source": {
                "kind": "repository_path",
                "value": "src",
                "ref_mode": "not_applicable",
            },
            "runtime": {
                "mode": "process",
                "command": ["server"],
                "safety": "read_only",
            },
        }
    },
    "complexity_triggers": [],
    "configuration_branches": [
        {"id": "main", "layers": [{"id": "choice", "kind": "choice"}]}
    ],
    "installation": {"cli_main": []},
    "registration": {"cli_main": []},
    "discovery": {"cli_main": []},
    "activation": {"cli_main": []},
    "verification": {
        "targets": {
            "cli_main": {
                "target_type": "cli",
                "items": [
                    {
                        "id": "cli.install",
                        "phase": "installation",
                        "target_type": "cli",
                        "required_for_e2e": True,
                        "blocked_by": [],
                        "probe": {
                            "kind": "command",
                            "argv": ["printf", "ok"],
                            "safety": "read_only",
                        },
                    }
                ],
            }
        }
    },
    "handoffs": {},
    "external_effects": {"mutation_surfaces": []},
}

if variant == "undefined-handoff":
    contract["installation"]["cli_main"] = [
        {
            "id": "install-reference",
            "reference": {"kind": "path", "path": "scripts/install.sh"},
            "handoff_id": "missing-handoff",
        }
    ]
elif variant == "cycle":
    items = contract["verification"]["targets"]["cli_main"]["items"]
    items[0]["blocked_by"] = ["cli.second"]
    items.append(
        {
            "id": "cli.second",
            "phase": "activation",
            "target_type": "cli",
            "required_for_e2e": True,
            "blocked_by": ["cli.install"],
            "probe": {
                "kind": "command",
                "argv": ["printf", "second"],
                "safety": "read_only",
            },
        }
    )
elif variant == "invalid-safety":
    contract["setup_target"]["cli_main"]["runtime"]["safety"] = "unsafe"
    item = contract["verification"]["targets"]["cli_main"]["items"][0]
    item["probe"]["safety"] = "unsafe"
    contract["verification"]["targets"]["cli_main"]["items"].append(
        {
            "id": "cli.adapter",
            "phase": "discovery",
            "target_type": "cli",
            "required_for_e2e": True,
            "probe": {
                "kind": "agent_action",
                "action": "discovery",
                "adapter": {
                    "kind": "command",
                    "argv": ["printf", "adapter"],
                    "stdin": "empty",
                    "safety": "unsafe",
                },
            },
        }
    )
elif variant == "invalid-capabilities":
    contract["verification"]["targets"]["cli_main"]["items"][0][
        "required_capabilities"
    ] = ["valid_capability", "valid_capability", "Invalid"]
elif variant == "empty-runtime-command":
    contract["setup_target"]["cli_main"]["runtime"]["command"] = []
elif variant == "empty-probe-argv":
    contract["verification"]["targets"]["cli_main"]["items"][0]["probe"]["argv"] = []
elif variant == "empty-adapter-argv":
    contract["verification"]["targets"]["cli_main"]["items"][0]["probe"] = {
        "kind": "agent_action",
        "action": "discovery",
        "adapter": {
            "kind": "command",
            "argv": [],
            "stdin": "empty",
            "safety": "read_only",
        },
    }
elif variant == "repository-source-parent-escape":
    contract["setup_target"]["cli_main"]["canonical_source"]["value"] = "../outside"
elif variant == "repository-source-absolute":
    contract["setup_target"]["cli_main"]["canonical_source"]["value"] = "/etc/passwd"
elif variant == "repository-source-symlink":
    contract["setup_target"]["cli_main"]["canonical_source"]["value"] = "linked-source"
elif variant == "unknown-layer-kind":
    contract["configuration_branches"][0]["layers"][0]["kind"] = "future_layer"
elif variant == "command-safety":
    target = contract["setup_target"]["cli_main"]
    target["runtime"] = {
        "mode": "process",
        "command": ["node", "--version"],
        "safety": "read_only",
    }
    verification_target = contract["verification"]["targets"]["cli_main"]
    command_specs = [
        ("command.node", ["node", "--version"], "read_only"),
        ("command.git", ["git", "status", "--porcelain"], "read_only"),
        ("command.npm", ["npm", "install"], "mutating"),
        ("command.unknown", ["unknown-command", "--check"], "read_only"),
        ("command.mismatch", ["node", "--version"], "mutating"),
        ("command.absolute", ["/usr/bin/node", "--version"], "read_only"),
        ("command.wrapper", ["env", "node", "--version"], "read_only"),
        ("command.trailing", ["node", "--version", "--verbose"], "read_only"),
    ]
    verification_target["items"] = [
        {
            "id": item_id,
            "phase": "discovery",
            "target_type": "cli",
            "required_for_e2e": True,
            "blocked_by": [],
            "probe": {"kind": "command", "argv": argv, "safety": safety},
        }
        for item_id, argv, safety in command_specs
    ]
elif variant == "readonly-node":
    target = contract["setup_target"]["cli_main"]
    target["runtime"] = {
        "mode": "process",
        "command": ["node", "--version"],
        "safety": "read_only",
    }
    contract["verification"]["targets"]["cli_main"]["items"][0]["probe"] = {
        "kind": "command",
        "argv": ["node", "--version"],
        "safety": "read_only",
    }
elif variant in {"mcp-initialize", "mcp-tool-discovery", "mcp-representative-readonly"}:
    target = contract["setup_target"]["cli_main"]
    target["target_type"] = "mcp"
    target["runtime"] = {
        "mode": "process",
        "command": ["agent-setup-mcp-stdio-readonly"],
        "safety": "read_only",
    }
    verification_target = contract["verification"]["targets"]["cli_main"]
    verification_target["target_type"] = "mcp"
    if variant == "mcp-initialize":
        verification_target["items"][0] = {
            "id": "mcp.initialize",
            "phase": "initialize",
            "target_type": "mcp",
            "required_for_e2e": True,
            "probe": {"kind": "mcp_request", "request": "initialize"},
        }
    elif variant == "mcp-tool-discovery":
        verification_target["items"][0] = {
            "id": "mcp.tool-discovery",
            "phase": "tool_discovery",
            "target_type": "mcp",
            "required_for_e2e": True,
            "probe": {"kind": "mcp_request", "request": "tool_discovery"},
        }
    else:
        verification_target["items"][0] = {
            "id": "mcp.representative-readonly",
            "phase": "representative_operation",
            "target_type": "mcp",
            "required_for_e2e": True,
            "probe": {
                "kind": "mcp_request",
                "request": "representative_tool_call",
                "tool": "read_fixture",
                "arguments": {"name": "test"},
                "safety": "read_only",
            },
        }
elif variant == "temporary-fixture":
    target = contract["setup_target"]["cli_main"]
    target["target_type"] = "mcp"
    target["runtime"] = {
        "mode": "process",
        "command": ["agent-setup-mcp-stdio-readonly"],
        "safety": "read_only",
    }
    verification_target = contract["verification"]["targets"]["cli_main"]
    verification_target["target_type"] = "mcp"
    verification_target["items"][0] = {
        "id": "mcp.temporary",
        "phase": "representative_operation",
        "target_type": "mcp",
        "required_for_e2e": True,
        "probe": {
            "kind": "mcp_request",
            "request": "representative_tool_call",
            "tool": "create_fixture",
            "arguments": {"name": "test"},
            "safety": "mutating",
            "mutation_surface_id": "temporary-resource",
        },
    }
    contract["external_effects"]["mutation_surfaces"] = [{
        "id": "temporary-resource",
        "scope": "external",
        "kind": "external_resource",
        "value": "test-fixture",
        "snapshot": "required",
        "cleanup_required": True,
    }]
elif variant != "valid":
    raise ValueError(f"unknown fixture variant: {variant}")

path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(
    "---\n" + yaml.safe_dump(contract, sort_keys=False) + "---\n# body\n",
    encoding="utf-8",
)
PY
}

write_dry_run_contract() {
  local path="$1"

  python3 - "$path" <<'PY'
import sys
from pathlib import Path

import yaml

path = Path(sys.argv[1])
targets = {
    "cli_main": {
        "target_type": "cli",
        "canonical_source": {
            "kind": "repository_path",
            "value": "src",
            "ref_mode": "not_applicable",
        },
        "runtime": {
            "mode": "process",
            "command": ["node", "--version"],
            "safety": "read_only",
        },
    },
    "skill_main": {
        "target_type": "skill",
        "canonical_source": {
            "kind": "repository_path",
            "value": "src",
            "ref_mode": "not_applicable",
        },
        "runtime": {"mode": "agent_discovery"},
    },
    "mcp_main": {
        "target_type": "mcp",
        "canonical_source": {
            "kind": "repository_path",
            "value": "src",
            "ref_mode": "not_applicable",
        },
        "runtime": {
            "mode": "process",
            "command": ["agent-setup-mcp-stdio-readonly"],
            "safety": "read_only",
        },
    },
}

def command_item(item_id, argv, safety):
    return {
        "id": item_id,
        "phase": "discovery",
        "target_type": "cli",
        "required_for_e2e": True,
        "blocked_by": [],
        "probe": {"kind": "command", "argv": argv, "safety": safety},
    }

items = {
    "cli_main": [
        command_item("cli.node", ["node", "--version"], "read_only"),
        command_item("cli.git", ["git", "status", "--porcelain"], "read_only"),
        command_item("cli.install", ["npm", "install"], "mutating"),
        command_item("cli.unknown", ["unknown-command", "--check"], "read_only"),
        command_item("cli.mismatch", ["node", "--version"], "mutating"),
    ],
    "skill_main": [
        {
            "id": "skill.adapter",
            "phase": "discovery",
            "target_type": "skill",
            "required_for_e2e": True,
            "blocked_by": [],
            "probe": {
                "kind": "agent_action",
                "action": "discovery",
                "adapter": {
                    "kind": "command",
                    "argv": ["node", "--version"],
                    "stdin": "empty",
                    "safety": "read_only",
                },
            },
        }
    ],
    "mcp_main": [
        {
            "id": "mcp.initialize",
            "phase": "initialize",
            "target_type": "mcp",
            "required_for_e2e": True,
            "blocked_by": [],
            "probe": {"kind": "mcp_request", "request": "initialize"},
        },
        {
            "id": "mcp.temporary",
            "phase": "representative_operation",
            "target_type": "mcp",
            "required_for_e2e": True,
            "blocked_by": [],
            "probe": {
                "kind": "mcp_request",
                "request": "representative_tool_call",
                "tool": "create_fixture",
                "arguments": {"name": "dry-run"},
                "safety": "mutating",
                "mutation_surface_id": "temporary-resource",
            },
        },
    ],
}

contract = {
    "setup_contract_schema_version": 1,
    "setup_intent": "Exercise dry-run safety decisions",
    "setup_target": targets,
    "complexity_triggers": [],
    "configuration_branches": [
        {"id": "main", "layers": [{"id": "choice", "kind": "choice"}]}
    ],
    "installation": {target_id: [] for target_id in targets},
    "registration": {target_id: [] for target_id in targets},
    "discovery": {target_id: [] for target_id in targets},
    "activation": {target_id: [] for target_id in targets},
    "verification": {
        "targets": {
            target_id: {"target_type": targets[target_id]["target_type"], "items": target_items}
            for target_id, target_items in items.items()
        }
    },
    "handoffs": {},
    "external_effects": {
        "mutation_surfaces": [
            {
                "id": "temporary-resource",
                "scope": "external",
                "kind": "external_resource",
                "value": "dry-run-fixture",
                "snapshot": "required",
                "cleanup_required": True,
            }
        ]
    },
}

path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(
    "---\n" + yaml.safe_dump(contract, sort_keys=False) + "---\n# body\n",
    encoding="utf-8",
)
PY
}

capture_audit() {
  local report="$1"
  shift
  local status

  if bash "$SCRIPT_DIR/audit-contract.sh" "$@" >"$report" 2>"$report.stderr"; then
    status=0
  else
    status=$?
  fi
  printf '%s\n' "$status" >"$report.status"
}

check_audit_report_shape() {
  local report="$1"

  python3 - "$report" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
assert list(data) == [
    "contract_discovery",
    "observed_topology",
    "discrepancies",
    "schema_errors",
    "next_actions",
]
assert isinstance(data["discrepancies"], list)
assert "discrepancy" not in data
PY
}

check_audit_explicit_contract_has_priority() {
  local repo="$TEMP_DIR/audit-explicit-repo"
  local report="$TEMP_DIR/audit-explicit.json"
  mkdir -p "$repo"

  write_audit_contract "$repo/explicit.md"
  write_audit_contract "$repo/docs/agents.md"
  write_audit_contract "$repo/docs/readme.md"
  printf '%s\n' '<!-- agent-setup-contract: docs/agents.md -->' >"$repo/AGENTS.md"
  printf '%s\n' '<!-- agent-setup-contract: docs/readme.md -->' >"$repo/README.md"

  capture_audit "$report" --contract explicit.md "$repo"
  python3 - "$report" "$report.status" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
assert int(open(sys.argv[2]).read()) == 0
assert data["contract_discovery"] == {
    "status": "found",
    "path": "explicit.md",
    "source": "explicit",
}
assert data["schema_errors"] == []
PY
  check_audit_report_shape "$report"
}

check_audit_conflicting_repository_markers_are_ambiguous() {
  local repo="$TEMP_DIR/audit-conflict-repo"
  local report="$TEMP_DIR/audit-conflict.json"
  mkdir -p "$repo"

  write_audit_contract "$repo/docs/agents.md"
  write_audit_contract "$repo/docs/readme.md"
  printf '%s\n' '<!-- agent-setup-contract: docs/agents.md -->' >"$repo/AGENTS.md"
  printf '%s\n' '<!-- agent-setup-contract: docs/readme.md -->' >"$repo/README.md"

  capture_audit "$report" "$repo"
  python3 - "$report" "$report.status" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
assert int(open(sys.argv[2]).read()) == 0
assert data["contract_discovery"] == {
    "status": "ambiguous",
    "source": "repository_declared",
}
assert data["schema_errors"] == []
PY
}

check_audit_marker_scan_candidates_are_ambiguous() {
  local repo="$TEMP_DIR/audit-candidates-repo"
  local report="$TEMP_DIR/audit-candidates.json"
  mkdir -p "$repo"

  write_audit_contract "$repo/SETUP-CONTRACT.md"
  write_audit_contract "$repo/docs/one.md"

  capture_audit "$report" "$repo"
  python3 - "$report" "$report.status" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
assert int(open(sys.argv[2]).read()) == 0
assert data["contract_discovery"] == {
    "status": "ambiguous",
    "source": "marker_scan",
}
assert data["schema_errors"] == []
PY
}

check_audit_not_found_is_deterministic() {
  local repo="$TEMP_DIR/audit-not-found-repo"
  local report="$TEMP_DIR/audit-not-found.json"
  mkdir -p "$repo"

  capture_audit "$report" "$repo"
  python3 - "$report" "$report.status" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
assert int(open(sys.argv[2]).read()) == 0
assert data["contract_discovery"] == {"status": "not_found", "source": "none"}
assert data["schema_errors"] == []
PY
  check_audit_report_shape "$report"
}

check_audit_skips_unreadable_marker_scan_candidates() {
  local repo="$TEMP_DIR/audit-unreadable-candidate-repo"
  local report="$TEMP_DIR/audit-unreadable-candidate.json"
  mkdir -p "$repo"
  printf '\377\n' >"$repo/SETUP-CONTRACT.md"

  capture_audit "$report" "$repo"
  python3 - "$report" "$report.status" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
assert int(open(sys.argv[2]).read()) == 0
assert data["contract_discovery"] == {"status": "not_found", "source": "none"}
assert data["schema_errors"] == []
PY
  check_audit_report_shape "$report"
}

check_audit_ignores_unreadable_marker_documents() {
  local repo="$TEMP_DIR/audit-unreadable-marker-repo"
  local report="$TEMP_DIR/audit-unreadable-marker.json"
  mkdir -p "$repo"
  printf '\377\n' >"$repo/README.md"

  capture_audit "$report" "$repo"
  python3 - "$report" "$report.status" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
assert int(open(sys.argv[2]).read()) == 0
assert data["contract_discovery"] == {"status": "not_found", "source": "none"}
assert data["schema_errors"] == []
PY
  check_audit_report_shape "$report"
}

check_audit_reports_unreadable_selected_contract() {
  local repo="$TEMP_DIR/audit-unreadable-selected-repo"
  local report="$TEMP_DIR/audit-unreadable-selected.json"
  mkdir -p "$repo"
  printf '%s\n' '---' >"$repo/contract.md"
  printf '\377\n' >>"$repo/contract.md"

  capture_audit "$report" --contract contract.md "$repo"
  python3 - "$report" "$report.status" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
assert int(open(sys.argv[2]).read()) == 2
assert data["contract_discovery"] == {
    "status": "contract_error",
    "source": "explicit",
}
assert data["schema_errors"]
PY
  check_audit_report_shape "$report"
}

check_audit_rejects_escaping_declared_path() {
  local repo="$TEMP_DIR/audit-escaping-repo"
  local report="$TEMP_DIR/audit-escaping.json"
  mkdir -p "$repo"
  write_audit_contract "$repo/SETUP-CONTRACT.md"
  printf '%s\n' '<!-- agent-setup-contract: ../contract.md -->' >"$repo/AGENTS.md"

  capture_audit "$report" "$repo"
  python3 - "$report" "$report.status" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
assert int(open(sys.argv[2]).read()) == 2
assert data["contract_discovery"] == {
    "status": "contract_error",
    "source": "repository_declared",
}
assert data["schema_errors"]
assert any(".." in error["message"] for error in data["schema_errors"])
PY
}

check_audit_rejects_malformed_explicit_frontmatter() {
  local repo="$TEMP_DIR/audit-frontmatter-repo"
  local report="$TEMP_DIR/audit-frontmatter.json"
  mkdir -p "$repo"
  printf '%s\n' '# no frontmatter' >"$repo/contract.md"

  capture_audit "$report" --contract contract.md "$repo"
  python3 - "$report" "$report.status" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
assert int(open(sys.argv[2]).read()) == 2
assert data["contract_discovery"] == {
    "status": "contract_error",
    "source": "explicit",
}
assert data["schema_errors"]
PY
}

check_audit_rejects_undefined_handoff() {
  local repo="$TEMP_DIR/audit-handoff-repo"
  local report="$TEMP_DIR/audit-handoff.json"
  mkdir -p "$repo"
  write_audit_contract "$repo/contract.md" undefined-handoff

  capture_audit "$report" --contract contract.md "$repo"
  python3 - "$report" "$report.status" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
assert int(open(sys.argv[2]).read()) == 2
assert data["contract_discovery"]["status"] == "found"
assert any(
    error["code"] == "unresolved_handoff_id"
    for error in data["schema_errors"]
)
PY
}

check_audit_rejects_blocked_by_cycle() {
  local repo="$TEMP_DIR/audit-cycle-repo"
  local report="$TEMP_DIR/audit-cycle.json"
  mkdir -p "$repo"
  write_audit_contract "$repo/contract.md" cycle

  capture_audit "$report" --contract contract.md "$repo"
  python3 - "$report" "$report.status" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
assert int(open(sys.argv[2]).read()) == 2
assert any(error["code"] == "blocked_by_cycle" for error in data["schema_errors"])
PY
}

check_audit_rejects_empty_argv_lists() {
  local repo="$TEMP_DIR/audit-empty-argv-repo"
  local report
  local expected
  mkdir -p "$repo"

  for variant in empty-runtime-command empty-probe-argv empty-adapter-argv; do
    report="$repo/$variant.json"
    write_audit_contract "$repo/$variant.md" "$variant"
    capture_audit "$report" --contract "$variant.md" "$repo"
    case "$variant" in
      empty-runtime-command) expected="invalid_runtime" ;;
      empty-probe-argv|empty-adapter-argv) expected="invalid_probe" ;;
    esac
    python3 - "$report" "$report.status" "$expected" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
assert int(open(sys.argv[2]).read()) == 2
assert any(error["code"] == sys.argv[3] for error in data["schema_errors"])
PY
  done
}

check_audit_rejects_invalid_repository_source_paths() {
  local repo="$TEMP_DIR/audit-invalid-source-repo"
  local outside="$TEMP_DIR/audit-source-outside"
  local report
  mkdir -p "$repo" "$outside"
  ln -s "$outside" "$repo/linked-source"

  for variant in repository-source-parent-escape repository-source-absolute repository-source-symlink; do
    report="$repo/$variant.json"
    write_audit_contract "$repo/$variant.md" "$variant"
    capture_audit "$report" --contract "$variant.md" "$repo"
    python3 - "$report" "$report.status" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
assert int(open(sys.argv[2]).read()) == 2
assert any(error["code"] == "invalid_canonical_source" for error in data["schema_errors"])
PY
  done
}

check_audit_validates_all_safety_enums_without_execution() {
  local repo="$TEMP_DIR/audit-safety-repo"
  local report="$TEMP_DIR/audit-safety.json"
  mkdir -p "$repo"
  write_audit_contract "$repo/contract.md" invalid-safety

  capture_audit "$report" --contract contract.md "$repo"
  python3 - "$report" "$report.status" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
assert int(open(sys.argv[2]).read()) == 2
errors = data["schema_errors"]
assert sum(error["code"] == "invalid_safety" for error in errors) >= 3
assert all("argv" not in error["message"] for error in errors if error["code"] == "invalid_safety")
PY
}

check_audit_validates_capability_ids_without_matrix_lookup() {
  local repo="$TEMP_DIR/audit-capability-repo"
  local report="$TEMP_DIR/audit-capability.json"
  mkdir -p "$repo"
  write_audit_contract "$repo/contract.md" invalid-capabilities

  capture_audit "$report" --contract contract.md "$repo"
  python3 - "$report" "$report.status" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
assert int(open(sys.argv[2]).read()) == 2
errors = data["schema_errors"]
assert any(error["code"] == "invalid_capability_id" for error in errors)
assert any(error["code"] == "duplicate_required_capability" for error in errors)
PY
}

check_audit_rejects_unknown_layer_kind() {
  local repo="$TEMP_DIR/audit-layer-kind-repo"
  local report="$TEMP_DIR/audit-layer-kind.json"
  mkdir -p "$repo"
  write_audit_contract "$repo/contract.md" unknown-layer-kind

  capture_audit "$report" --contract contract.md "$repo"
  python3 - "$report" "$report.status" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
assert int(open(sys.argv[2]).read()) == 2
assert any(error["code"] == "invalid_layer_kind" for error in data["schema_errors"])
PY
}

check_audit_writes_both_formats_only_outside_target() {
  local repo="$TEMP_DIR/audit-both-repo"
  local output_dir="$TEMP_DIR/audit-output"
  local report="$TEMP_DIR/audit-both.stdout"
  mkdir -p "$repo" "$output_dir"
  write_audit_contract "$repo/contract.md"

  capture_audit "$report" --format both --output-dir "$output_dir" --contract contract.md "$repo"
  python3 - "$report.status" "$output_dir/audit-report.json" "$output_dir/audit-report.md" <<'PY'
import json
import sys
from pathlib import Path

assert int(Path(sys.argv[1]).read_text()) == 0
json_report = Path(sys.argv[2])
markdown_report = Path(sys.argv[3])
assert json_report.is_file()
assert markdown_report.is_file()
data = json.loads(json_report.read_text(encoding="utf-8"))
assert data["contract_discovery"]["status"] == "found"
assert "contract_discovery" in markdown_report.read_text(encoding="utf-8")
PY
}

check_audit_rejects_target_internal_output_dir() {
  local repo="$TEMP_DIR/audit-internal-output-repo"
  local report="$TEMP_DIR/audit-internal-output.stdout"
  mkdir -p "$repo"
  write_audit_contract "$repo/contract.md"

  capture_audit "$report" --format both --output-dir "$repo/reports" --contract contract.md "$repo"
  python3 - "$report.status" "$repo/reports" <<'PY'
import sys
from pathlib import Path

assert int(Path(sys.argv[1]).read_text()) == 2
assert not Path(sys.argv[2]).exists()
PY
}

check_audit_reports_dependency_unavailable_without_installing() {
  local repo="$TEMP_DIR/audit-dependency-repo"
  local fake_bin="$TEMP_DIR/audit-fake-bin"
  local report="$TEMP_DIR/audit-dependency.json"
  local pip_called="$TEMP_DIR/audit-pip-called"
  mkdir -p "$repo" "$fake_bin"
  write_audit_contract "$repo/contract.md"

  cat >"$fake_bin/python3" <<'PYTHON'
#!/bin/sh
if [ "${1:-}" = "-m" ] && [ "${2:-}" = "pip" ]; then
  touch "${AUDIT_PIP_CALLED:?}"
fi
exit 1
PYTHON
  chmod +x "$fake_bin/python3"
  AUDIT_PIP_CALLED="$pip_called" PATH="$fake_bin:$PATH" \
    capture_audit "$report" --contract contract.md "$repo"

  python3 - "$report.status" "$report.stderr" "$pip_called" <<'PY'
import sys
from pathlib import Path

assert int(Path(sys.argv[1]).read_text()) == 3
stderr = Path(sys.argv[2]).read_text(encoding="utf-8")
assert "dependency_unavailable" in stderr
assert not Path(sys.argv[3]).exists()
PY
}

write_topology_fixture() {
  local repo="$1"

  mkdir -p "$repo/src/config" "$repo/other"

  cat >"$repo/src/config/generated.yaml" <<'YAML'
database:
  host: localhost
YAML
  cat >"$repo/src/client.py" <<'PY'
import importlib


def bootstrap(module_name):
    return importlib.import_module(module_name)
PY
  printf '%s\n' 'usage: app [--verbose]' >"$repo/src/config/cli.txt"
  printf '%s\n' 'valid target documentation' >"$repo/other/valid.md"

  python3 - "$repo/contract.md" <<'PY'
import sys
from pathlib import Path

import yaml

contract = {
    "setup_contract_schema_version": 1,
    "setup_intent": "Test static topology scanning",
    "setup_target": {
        "cli_main": {
            "target_type": "cli",
            "canonical_source": {
                "kind": "repository_path",
                "value": "src",
                "ref_mode": "not_applicable",
            },
            "runtime": {
                "mode": "process",
                "command": ["server"],
                "safety": "read_only",
            },
        },
        "other_valid": {
            "target_type": "service",
            "canonical_source": {
                "kind": "repository_path",
                "value": "other",
                "ref_mode": "not_applicable",
            },
            "runtime": {"mode": "in_process"},
        },
    },
    "complexity_triggers": [],
    "configuration_branches": [
        {
            "id": "main",
            "layers": [
                {
                    "id": "generated-config",
                    "kind": "generated_config",
                    "path": "src/config/generated.yaml",
                    "key": "server.port",
                },
                {
                    "id": "runtime-consumer",
                    "kind": "runtime_consumer",
                    "path": "src/client.py",
                    "symbol": "connect_mcp",
                },
                {
                    "id": "server-cli",
                    "kind": "cli",
                    "path": "src/config/generated.yaml",
                    "option": "--missing-flag",
                },
                {
                    "id": "other-layer",
                    "kind": "settings",
                    "path": "other/valid.md",
                    "key": "valid",
                },
            ],
        }
    ],
    "installation": {
        "cli_main": [
            {"id": "install-main", "reference": {"kind": "path", "path": "src/client.py"}}
        ],
        "other_valid": [
            {"id": "install-other", "reference": {"kind": "path", "path": "other/valid.md"}}
        ],
    },
    "registration": {"cli_main": [], "other_valid": []},
    "discovery": {"cli_main": [], "other_valid": []},
    "activation": {"cli_main": [], "other_valid": []},
    "verification": {
        "targets": {
            "cli_main": {
                "target_type": "cli",
                "items": [
                    {
                        "id": "cli.install",
                        "phase": "installation",
                        "target_type": "cli",
                        "required_for_e2e": True,
                        "blocked_by": [],
                        "probe": {
                            "kind": "command",
                            "argv": ["printf", "ok"],
                            "safety": "read_only",
                        },
                    }
                ],
            },
            "other_valid": {
                "target_type": "service",
                "items": [
                    {
                        "id": "other.install",
                        "phase": "installation",
                        "target_type": "service",
                        "required_for_e2e": True,
                        "blocked_by": [],
                        "probe": {
                            "kind": "command",
                            "argv": ["printf", "ok"],
                            "safety": "read_only",
                        },
                    }
                ],
            },
        }
    },
    "handoffs": {},
    "external_effects": {"mutation_surfaces": []},
}

path = Path(sys.argv[1])
path.write_text(
    "---\n" + yaml.safe_dump(contract, sort_keys=False) + "---\n# body\n",
    encoding="utf-8",
)
PY
}

repo_file_fingerprint() {
  (cd "$1" && find . -type f -print0 | sort -z | xargs -0 sha256sum) | sha256sum
}

check_audit_reports_static_topology() {
  local repo="$TEMP_DIR/audit-topology-repo"
  local output_dir="$TEMP_DIR/audit-topology-output"
  local report="$TEMP_DIR/audit-topology.stdout"
  local fingerprint_before="$TEMP_DIR/audit-topology.before"
  local fingerprint_after="$TEMP_DIR/audit-topology.after"
  mkdir -p "$repo" "$output_dir"
  write_topology_fixture "$repo"
  repo_file_fingerprint "$repo" >"$fingerprint_before"

  capture_audit "$report" --format both --output-dir "$output_dir" --contract contract.md "$repo"
  local both_status=0
  python3 - "$report" "$report.status" "$output_dir/audit-report.json" "$output_dir/audit-report.md" <<'PY' || both_status=1
import json
import sys
from pathlib import Path

assert int(Path(sys.argv[2]).read_text()) == 0
stdout = Path(sys.argv[1]).read_text(encoding="utf-8")
data = json.loads(stdout)  # --format both keeps JSON on stdout
assert list(data) == [
    "contract_discovery",
    "observed_topology",
    "discrepancies",
    "schema_errors",
    "next_actions",
]
assert data["schema_errors"] == []
assert data["contract_discovery"]["status"] == "found"

topology = data["observed_topology"]
assert isinstance(topology, dict)
assert topology["scanned_layer_count"] == 4
assert topology["scanned_phase_reference_count"] == 2
consumers = [
    entry
    for entry in topology["layer_observations"]
    if entry["layer_id"] == "runtime-consumer"
]
assert len(consumers) == 1
assert consumers[0]["path_exists"] is True
assert consumers[0]["symbol_present"] is False
assert consumers[0]["dynamic_wiring"] is True

findings = data["discrepancies"]
confirmed = [f for f in findings if f["finding_state"] == "confirmed"]
candidates = [f for f in findings if f["finding_state"] == "candidate"]
unresolved = [f for f in findings if f["finding_state"] == "unresolved"]
assert len(findings) == 3
assert len(confirmed) == 1 and len(candidates) == 1 and len(unresolved) == 1
assert confirmed[0]["code"] == "absent_generated_config_key"
assert confirmed[0]["affected_target_ids"] == ["cli_main"]
assert unresolved[0]["code"] == "indirect_runtime_consumer"
assert candidates[0]["code"] == "unmatched_cli_option"
assert all(f["affected_target_ids"] for f in findings)
assert all(
    set(f) == {"finding_state", "code", "message", "affected_target_ids", "locator"}
    for f in findings
)
assert all("other_valid" not in f["affected_target_ids"] for f in findings)
assert len(data["next_actions"]) == len(findings)
assert data["next_actions"]

json_report = Path(sys.argv[3])
markdown_report = Path(sys.argv[4])
assert json_report.is_file() and markdown_report.is_file()
assert json.loads(json_report.read_text(encoding="utf-8")) == data
markdown = markdown_report.read_text(encoding="utf-8")
assert "## Observed Topology" in markdown
for state in ("confirmed", "candidate", "unresolved"):
    assert markdown.count(f"- [{state}] ") == sum(
        1 for f in findings if f["finding_state"] == state
    )
assert "## Next Actions" in markdown
PY
  local markdown_status=0
  python3 - "$output_dir/audit-report.md" <<'PY' || markdown_status=1
import sys
from pathlib import Path

markdown = Path(sys.argv[1]).read_text(encoding="utf-8")
assert "## Observed Topology" in markdown
assert "- [confirmed] " in markdown
assert "- [candidate] " in markdown
assert "- [unresolved] " in markdown
assert "## Next Actions" in markdown
PY

  repo_file_fingerprint "$repo" >"$fingerprint_after"
  [[ $both_status -eq 0 && $markdown_status -eq 0 ]] &&
    diff -q "$fingerprint_before" "$fingerprint_after" >/dev/null
}

check_audit_unmatched_layer_path_is_unassigned() {
  local repo="$TEMP_DIR/audit-unmatched-path-repo"
  local report="$TEMP_DIR/audit-unmatched-path.stdout"
  mkdir -p "$repo"
  write_topology_fixture "$repo"

  python3 - "$repo/contract.md" <<'PY'
import sys
from pathlib import Path

import yaml

path = Path(sys.argv[1])
contract = yaml.safe_load(path.read_text(encoding="utf-8").split("\n---", 1)[0][4:])
contract["configuration_branches"][0]["layers"].append(
    {
        "id": "unmatched-layer",
        "kind": "settings",
        "path": "unrelated/missing.ini",
    }
)
path.write_text(
    "---\n" + yaml.safe_dump(contract, sort_keys=False) + "---\n# body\n",
    encoding="utf-8",
)
PY

  capture_audit "$report" --contract contract.md "$repo"
  python3 - "$report" "$report.status" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
assert int(Path(sys.argv[2]).read_text()) == 0
findings = [
    finding
    for finding in data["discrepancies"]
    if finding["locator"].get("layer_id") == "unmatched-layer"
]
assert len(findings) == 1
assert findings[0]["code"] == "missing_declared_path"
assert findings[0]["affected_target_ids"] == ["unassigned"]
PY
}


check_documentation_contract_marker_syntax() {
  grep -q '<!-- agent-setup-contract:' "$SKILL_DIR/references/setup-contract-schema.md" || return 1
  grep -q 'Paths are normalized repository-relative paths' "$SKILL_DIR/references/setup-contract-schema.md" || return 1
}

check_documentation_audit_grammar() {
  grep -q 'audit-contract.sh' "$SKILL_DIR/SKILL.md" || return 1
  grep -q 'contract_discovery' "$SKILL_DIR/SKILL.md" || return 1
  grep -q 'schema_errors' "$SKILL_DIR/SKILL.md" || return 1
}

check_documentation_mutation_surface_investigation() {
  grep -q 'mutation_surfaces' "$SKILL_DIR/references/setup-contract-schema.md" || return 1
  grep -q 'external_effects' "$SKILL_DIR/SKILL.md" || return 1
}

check_documentation_process_runtime_safety_shape() {
  local schema="${1:-$SKILL_DIR/references/setup-contract-schema.md}"
  local runtime_safety_line
  local runtime_safety_marker="\`runtime.safety\`"

  grep -qF 'runtime.safety' "$schema" || return 1
  grep -qF 'process only' "$schema" || return 1
  runtime_safety_line="$(grep -F "$runtime_safety_marker" "$schema" | grep -F 'process only' | head -n1)" || return 1
  for value in read_only mutating unknown; do
    local literal="\`$value\`"
    [[ "$runtime_safety_line" == *"$literal"* ]] || return 1
  done
}

check_documentation_process_runtime_safety_shape_rejects_unrelated_enum() {
  local schema="$TEMP_DIR/invalid-runtime-safety-schema.md"
  cp "$SKILL_DIR/references/setup-contract-schema.md" "$schema"
  python3 - "$schema" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
lines = text.splitlines()
for index, line in enumerate(lines):
    if "`runtime.safety`" in line and "process only" in line:
        lines[index] = "| `runtime.safety` | process only | `unsafe`; forbidden otherwise |"
        break
else:
    raise AssertionError("runtime.safety schema line not found")
path.write_text("\n".join(lines) + "\n", encoding="utf-8")
PY

  if check_documentation_process_runtime_safety_shape "$schema"; then
    return 1
  fi
}

check_target_probe_classifier() {
  local classify="$SCRIPT_DIR/run-target-probes.sh"
  local result

  result="$(printf '%s\n' '{"argv":["node","--version"],"declared_safety":"read_only"}' | bash "$classify" --classify-only)"
  python3 - "$result" <<'PY'
import json
import sys

assert json.loads(sys.argv[1]) == {
    "effective_safety": "read_only",
    "declaration_matches": True,
}
PY

  result="$(printf '%s\n' '{"argv":["agent-setup-mcp-stdio-readonly"],"declared_safety":"read_only"}' | bash "$classify" --classify-only)"
  python3 - "$result" <<'PY'
import json
import sys

assert json.loads(sys.argv[1]) == {
    "effective_safety": "read_only",
    "declaration_matches": True,
}
PY

  result="$(printf '%s\n' '{"argv":["npm","install"],"declared_safety":"mutating"}' | bash "$classify" --classify-only)"
  python3 - "$result" <<'PY'
import json
import sys

assert json.loads(sys.argv[1]) == {
    "effective_safety": "mutating",
    "declaration_matches": True,
}
PY

  result="$(printf '%s\n' '{"argv":["unknown-command","--check"],"declared_safety":"read_only"}' | bash "$classify" --classify-only)"
  python3 - "$result" <<'PY'
import json
import sys

assert json.loads(sys.argv[1]) == {
    "effective_safety": "unknown",
    "declaration_matches": False,
}
PY
}

check_target_probe_classifier_requires_exact_argv() {
  local classify="$SCRIPT_DIR/run-target-probes.sh"
  local result

  for input in \
    '{"argv":["/usr/bin/node","--version"],"declared_safety":"read_only"}' \
    '{"argv":["env","node","--version"],"declared_safety":"read_only"}' \
    '{"argv":["node","--version","--verbose"],"declared_safety":"read_only"}'; do
    if ! result="$(printf '%s\n' "$input" | bash "$classify" --classify-only)"; then
      return 1
    fi
    python3 - "$result" <<'PY' || return 1
import json
import sys

assert json.loads(sys.argv[1]) == {
    "effective_safety": "unknown",
    "declaration_matches": False,
}
PY
  done
}

check_target_probe_readonly_command() {
  local repo="$TEMP_DIR/probe-readonly-repo"
  local evidence="$TEMP_DIR/probe-readonly-evidence"
  local result="$TEMP_DIR/probe-readonly-result.json"
  mkdir -p "$repo" "$evidence"
  write_audit_contract "$repo/contract.md" readonly-node

  bash "$SCRIPT_DIR/run-target-probes.sh" \
    --contract contract.md \
    --target cli_main \
    --item cli.install \
    --evidence-dir "$evidence" \
    "$repo" >"$result"

  python3 - "$result" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["target_id"] == "cli_main"
assert data["item_id"] == "cli.install"
assert data["status"] == "verified"
assert data["error_category"] is None
PY
}

check_target_probe_command_safety_boundaries() {
  local repo="$TEMP_DIR/probe-command-safety-repo"
  local fake_bin="$TEMP_DIR/probe-command-safety-bin"
  local marker_dir="$TEMP_DIR/probe-command-safety-markers"
  local normal_result="$TEMP_DIR/probe-command-safety-normal.json"
  local dry_result="$TEMP_DIR/probe-command-safety-dry.json"
  local real_git
  local normal_status
  local dry_status
  mkdir -p "$repo" "$fake_bin" "$marker_dir"
  write_audit_contract "$repo/contract.md" command-safety
  real_git="$(command -v git)"

  for executable in node git npm unknown-command env; do
    cat >"$fake_bin/$executable" <<SH
#!/bin/sh
if [ "\${1:-}" = "-C" ]; then
  exec "$real_git" "\$@"
fi
touch "$marker_dir/$executable"
printf '%s\n' fixture
exit 0
SH
    chmod +x "$fake_bin/$executable"
  done

  if PATH="$fake_bin:$PATH" bash "$SCRIPT_DIR/verify-setup.sh" \
    --contract contract.md \
    "$repo" >"$normal_result"; then
    return 1
  else
    normal_status=$?
  fi
  [[ "$normal_status" == 4 ]] || return 1

  python3 - "$normal_result" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["verification_report"]
items = {item["id"]: item for item in report["targets"]["cli_main"]["items"]}
for item_id in ("command.node", "command.git"):
    assert items[item_id]["status"] == "verified"
    assert items[item_id]["error_category"] is None
for item_id in (
    "command.npm",
    "command.unknown",
    "command.mismatch",
    "command.absolute",
    "command.wrapper",
    "command.trailing",
):
    assert items[item_id]["status"] == "not_verified"
    assert items[item_id]["error_category"] == "safety_blocked"
PY
  [[ -e "$marker_dir/node" ]] || return 1
  [[ -e "$marker_dir/git" ]] || return 1
  for executable in npm unknown-command env; do
    [[ ! -e "$marker_dir/$executable" ]] || return 1
  done

  if PATH="$fake_bin:$PATH" bash "$SCRIPT_DIR/verify-setup.sh" \
    --dry-run \
    --contract contract.md \
    "$repo" >"$dry_result"; then
    dry_status=0
  else
    dry_status=$?
  fi
  [[ "$dry_status" == 0 ]] || return 1
  python3 - "$dry_result" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
probes = {probe["item_id"]: probe for probe in data["dry_run"]["probes"]}
expected = {
    "command.node": ("read_only", True, "execute"),
    "command.git": ("read_only", True, "execute"),
    "command.npm": ("mutating", True, "not_executed"),
    "command.unknown": ("unknown", False, "not_executed"),
    "command.mismatch": ("read_only", False, "not_executed"),
    "command.absolute": ("unknown", False, "not_executed"),
    "command.wrapper": ("unknown", False, "not_executed"),
    "command.trailing": ("unknown", False, "not_executed"),
}
for item_id, (effective, matches, decision) in expected.items():
    probe = probes[item_id]
    assert probe["effective_safety"] == effective
    assert probe["declaration_matches"] is matches
    assert probe["decision"] == decision
PY
  for executable in npm unknown-command env; do
    [[ ! -e "$marker_dir/$executable" ]] || return 1
  done
}

check_target_probe_enforces_target_type_boundaries() {
  local repo="$TEMP_DIR/probe-target-type-repo"
  local evidence="$TEMP_DIR/probe-target-type-evidence"
  local fake_bin="$TEMP_DIR/probe-target-type-bin"
  local marker="$TEMP_DIR/probe-target-type-started"
  local result="$TEMP_DIR/probe-target-type-result.json"
  mkdir -p "$repo" "$evidence" "$fake_bin"

  cat >"$fake_bin/node" <<SH
#!/bin/sh
touch "$marker"
printf '%s\n' fixture
SH
  cat >"$fake_bin/agent-setup-mcp-stdio-readonly" <<SH
#!/bin/sh
touch "$marker"
while IFS= read -r request; do
  printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{}}'
done
SH
  chmod +x "$fake_bin/node" "$fake_bin/agent-setup-mcp-stdio-readonly"

  for variant in command-on-mcp mcp-on-cli agent-on-cli; do
    write_audit_contract "$repo/contract.md" readonly-node
    python3 - "$repo/contract.md" "$variant" <<'PY'
import sys
from pathlib import Path

import yaml

path = Path(sys.argv[1])
variant = sys.argv[2]
contract = yaml.safe_load(path.read_text(encoding="utf-8").split("\n---", 1)[0][4:])
target = contract["setup_target"]["cli_main"]
verification = contract["verification"]["targets"]["cli_main"]
item = verification["items"][0]

if variant == "command-on-mcp":
    target["target_type"] = "mcp"
    verification["target_type"] = "mcp"
    item["target_type"] = "mcp"
elif variant == "mcp-on-cli":
    target["runtime"] = {
        "mode": "process",
        "command": ["agent-setup-mcp-stdio-readonly"],
        "safety": "read_only",
    }
    item["probe"] = {"kind": "mcp_request", "request": "initialize"}
else:
    item["probe"] = {
        "kind": "agent_action",
        "action": "discovery",
        "adapter": {
            "kind": "command",
            "argv": ["node", "--version"],
            "stdin": "empty",
            "safety": "read_only",
        },
    }

path.write_text(
    "---\n" + yaml.safe_dump(contract, sort_keys=False) + "---\n# body\n",
    encoding="utf-8",
)
PY

    rm -f "$marker"
    if ! PATH="$fake_bin:$PATH" \
      AGENT_SETUP_MCP_FIXTURE="$fake_bin/agent-setup-mcp-stdio-readonly" \
      bash "$SCRIPT_DIR/run-target-probes.sh" \
      --contract contract.md \
      --target cli_main \
      --item cli.install \
      --evidence-dir "$evidence" \
      "$repo" >"$result"; then
      return 1
    fi
    python3 - "$result" <<'PY' || return 1
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["status"] == "not_verified"
assert data["error_category"] == "safety_blocked"
PY
    [[ ! -e "$marker" ]] || return 1
  done
}

check_target_probe_normal_dry_run_classifier_parity() {
  local repo="$TEMP_DIR/probe-classifier-parity-repo"
  local fake_bin="$TEMP_DIR/probe-classifier-parity-bin"
  local normal_result="$TEMP_DIR/probe-classifier-parity-normal.json"
  local dry_result="$TEMP_DIR/probe-classifier-parity-dry.json"
  local normal_status
  local real_git
  mkdir -p "$repo" "$fake_bin"
  write_audit_contract "$repo/contract.md" command-safety
  real_git="$(command -v git)"

  for executable in node git npm unknown-command env; do
    cat >"$fake_bin/$executable" <<SH
#!/bin/sh
if [ "\${1:-}" = "-C" ]; then
  exec "$real_git" "\$@"
fi
printf '%s\n' fixture
exit 0
SH
    chmod +x "$fake_bin/$executable"
  done

  if PATH="$fake_bin:$PATH" bash "$SCRIPT_DIR/verify-setup.sh" \
    --contract contract.md \
    "$repo" >"$normal_result"; then
    return 1
  else
    normal_status=$?
  fi
  [[ "$normal_status" == 4 ]] || return 1

  PATH="$fake_bin:$PATH" bash "$SCRIPT_DIR/verify-setup.sh" \
    --dry-run \
    --contract contract.md \
    "$repo" >"$dry_result"

  python3 - "$repo/contract.md" "$normal_result" "$dry_result" "$SCRIPT_DIR/run-target-probes.sh" <<'PY' || return 1
import json
import subprocess
import sys
from pathlib import Path

import yaml

contract_path, normal_path, dry_path, classifier = sys.argv[1:]
contract_text = Path(contract_path).read_text(encoding="utf-8")
contract = yaml.safe_load(contract_text.split("\n---", 1)[0][4:])
normal = json.loads(Path(normal_path).read_text(encoding="utf-8"))["verification_report"]
dry = json.loads(Path(dry_path).read_text(encoding="utf-8"))["dry_run"]
normal_items = {
    item["id"]: item for item in normal["targets"]["cli_main"]["items"]
}
dry_items = {probe["item_id"]: probe for probe in dry["probes"]}

for item in contract["verification"]["targets"]["cli_main"]["items"]:
    probe = item["probe"]
    payload = json.dumps({
        "argv": probe["argv"],
        "declared_safety": probe["safety"],
    })
    normal_classified = json.loads(subprocess.run(
        ["bash", classifier, "--classify-only"],
        input=payload + "\n",
        text=True,
        capture_output=True,
        check=True,
    ).stdout)
    dry_classified = json.loads(subprocess.run(
        ["bash", classifier, "--classify-only"],
        input=payload + "\n",
        text=True,
        capture_output=True,
        check=True,
    ).stdout)
    assert normal_classified == dry_classified
    classified = normal_classified
    dry_probe = dry_items[item["id"]]
    assert dry_probe["effective_safety"] == classified["effective_safety"]
    assert dry_probe["declaration_matches"] is classified["declaration_matches"]
    normal_item = normal_items[item["id"]]
    if (
        classified["effective_safety"] == "read_only"
        and classified["declaration_matches"]
    ):
        assert normal_item["status"] == "verified"
        assert normal_item["error_category"] is None
    else:
        assert normal_item["status"] == "not_verified"
        assert normal_item["error_category"] == "safety_blocked"
    assert dry_probe["decision"] in {"execute", "not_executed"}

for label, argv, declared_safety, expected_safety, expected_match in (
    ("safe MCP runtime", ["agent-setup-mcp-stdio-readonly"], "read_only", "read_only", True),
    ("mutating command", ["npm", "install"], "mutating", "mutating", True),
    ("unknown command", ["unknown-command", "--check"], "read_only", "unknown", False),
    ("read-only command", ["node", "--version"], "read_only", "read_only", True),
    ("safe Skill adapter", ["node", "--version"], "read_only", "read_only", True),
):
    payload = json.dumps({"argv": argv, "declared_safety": declared_safety})
    normal_classified = json.loads(subprocess.run(
        ["bash", classifier, "--classify-only"],
        input=payload + "\n", text=True, capture_output=True, check=True,
    ).stdout)
    dry_classified = json.loads(subprocess.run(
        ["bash", classifier, "--classify-only"],
        input=payload + "\n", text=True, capture_output=True, check=True,
    ).stdout)
    assert normal_classified == dry_classified
    assert normal_classified["effective_safety"] == expected_safety
    assert normal_classified["declaration_matches"] is expected_match
PY
}

check_target_probe_mcp_runtime_safety_variants() {
  local repo="$TEMP_DIR/probe-mcp-runtime-safety-repo"
  local evidence="$TEMP_DIR/probe-mcp-runtime-safety-evidence"
  local fake_bin="$TEMP_DIR/probe-mcp-runtime-safety-bin"
  local marker="$TEMP_DIR/probe-mcp-runtime-safety-started"
  local normal_result="$TEMP_DIR/probe-mcp-runtime-safety-normal.json"
  local dry_result="$TEMP_DIR/probe-mcp-runtime-safety-dry.json"
  mkdir -p "$repo" "$evidence" "$fake_bin"
  write_audit_contract "$repo/contract.md" mcp-initialize
  cat >"$fake_bin/agent-setup-mcp-stdio-readonly" <<SH
#!/bin/sh
touch "$marker"
while IFS= read -r request; do
  printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{}}'
done
SH
  chmod +x "$fake_bin/agent-setup-mcp-stdio-readonly"

  for variant in safe mutating unknown mismatch; do
    rm -f "$marker"
    python3 - "$repo/contract.md" "$variant" <<'PY'
import sys
from pathlib import Path

import yaml

path = Path(sys.argv[1])
variant = sys.argv[2]
contract = yaml.safe_load(path.read_text(encoding="utf-8").split("\n---", 1)[0][4:])
runtime = contract["setup_target"]["cli_main"]["runtime"]
if variant == "safe":
    runtime["command"] = ["agent-setup-mcp-stdio-readonly"]
    runtime["safety"] = "read_only"
elif variant == "mutating":
    runtime["command"] = ["npm", "install"]
    runtime["safety"] = "mutating"
elif variant == "unknown":
    runtime["command"] = ["unknown-command", "--check"]
    runtime["safety"] = "read_only"
else:
    runtime["command"] = ["agent-setup-mcp-stdio-readonly"]
    runtime["safety"] = "mutating"
path.write_text(
    "---\n" + yaml.safe_dump(contract, sort_keys=False) + "---\n# body\n",
    encoding="utf-8",
)
PY

    if ! AGENT_SETUP_MCP_FIXTURE="$fake_bin/agent-setup-mcp-stdio-readonly" \
      bash "$SCRIPT_DIR/run-target-probes.sh" \
      --contract contract.md \
      --target cli_main \
      --item mcp.initialize \
      --evidence-dir "$evidence" \
      "$repo" >"$normal_result"; then
      return 1
    fi
    python3 - "$variant" "$normal_result" <<'PY'
import json
import sys
from pathlib import Path

variant = sys.argv[1]
data = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
if variant == "safe":
    assert data["status"] == "verified"
    assert data["error_category"] is None
else:
    assert data["status"] == "not_verified"
    assert data["error_category"] == "safety_blocked"
PY
    if [[ "$variant" == safe ]]; then
      [[ -e "$marker" ]] || return 1
    else
      [[ ! -e "$marker" ]] || return 1
    fi

    if ! AGENT_SETUP_MCP_FIXTURE="$fake_bin/agent-setup-mcp-stdio-readonly" \
      bash "$SCRIPT_DIR/verify-setup.sh" \
      --dry-run \
      --contract contract.md \
      "$repo" >"$dry_result"; then
      return 1
    fi
    python3 - "$variant" "$dry_result" <<'PY'
import json
import sys
from pathlib import Path

variant = sys.argv[1]
data = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
runtime = data["dry_run"]["runtimes"][0]
expected = {
    "safe": ("read_only", True),
    "mutating": ("mutating", True),
    "unknown": ("unknown", False),
    "mismatch": ("read_only", False),
}[variant]
assert (runtime["effective_safety"], runtime["declaration_matches"]) == expected
assert runtime["decision"] == "not_executed"
assert data["dry_run"]["probes"][0]["decision"] == "not_executed"
PY
  done
}

check_target_probe_blocks_unsupported_mcp_runtime_modes() {
  local repo="$TEMP_DIR/probe-mcp-unsupported-runtime-repo"
  local evidence="$TEMP_DIR/probe-mcp-unsupported-runtime-evidence"
  local fake_bin="$TEMP_DIR/probe-mcp-unsupported-runtime-bin"
  local marker="$TEMP_DIR/probe-mcp-unsupported-runtime-started"
  local result="$TEMP_DIR/probe-mcp-unsupported-runtime-result.json"
  mkdir -p "$repo" "$evidence" "$fake_bin"
  write_audit_contract "$repo/contract.md" mcp-initialize
  cat >"$fake_bin/agent-setup-mcp-stdio-readonly" <<SH
#!/bin/sh
touch "$marker"
exit 0
SH
  chmod +x "$fake_bin/agent-setup-mcp-stdio-readonly"

  for mode in in_process agent_discovery external_service not_applicable; do
    python3 - "$repo/contract.md" "$mode" <<'PY'
import sys
from pathlib import Path

import yaml

path = Path(sys.argv[1])
mode = sys.argv[2]
contract = yaml.safe_load(path.read_text(encoding="utf-8").split("\n---", 1)[0][4:])
contract["setup_target"]["cli_main"]["runtime"] = {"mode": mode}
path.write_text(
    "---\n" + yaml.safe_dump(contract, sort_keys=False) + "---\n# body\n",
    encoding="utf-8",
)
PY
    rm -f "$marker"
    if ! PATH="$fake_bin:$PATH" \
      AGENT_SETUP_MCP_FIXTURE="$fake_bin/agent-setup-mcp-stdio-readonly" \
      bash "$SCRIPT_DIR/run-target-probes.sh" \
      --contract contract.md \
      --target cli_main \
      --item mcp.initialize \
      --evidence-dir "$evidence" \
      "$repo" >"$result"; then
      return 1
    fi
    python3 - "$result" <<'PY' || return 1
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["status"] == "not_verified"
assert data["error_category"] == "safety_blocked"
PY
    [[ ! -e "$marker" ]] || return 1
  done
}

check_target_probe_mcp_initialize() {
  local repo="$TEMP_DIR/probe-mcp-repo"
  local evidence="$TEMP_DIR/probe-mcp-evidence"
  local fake_bin="$TEMP_DIR/probe-mcp-bin"
  local path_bin="$TEMP_DIR/probe-mcp-path-bin"
  local trusted_marker="$TEMP_DIR/probe-mcp-trusted"
  local path_marker="$TEMP_DIR/probe-mcp-path"
  local result="$TEMP_DIR/probe-mcp-result.json"
  mkdir -p "$repo" "$evidence" "$fake_bin" "$path_bin"
  write_audit_contract "$repo/contract.md" mcp-initialize
  cat >"$fake_bin/agent-setup-mcp-stdio-readonly" <<SH
#!/bin/sh
touch "$trusted_marker"
while IFS= read -r request; do
  printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{}}'
done
SH
  cat >"$path_bin/agent-setup-mcp-stdio-readonly" <<SH
#!/bin/sh
touch "$path_marker"
while IFS= read -r request; do
  printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{}}'
done
SH
  chmod +x "$fake_bin/agent-setup-mcp-stdio-readonly"
  chmod +x "$path_bin/agent-setup-mcp-stdio-readonly"

  PATH="$path_bin:$PATH" AGENT_SETUP_MCP_FIXTURE="$fake_bin/agent-setup-mcp-stdio-readonly" \
    bash "$SCRIPT_DIR/run-target-probes.sh" \
    --contract contract.md \
    --target cli_main \
    --item mcp.initialize \
    --evidence-dir "$evidence" \
    "$repo" >"$result"

  [[ -s "$result" ]] || return 1
  python3 - "$result" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["status"] == "verified"
assert data["error_category"] is None
PY
  [[ -e "$trusted_marker" ]]
  [[ ! -e "$path_marker" ]]
}

check_target_probe_validates_mcp_fixture_path() {
  local repo="$TEMP_DIR/probe-mcp-fixture-validation-repo"
  local evidence="$TEMP_DIR/probe-mcp-fixture-validation-evidence"
  local fake_bin="$TEMP_DIR/probe-mcp-fixture-validation-bin"
  local external_fixture="$fake_bin/agent-setup-mcp-stdio-readonly"
  local internal_fixture="$repo/agent-setup-mcp-stdio-readonly"
  local internal_link="$repo/agent-setup-mcp-stdio-readonly-link"
  local result="$TEMP_DIR/probe-mcp-fixture-validation-result.json"
  local fixture
  local expected_category
  local expected_status
  local case_value
  mkdir -p "$repo" "$evidence" "$fake_bin"
  write_audit_contract "$repo/contract.md" mcp-initialize
  cat >"$external_fixture" <<'SH'
#!/bin/sh
while IFS= read -r request; do
  printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{}}'
done
SH
  chmod +x "$external_fixture"
  printf '%s\n' '#!/bin/sh' 'exit 0' >"$internal_fixture"
  chmod +x "$internal_fixture"
  ln -s "$external_fixture" "$internal_link"

  for case_value in \
    "relative-fixture not_verified capability_unavailable" \
    "$external_fixture verified null" \
    "$internal_fixture not_verified safety_blocked" \
    "$internal_link not_verified safety_blocked"; do
    read -r fixture expected_status expected_category <<<"$case_value"
    if ! AGENT_SETUP_MCP_FIXTURE="$fixture" \
      bash "$SCRIPT_DIR/run-target-probes.sh" \
      --contract contract.md \
      --target cli_main \
      --item mcp.initialize \
      --evidence-dir "$evidence" \
      "$repo" >"$result"; then
      return 1
    fi
    python3 - "$result" "$expected_status" "$expected_category" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["status"] == sys.argv[2]
if sys.argv[3] == "null":
    assert data["error_category"] is None
else:
    assert data["error_category"] == sys.argv[3]
PY
  done
}

check_target_probe_mcp_protocol_operations() {
  local repo="$TEMP_DIR/probe-mcp-protocol-repo"
  local evidence="$TEMP_DIR/probe-mcp-protocol-evidence"
  local fake_bin="$TEMP_DIR/probe-mcp-protocol-bin"
  local request_log="$TEMP_DIR/probe-mcp-protocol-requests.jsonl"
  local result="$TEMP_DIR/probe-mcp-protocol-result.json"
  mkdir -p "$repo" "$evidence" "$fake_bin"

  cat >"$fake_bin/agent-setup-mcp-stdio-readonly" <<SH
#!/bin/sh
while IFS= read -r request; do
  printf '%s\n' "\$request" >> "$request_log"
  case "\$request" in
    *'"method":"initialize"'*)
      printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-06-18"}}'
      ;;
    *'"method":"tools/list"'*)
      printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{"tools":[]}}'
      ;;
    *'"method":"tools/call"'*)
      printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{"content":[{"type":"text","text":"fixture"}]}}'
      ;;
  esac
done
SH
  chmod +x "$fake_bin/agent-setup-mcp-stdio-readonly"

  for variant in mcp-tool-discovery mcp-representative-readonly; do
    write_audit_contract "$repo/contract.md" "$variant"
    : >"$request_log"
    if ! AGENT_SETUP_MCP_FIXTURE="$fake_bin/agent-setup-mcp-stdio-readonly" \
      bash "$SCRIPT_DIR/run-target-probes.sh" \
      --contract contract.md \
      --target cli_main \
      --item "$(if [[ "$variant" == mcp-tool-discovery ]]; then printf '%s' mcp.tool-discovery; else printf '%s' mcp.representative-readonly; fi)" \
      --evidence-dir "$evidence" \
      "$repo" >"$result"; then
      return 1
    fi
    python3 - "$variant" "$result" "$request_log" <<'PY'
import json
import sys
from pathlib import Path

variant = sys.argv[1]
result = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
assert result["status"] == "verified"
assert result["error_category"] is None
requests = [
    json.loads(line)
    for line in Path(sys.argv[3]).read_text(encoding="utf-8").splitlines()
]
if variant == "mcp-tool-discovery":
    assert len(requests) == 1
    assert requests[0]["method"] == "tools/list"
    assert requests[0]["params"] == {}
else:
    assert [request["method"] for request in requests] == [
        "initialize",
        "tools/list",
        "tools/call",
    ]
    assert requests[0]["params"] == {}
    assert requests[1]["params"] == {}
    assert requests[2]["params"] == {
        "name": "read_fixture",
        "arguments": {"name": "test"},
    }
PY
  done
}

check_target_probe_rejects_mcp_initialize_error() {
  local repo="$TEMP_DIR/probe-mcp-error-repo"
  local evidence="$TEMP_DIR/probe-mcp-error-evidence"
  local fake_bin="$TEMP_DIR/probe-mcp-error-bin"
  local result="$TEMP_DIR/probe-mcp-error-result.json"
  mkdir -p "$repo" "$evidence" "$fake_bin"
  write_audit_contract "$repo/contract.md" mcp-initialize
  cat >"$fake_bin/agent-setup-mcp-stdio-readonly" <<'SH'
#!/bin/sh
while IFS= read -r request; do
  printf '%s\n' '{"jsonrpc":"2.0","id":1,"error":{"code":-32000,"message":"fixture initialization failed"}}'
done
SH
  chmod +x "$fake_bin/agent-setup-mcp-stdio-readonly"

  if ! AGENT_SETUP_MCP_FIXTURE="$fake_bin/agent-setup-mcp-stdio-readonly" \
    bash "$SCRIPT_DIR/run-target-probes.sh" \
    --contract contract.md \
    --target cli_main \
    --item mcp.initialize \
    --evidence-dir "$evidence" \
    "$repo" >"$result"; then
    return 1
  fi
  python3 - "$result" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["status"] == "not_verified"
assert data["error_category"] == "runtime_failure"
PY
}

check_target_probe_rejects_malformed_mcp_response() {
  local repo="$TEMP_DIR/probe-malformed-mcp-repo"
  local evidence="$TEMP_DIR/probe-malformed-mcp-evidence"
  local fake_bin="$TEMP_DIR/probe-malformed-mcp-bin"
  local result="$TEMP_DIR/probe-malformed-mcp-result.json"
  mkdir -p "$repo" "$evidence" "$fake_bin"
  write_audit_contract "$repo/contract.md" mcp-initialize
  cat >"$fake_bin/agent-setup-mcp-stdio-readonly" <<'SH'
#!/bin/sh
while IFS= read -r request; do
  printf '%s\n' 'not-json-rpc'
done
SH
  chmod +x "$fake_bin/agent-setup-mcp-stdio-readonly"

  AGENT_SETUP_MCP_FIXTURE="$fake_bin/agent-setup-mcp-stdio-readonly" \
    bash "$SCRIPT_DIR/run-target-probes.sh" \
    --contract contract.md \
    --target cli_main \
    --item mcp.initialize \
    --evidence-dir "$evidence" \
    "$repo" >"$result"

  [[ -s "$result" ]] || return 1
  python3 - "$result" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["status"] == "not_verified"
assert data["error_category"] == "runtime_failure"
PY
}

check_target_probe_blocks_temporary_fixture() {
  local repo="$TEMP_DIR/probe-temporary-fixture-repo"
  local evidence="$TEMP_DIR/probe-temporary-fixture-evidence"
  local fake_bin="$TEMP_DIR/probe-temporary-fixture-bin"
  local marker="$TEMP_DIR/probe-temporary-fixture-started"
  local result="$TEMP_DIR/probe-temporary-fixture-result.json"
  mkdir -p "$repo" "$evidence" "$fake_bin"
  write_audit_contract "$repo/contract.md" temporary-fixture
  cat >"$fake_bin/agent-setup-mcp-stdio-readonly" <<SH
#!/bin/sh
touch "$marker"
SH
  chmod +x "$fake_bin/agent-setup-mcp-stdio-readonly"

  PATH="$fake_bin:$PATH" bash "$SCRIPT_DIR/run-target-probes.sh" \
    --contract contract.md \
    --target cli_main \
    --item mcp.temporary \
    --evidence-dir "$evidence" \
    "$repo" >"$result"

  [[ -s "$result" ]] || return 1
  python3 - "$result" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["status"] == "not_verified"
assert data["error_category"] == "safety_blocked"
PY
  [[ ! -e "$marker" ]]
}

check_verification_temporary_fixture_handoff_boundary() {
  local repo="$TEMP_DIR/temporary-handoff-repo"
  local fake_bin="$TEMP_DIR/temporary-handoff-bin"
  local runtime_marker="$TEMP_DIR/temporary-handoff-runtime-started"
  local normal_result="$TEMP_DIR/temporary-handoff-normal.json"
  local dry_result="$TEMP_DIR/temporary-handoff-dry.json"
  local normal_status
  local dry_status
  mkdir -p "$repo" "$fake_bin"
  write_audit_contract "$repo/contract.md" temporary-fixture
  python3 - "$repo/contract.md" <<'PY'
import sys
from pathlib import Path

import yaml

path = Path(sys.argv[1])
contract = yaml.safe_load(path.read_text(encoding="utf-8").split("\n---", 1)[0][4:])
contract["verification"]["targets"]["cli_main"]["items"][0]["handoff_id"] = "temporary-review"
contract["handoffs"] = {
    "temporary-review": {
        "actor": "user",
        "action": "Review the temporary resource operation.",
        "prerequisites": [],
        "expected_outcome": "The temporary resource is approved.",
        "required_evidence": [{"type": "command_output", "summary": "review"}],
    }
}
path.write_text(
    "---\n" + yaml.safe_dump(contract, sort_keys=False) + "---\n# body\n",
    encoding="utf-8",
)
PY
  cat >"$fake_bin/agent-setup-mcp-stdio-readonly" <<SH
#!/bin/sh
touch "$runtime_marker"
exit 0
SH
  chmod +x "$fake_bin/agent-setup-mcp-stdio-readonly"

  if PATH="$fake_bin:$PATH" \
    AGENT_SETUP_MCP_FIXTURE="$fake_bin/agent-setup-mcp-stdio-readonly" \
    bash "$SCRIPT_DIR/verify-setup.sh" \
    --contract contract.md \
    "$repo" >"$normal_result"; then
    return 1
  else
    normal_status=$?
  fi
  [[ "$normal_status" == 4 ]] || return 1
  [[ ! -e "$runtime_marker" ]] || return 1
  python3 - "$normal_result" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["verification_report"]
item = report["targets"]["cli_main"]["items"][0]
assert item["status"] == "not_verified"
assert item["error_category"] == "safety_blocked"
assert len(report["handoffs"]) == 1
assert report["handoffs"][0]["handoff_id"] == "temporary-review"
PY

  if PATH="$fake_bin:$PATH" \
    AGENT_SETUP_MCP_FIXTURE="$fake_bin/agent-setup-mcp-stdio-readonly" \
    bash "$SCRIPT_DIR/verify-setup.sh" \
    --dry-run \
    --contract contract.md \
    "$repo" >"$dry_result"; then
    dry_status=0
  else
    dry_status=$?
  fi
  [[ "$dry_status" == 0 ]] || return 1
  [[ ! -e "$runtime_marker" ]] || return 1
  python3 - "$dry_result" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
assert data["dry_run"]["decision"] == "not_executed"
assert data["dry_run"]["probes"][0]["decision"] == "not_executed"
assert data["verification_report"]["handoffs"] == []
assert [
    reference["handoff_id"]
    for reference in data["verification_report"]["handoff_references"]
] == ["temporary-review"]
PY
}

check_non_probe_plugin_uses_only_defined_handoff() {
  local repo="$TEMP_DIR/plugin-handoff-repo"
  local normal_result="$TEMP_DIR/plugin-handoff-normal.json"
  local dry_result="$TEMP_DIR/plugin-handoff-dry.json"
  local normal_status
  local dry_status
  mkdir -p "$repo"
  write_dry_run_contract "$repo/contract.md"
  python3 - "$repo/contract.md" <<'PY'
import sys
from pathlib import Path

import yaml

path = Path(sys.argv[1])
contract = yaml.safe_load(path.read_text(encoding="utf-8").split("\n---", 1)[0][4:])
target = contract["setup_target"]["cli_main"]
target["target_type"] = "plugin"
target["runtime"] = {"mode": "in_process"}
contract["setup_target"] = {"cli_main": target}
verification_target = contract["verification"]["targets"]["cli_main"]
verification_target["target_type"] = "plugin"
verification_target["items"] = [{
    "id": "plugin.activation",
    "phase": "activation",
    "target_type": "plugin",
    "required_for_e2e": False,
    "blocked_by": [],
    "handoff_id": "plugin-review",
}]
contract["verification"] = {"targets": {"cli_main": verification_target}}
for section in ("installation", "registration", "discovery", "activation"):
    contract[section] = {"cli_main": contract[section]["cli_main"]}
contract["handoffs"] = {
    "plugin-review": {
        "actor": "user",
        "action": "Review the Plugin activation.",
        "prerequisites": [],
        "expected_outcome": "The Plugin is activated.",
        "required_evidence": [{"type": "command_output", "summary": "activation"}],
    }
}
path.write_text(
    "---\n" + yaml.safe_dump(contract, sort_keys=False) + "---\n# body\n",
    encoding="utf-8",
)
PY

  if bash "$SCRIPT_DIR/verify-setup.sh" \
    --contract contract.md \
    "$repo" >"$normal_result"; then
    normal_status=0
  else
    normal_status=$?
  fi
  [[ "$normal_status" == 0 ]] || return 1
  python3 - "$normal_result" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["verification_report"]
item = report["targets"]["cli_main"]["items"][0]
assert item["status"] == "not_verified"
assert item["error_category"] is None
assert report["targets"]["cli_main"]["e2e_status"] == "not_applicable"
assert [handoff["handoff_id"] for handoff in report["handoffs"]] == ["plugin-review"]
PY

  if bash "$SCRIPT_DIR/verify-setup.sh" \
    --dry-run \
    --contract contract.md \
    "$repo" >"$dry_result"; then
    dry_status=0
  else
    dry_status=$?
  fi
  [[ "$dry_status" == 0 ]] || return 1
  python3 - "$dry_result" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
assert data["dry_run"]["probes"][0]["decision"] == "not_executed"
assert data["verification_report"]["handoffs"] == []
assert [
    reference["handoff_id"]
    for reference in data["verification_report"]["handoff_references"]
] == ["plugin-review"]
PY
}

check_target_probe_rejects_internal_evidence_dir_without_mutation() {
  local repo="$TEMP_DIR/probe-internal-evidence-repo"
  local evidence="$repo/.agent-setup/evidence"
  mkdir -p "$repo"

  if bash "$SCRIPT_DIR/run-target-probes.sh" \
    --contract contract.md \
    --target cli_main \
    --item cli.install \
    --evidence-dir "$evidence" \
    "$repo" >/dev/null 2>/dev/null; then
    return 1
  fi
  [[ ! -e "$evidence" ]]
}

check_verification_exposes_enhanced_workflow() {
  local repo="$TEMP_DIR/enhanced-verification-plan-repo"
  mkdir -p "$repo/.agent-setup"
  write_audit_contract "$repo/SETUP-CONTRACT.md" readonly-node
  cat >"$repo/.agent-setup/analyze.json" <<'JSON'
{
  "complexity_triggers": [
    {"id": "mcp-runtime", "evidence": "mcp.json", "note": "runtime"}
  ],
  "env_template": false
}
JSON
  write_analysis_fingerprint "$repo"

  bash "$SCRIPT_DIR/verify-setup.sh" "$repo" 2>/dev/null |
    python3 -c '
import json
import sys

plan = json.load(sys.stdin)
enhanced = plan["enhanced_workflow"]
assert enhanced["probe_executor"] == "run-target-probes.sh"
assert enhanced["classify_only_command"] == "run-target-probes.sh --classify-only"
assert enhanced["temporary_fixture_policy"] == "safety_blocked"
'
}

check_dry_run_preserves_target_and_reports_snapshots() {
  local repo="$TEMP_DIR/dry-run-pristine-repo"
  local report="$TEMP_DIR/dry-run-pristine-report.md"
  local result="$TEMP_DIR/dry-run-pristine-result.json"
  mkdir -p "$repo/src"
  printf '%s\n' 'source' >"$repo/src/README.md"

  git -C "$repo" init -q
  git -C "$repo" config user.email test@example.invalid
  git -C "$repo" config user.name "Agent Setup Test"
  git -C "$repo" add src/README.md
  git -C "$repo" commit -qm initial

  bash "$SCRIPT_DIR/verify-setup.sh" \
    --dry-run \
    --report "$report" \
    "$repo" >"$result"

  [[ ! -e "$repo/.agent-setup" ]] || return 1
  [[ -z "$(git -C "$repo" status --porcelain)" ]] || return 1
  [[ -f "$report" ]] || return 1

  python3 - "$result" <<'PY'
import json
from pathlib import Path
import sys

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
dry_run = data["dry_run"]
assert dry_run["decision"] == "not_executed"
assert dry_run["before_snapshot"]["agent_setup_exists"] is False
assert dry_run["after_snapshot"]["agent_setup_exists"] is False
PY
}

check_dry_run_classifies_policy_and_blocks_processes() {
  local repo="$TEMP_DIR/dry-run-safety-repo"
  local fake_bin="$TEMP_DIR/dry-run-safety-bin"
  local marker="$TEMP_DIR/dry-run-process-started"
  local result="$TEMP_DIR/dry-run-safety-result.json"
  mkdir -p "$repo/src" "$fake_bin"
  write_dry_run_contract "$repo/contract.md"

  for executable in node npm unknown-command agent-setup-mcp-stdio-readonly; do
    cat >"$fake_bin/$executable" <<SH
#!/bin/sh
touch "$marker"
exit 0
SH
    chmod +x "$fake_bin/$executable"
  done

  PATH="$fake_bin:$PATH" bash "$SCRIPT_DIR/verify-setup.sh" \
    --dry-run \
    --contract contract.md \
    --report "$TEMP_DIR/dry-run-safety-report.md" \
    "$repo" >"$result"

  [[ ! -e "$marker" ]] || return 1
  [[ ! -e "$repo/.agent-setup" ]] || return 1

  python3 - "$result" <<'PY'
import json
from pathlib import Path
import sys

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
probes = {
    (probe["target_id"], probe["item_id"]): probe
    for probe in data["dry_run"]["probes"]
}

for item_id in ("cli.node", "cli.git"):
    probe = probes[("cli_main", item_id)]
    assert probe["effective_safety"] == "read_only"
    assert probe["declaration_matches"] is True
    assert probe["decision"] == "execute"

for item_id, effective_safety, matches in (
    ("cli.install", "mutating", True),
    ("cli.unknown", "unknown", False),
    ("cli.mismatch", "read_only", False),
):
    probe = probes[("cli_main", item_id)]
    assert probe["effective_safety"] == effective_safety
    assert probe["declaration_matches"] is matches
    assert probe["decision"] == "not_executed"

skill = probes[("skill_main", "skill.adapter")]
assert skill["effective_safety"] == "read_only"
assert skill["declaration_matches"] is True
assert skill["decision"] == "not_executed"

temporary = probes[("mcp_main", "mcp.temporary")]
assert temporary["decision"] == "not_executed"

runtimes = {runtime["target_id"]: runtime for runtime in data["dry_run"]["runtimes"]}
assert runtimes["mcp_main"]["effective_safety"] == "read_only"
assert runtimes["mcp_main"]["declaration_matches"] is True
assert runtimes["mcp_main"]["decision"] == "not_executed"
PY
}

check_dry_run_blocks_confirmed_audit_targets() {
  local repo="$TEMP_DIR/dry-run-confirmed-audit-repo"
  local report="$TEMP_DIR/dry-run-confirmed-audit-report.md"
  local result="$TEMP_DIR/dry-run-confirmed-audit-result.json"
  local status
  mkdir -p "$repo"
  write_topology_fixture "$repo"
  set_report_contract_probe_commands "$repo/contract.md"

  if bash "$SCRIPT_DIR/verify-setup.sh" \
    --dry-run \
    --contract contract.md \
    --report "$report" \
    "$repo" >"$result"; then
    return 1
  else
    status=$?
  fi
  [[ "$status" == "4" ]] || return 1

  python3 - "$result" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
report = data["verification_report"]
assert report["overall_status"] == "not_verified"
assert report["targets"]["cli_main"]["audit_blocked"] is True
assert report["targets"]["other_valid"]["audit_blocked"] is False

probes = report["dry_run"]["probes"]
affected = [probe for probe in probes if probe["target_id"] == "cli_main"]
unaffected = [probe for probe in probes if probe["target_id"] == "other_valid"]
assert affected
assert all(probe["decision"] == "not_executed" for probe in affected)
assert all(probe["error_category"] == "audit_blocked" for probe in affected)
assert unaffected
assert any(probe["decision"] == "execute" for probe in unaffected)
PY
}

check_dry_run_skill_handoff_is_reference_only() {
  local repo="$TEMP_DIR/dry-run-skill-handoff-repo"
  local report="$TEMP_DIR/dry-run-skill-handoff-report.md"
  local result="$TEMP_DIR/dry-run-skill-handoff-result.json"
  mkdir -p "$repo/src"
  write_dry_run_contract "$repo/contract.md"
  python3 - "$repo/contract.md" <<'PY'
import sys
from pathlib import Path

import yaml

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
contract = yaml.safe_load(text.split("\n---", 1)[0][4:])
contract["verification"]["targets"]["skill_main"]["items"][0]["handoff_id"] = "skill-review"
contract["handoffs"] = {
    "skill-review": {
        "actor": "user",
        "action": "Review the Skill discovery result.",
        "prerequisites": [],
        "expected_outcome": "The Skill is discoverable.",
        "required_evidence": [{"type": "command_output", "summary": "discovery"}],
    }
}
path.write_text(
    "---\n" + yaml.safe_dump(contract, sort_keys=False) + "---\n# body\n",
    encoding="utf-8",
)
PY

  bash "$SCRIPT_DIR/verify-setup.sh" \
    --dry-run \
    --contract contract.md \
    --report "$report" \
    "$repo" >"$result"

  python3 - "$result" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
report = data["verification_report"]
assert report["dry_run"]["decision"] == "not_executed"
assert report["handoffs"] == []
references = report["handoff_references"]
assert len(references) == 1
assert references[0]["handoff_id"] == "skill-review"
assert references[0]["definition"]["actor"] == "user"
skill_probe = next(
    probe
    for probe in data["dry_run"]["probes"]
    if probe["target_id"] == "skill_main"
)
assert skill_probe["decision"] == "not_executed"
PY
}

check_normal_skill_safety_rejection_records_only_defined_handoff() {
  local repo="$TEMP_DIR/normal-skill-handoff-repo"
  local report="$TEMP_DIR/normal-skill-handoff-report.md"
  local result="$TEMP_DIR/normal-skill-handoff-result.json"
  local status
  mkdir -p "$repo/src"
  write_dry_run_contract "$repo/contract.md"
  python3 - "$repo/contract.md" <<'PY'
import sys
from pathlib import Path

import yaml

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
contract = yaml.safe_load(text.split("\n---", 1)[0][4:])
contract["verification"]["targets"]["skill_main"]["items"][0]["handoff_id"] = "skill-review"
contract["handoffs"] = {
    "skill-review": {
        "actor": "user",
        "action": "Review the Skill discovery result.",
        "prerequisites": [],
        "expected_outcome": "The Skill is discoverable.",
        "required_evidence": [{"type": "command_output", "summary": "discovery"}],
    }
}
path.write_text(
    "---\n" + yaml.safe_dump(contract, sort_keys=False) + "---\n# body\n",
    encoding="utf-8",
)
PY

  if bash "$SCRIPT_DIR/verify-setup.sh" \
    --contract contract.md \
    --report "$report" \
    "$repo" >"$result"; then
    return 1
  else
    status=$?
  fi
  [[ "$status" == "4" ]] || return 1

  python3 - "$result" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["verification_report"]
assert len(report["handoffs"]) == 1
handoff = report["handoffs"][0]
assert handoff["handoff_id"] == "skill-review"
assert handoff["verification_item_id"] == "skill.adapter"
assert handoff["actor"] == "user"
assert handoff["status"] == "pending"
assert handoff["evaluation_result"] == "needs_review"
item = report["targets"]["skill_main"]["items"][0]
assert item["status"] == "not_verified"
assert item["error_category"] == "safety_blocked"
PY
}

check_skill_discovery_and_activation_never_start_adapters() {
  local repo="$TEMP_DIR/skill-boundary-repo"
  local fake_bin="$TEMP_DIR/skill-boundary-bin"
  local adapter_marker="$TEMP_DIR/skill-boundary-adapter-started"
  local normal_result="$TEMP_DIR/skill-boundary-normal.json"
  local dry_result="$TEMP_DIR/skill-boundary-dry.json"
  local normal_status
  local dry_status
  mkdir -p "$repo/src" "$fake_bin"
  write_dry_run_contract "$repo/contract.md"
  python3 - "$repo/contract.md" <<'PY'
import sys
from pathlib import Path

import yaml

path = Path(sys.argv[1])
contract = yaml.safe_load(path.read_text(encoding="utf-8").split("\n---", 1)[0][4:])
skill_target = contract["setup_target"]["skill_main"]
skill_verification = contract["verification"]["targets"]["skill_main"]
discovery = skill_verification["items"][0]
discovery["required_capabilities"] = ["agent_discovery_probe"]
discovery["handoff_id"] = "skill-discovery-review"
activation = {
    "id": "skill.activation",
    "phase": "activation",
    "target_type": "skill",
    "required_for_e2e": True,
    "blocked_by": [],
    "required_capabilities": ["representative_activation_probe"],
    "handoff_id": "skill-activation-review",
    "probe": {
        "kind": "agent_action",
        "action": "activation",
        "adapter": {
            "kind": "command",
            "argv": ["node", "--version"],
            "stdin": "empty",
            "safety": "read_only",
        },
    },
}
skill_verification["items"] = [discovery, activation]
for section in ("installation", "registration", "discovery", "activation"):
    contract[section] = {"skill_main": contract[section]["skill_main"]}
contract["setup_target"] = {"skill_main": skill_target}
contract["verification"] = {"targets": {"skill_main": skill_verification}}
contract["handoffs"] = {
    "skill-discovery-review": {
        "actor": "user",
        "action": "Review Skill discovery.",
        "prerequisites": [],
        "expected_outcome": "The Skill is discoverable.",
        "required_evidence": [{"type": "command_output", "summary": "discovery"}],
    },
    "skill-activation-review": {
        "actor": "user",
        "action": "Review Skill activation.",
        "prerequisites": [],
        "expected_outcome": "The Skill is activated.",
        "required_evidence": [{"type": "command_output", "summary": "activation"}],
    },
}
path.write_text(
    "---\n" + yaml.safe_dump(contract, sort_keys=False) + "---\n# body\n",
    encoding="utf-8",
)
PY
  cat >"$fake_bin/node" <<SH
#!/bin/sh
touch "$adapter_marker"
printf '%s\n' fixture
SH
  chmod +x "$fake_bin/node"

  if PATH="$fake_bin:$PATH" bash "$SCRIPT_DIR/verify-setup.sh" \
    --contract contract.md \
    "$repo" >"$normal_result"; then
    return 1
  else
    normal_status=$?
  fi
  [[ "$normal_status" == 4 ]] || return 1
  [[ ! -e "$adapter_marker" ]] || return 1
  python3 - "$normal_result" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["verification_report"]
items = {item["id"]: item for item in report["targets"]["skill_main"]["items"]}
assert set(items) == {"skill.adapter", "skill.activation"}
for item_id, handoff_id in (
    ("skill.adapter", "skill-discovery-review"),
    ("skill.activation", "skill-activation-review"),
):
    assert items[item_id]["status"] == "not_verified"
    assert items[item_id]["error_category"] == "safety_blocked"
    assert items[item_id]["handoff_id"] == handoff_id
assert {handoff["handoff_id"] for handoff in report["handoffs"]} == {
    "skill-discovery-review",
    "skill-activation-review",
}
PY

  if PATH="$fake_bin:$PATH" bash "$SCRIPT_DIR/verify-setup.sh" \
    --dry-run \
    --contract contract.md \
    "$repo" >"$dry_result"; then
    dry_status=0
  else
    dry_status=$?
  fi
  [[ "$dry_status" == 0 ]] || return 1
  [[ ! -e "$adapter_marker" ]] || return 1
  python3 - "$dry_result" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
probes = {probe["item_id"]: probe for probe in data["dry_run"]["probes"]}
for item_id in ("skill.adapter", "skill.activation"):
    assert probes[item_id]["effective_safety"] == "read_only"
    assert probes[item_id]["declaration_matches"] is True
    assert probes[item_id]["decision"] == "not_executed"
assert data["verification_report"]["handoffs"] == []
assert {
    reference["handoff_id"]
    for reference in data["verification_report"]["handoff_references"]
} == {"skill-discovery-review", "skill-activation-review"}
PY
}

check_dry_run_rejects_target_internal_report() {
  local repo="$TEMP_DIR/dry-run-internal-report-repo"
  local stderr_file="$TEMP_DIR/dry-run-internal-report.stderr"
  mkdir -p "$repo/src"
  write_dry_run_contract "$repo/contract.md"

  if bash "$SCRIPT_DIR/verify-setup.sh" \
    --dry-run \
    --contract contract.md \
    --report "$repo/report.md" \
    "$repo" > /dev/null 2>"$stderr_file"; then
    return 1
  else
    local status=$?
  fi

  [[ "$status" == 2 ]] || return 1
  [[ ! -e "$repo/report.md" ]] || return 1
  [[ ! -e "$repo/.agent-setup" ]] || return 1
}

check_verification_detects_readme_contract_marker() {
  local repo="$TEMP_DIR/readme-contract-marker-repo"
  local result="$TEMP_DIR/readme-contract-marker-result.json"
  mkdir -p "$repo"
  write_audit_contract "$repo/contract.md" readonly-node
  printf '%s\n' '<!-- agent-setup-contract: contract.md -->' >"$repo/README.md"

  bash "$SCRIPT_DIR/verify-setup.sh" "$repo" >"$result"

  python3 - "$result" <<'PY'
import json
import sys

plan = json.load(open(sys.argv[1], encoding="utf-8"))
assert "enhanced_workflow" in plan
assert plan["contract"] == "contract.md"
assert plan["contract_audit"]["contract_discovery"] == {
    "status": "found",
    "path": "contract.md",
    "source": "repository_declared",
}
PY
}

check_verification_rejects_ambiguous_contract_markers() {
  local repo="$TEMP_DIR/ambiguous-contract-markers-repo"
  local stderr_file="$TEMP_DIR/ambiguous-contract-markers.stderr"
  local status
  mkdir -p "$repo"
  write_audit_contract "$repo/contract-a.md"
  write_audit_contract "$repo/contract-b.md"
  printf '%s\n' '<!-- agent-setup-contract: contract-a.md -->' >"$repo/AGENTS.md"
  printf '%s\n' '<!-- agent-setup-contract: contract-b.md -->' >"$repo/README.md"

  if bash "$SCRIPT_DIR/verify-setup.sh" "$repo" >/dev/null 2>"$stderr_file"; then
    return 1
  else
    status=$?
  fi

  [[ "$status" == 2 ]] || return 1
  grep -q 'ambiguous' "$stderr_file" || return 1
  grep -q 'contract_discovery' "$stderr_file" || return 1
}

check_dry_run_rejects_symlinked_temp_root_inside_target() {
  local repo="$TEMP_DIR/symlinked-tmpdir-repo"
  local target_tmp="$repo/target-tmp"
  local linked_tmp="$TEMP_DIR/symlinked-tmpdir"
  local stderr_file="$TEMP_DIR/symlinked-tmpdir.stderr"
  local status
  mkdir -p "$target_tmp"
  ln -s "$target_tmp" "$linked_tmp"

  if TMPDIR="$linked_tmp" bash "$SCRIPT_DIR/verify-setup.sh" --dry-run "$repo" \
    >/dev/null 2>"$stderr_file"; then
    return 1
  else
    status=$?
  fi

  [[ "$status" == 1 ]] || return 1
  grep -q 'temporary storage is inside the target repository' "$stderr_file" || return 1
  [[ -z "$(compgen -G "$target_tmp/agent-driven-setup.*" || true)" ]] || return 1
}

set_report_contract_probe_commands() {
  local contract="$1"

  python3 - "$contract" <<'PY'
import sys
from pathlib import Path

import yaml

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
contract = yaml.safe_load(text.split("\n---", 1)[0][4:])
for verification in contract["verification"]["targets"].values():
    for item in verification["items"]:
        probe = item.get("probe", {})
        if probe.get("kind") == "command":
            probe["argv"] = ["node", "--version"]
            probe["safety"] = "read_only"
path.write_text(
    "---\n" + yaml.safe_dump(contract, sort_keys=False) + "---\n# body\n",
    encoding="utf-8",
)
PY
}

check_verification_report_all_required_items_verified() {
  local repo="$TEMP_DIR/report-all-verified-repo"
  local report="$TEMP_DIR/report-all-verified.md"
  local result="$TEMP_DIR/report-all-verified.json"
  mkdir -p "$repo"
  write_audit_contract "$repo/contract.md" readonly-node
  python3 - "$repo/contract.md" <<'PY'
import sys
from pathlib import Path

import yaml

path = Path(sys.argv[1])
contract = yaml.safe_load(path.read_text(encoding="utf-8").split("\n---", 1)[0][4:])
contract["verification"]["targets"]["cli_main"]["items"][0][
    "required_capabilities"
] = ["representative_activation_probe"]
path.write_text(
    "---\n" + yaml.safe_dump(contract, sort_keys=False) + "---\n# body\n",
    encoding="utf-8",
)
PY
  printf '%s\n' 'test:' >"$repo/Makefile"

  bash "$SCRIPT_DIR/verify-setup.sh" \
    --contract contract.md \
    --report "$report" \
    "$repo" >"$result"

  python3 - "$result" "$report" <<'PY'
import json
import sys
from pathlib import Path

stdout = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
report = stdout["verification_report"]
markdown = Path(sys.argv[2]).read_text(encoding="utf-8")

assert {"commands", "notes", "makefile_targets", "verification_report"} <= stdout.keys()
assert report["generated_at"]
assert report["overall_status"] == "verified"
assert report["targets"]["cli_main"]["e2e_status"] == "verified"
items = report["targets"]["cli_main"]["items"]
assert items and all(item["status"] == "verified" for item in items)
assert report["capability_assessment"]
assert report["handoffs"] == []
assert report["dry_run"]["decision"] == "not_executed"
assert markdown.startswith("---\n")
assert "# Verification Report" in markdown
assert "overall_status: verified" in markdown
PY
}

check_capability_assessment_unknown_capability_blocks_item() {
  local repo="$TEMP_DIR/capability-unknown-repo"
  local result="$TEMP_DIR/capability-unknown-result.json"
  local status
  mkdir -p "$repo"
  write_audit_contract "$repo/contract.md" readonly-node
  python3 - "$repo/contract.md" <<'PY'
import sys
from pathlib import Path

import yaml

path = Path(sys.argv[1])
contract = yaml.safe_load(path.read_text(encoding="utf-8").split("\n---", 1)[0][4:])
contract["verification"]["targets"]["cli_main"]["items"][0][
    "required_capabilities"
] = ["future_capability"]
path.write_text(
    "---\n" + yaml.safe_dump(contract, sort_keys=False) + "---\n# body\n",
    encoding="utf-8",
)
PY

  if bash "$SCRIPT_DIR/verify-setup.sh" \
    --contract contract.md \
    "$repo" >"$result"; then
    return 1
  else
    status=$?
  fi
  [[ "$status" == "4" ]] || return 1

  python3 - "$result" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["verification_report"]
capability = report["capability_assessment"]["future_capability"]
assert capability["status"] == "unknown"
assert capability["reason"]
assert capability["evidence"] == []
item = report["targets"]["cli_main"]["items"][0]
assert item["status"] == "not_verified"
assert item["error_category"] == "capability_unavailable"
assert report["handoffs"] == []
PY
}

check_capability_assessment_unavailable_mcp_runtime_blocks_probe() {
  local repo="$TEMP_DIR/capability-mcp-unavailable-repo"
  local fake_bin="$TEMP_DIR/capability-mcp-unavailable-bin"
  local marker="$TEMP_DIR/capability-mcp-unavailable-started"
  local result="$TEMP_DIR/capability-mcp-unavailable-result.json"
  local runtime_path
  local path_without_runtime
  local status
  mkdir -p "$repo" "$fake_bin"
  write_audit_contract "$repo/contract.md" mcp-initialize
  python3 - "$repo/contract.md" <<'PY'
import sys
from pathlib import Path

import yaml

path = Path(sys.argv[1])
contract = yaml.safe_load(path.read_text(encoding="utf-8").split("\n---", 1)[0][4:])
contract["verification"]["targets"]["cli_main"]["items"][0][
    "required_capabilities"
] = ["mcp_runtime_probe"]
path.write_text(
    "---\n" + yaml.safe_dump(contract, sort_keys=False) + "---\n# body\n",
    encoding="utf-8",
)
PY
  cat >"$fake_bin/agent-setup-mcp-stdio-readonly" <<SH
#!/bin/sh
touch "$marker"
while IFS= read -r request; do
  printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{}}'
done
SH
  chmod +x "$fake_bin/agent-setup-mcp-stdio-readonly"

  runtime_path="$(command -v agent-setup-mcp-stdio-readonly || true)"
  path_without_runtime="$(python3 - "$PATH" "$runtime_path" <<'PY'
import os
from pathlib import Path
import sys

path_value, runtime_path = sys.argv[1:]
runtime_parent = Path(runtime_path).resolve().parent if runtime_path else None
entries = []
for entry in path_value.split(os.pathsep):
    resolved = Path(entry or ".").resolve()
    if runtime_parent is None or resolved != runtime_parent:
        entries.append(entry)
print(os.pathsep.join(entries))
PY
)"

  if AGENT_SETUP_MCP_FIXTURE="$fake_bin/agent-setup-mcp-stdio-readonly" \
    PATH="$TEMP_DIR/no-mcp-runtime:$path_without_runtime" \
    bash "$SCRIPT_DIR/verify-setup.sh" \
    --contract contract.md \
    "$repo" >"$result"; then
    return 1
  else
    status=$?
  fi
  [[ "$status" == "4" ]] || return 1
  [[ ! -e "$marker" ]] || return 1

  python3 - "$result" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["verification_report"]
capability = report["capability_assessment"]["mcp_runtime_probe"]
assert capability["status"] == "unavailable"
assert capability["reason"]
assert capability["evidence"]
item = report["targets"]["cli_main"]["items"][0]
assert item["status"] == "not_verified"
assert item["error_category"] == "capability_unavailable"
assert "handoff_id" not in item
assert report["handoffs"] == []
PY
}

check_capability_assessment_available_mcp_runtime_separates_failure() {
  local repo="$TEMP_DIR/capability-mcp-failure-repo"
  local fake_bin="$TEMP_DIR/capability-mcp-failure-bin"
  local result="$TEMP_DIR/capability-mcp-failure-result.json"
  local status
  mkdir -p "$repo" "$fake_bin"
  write_audit_contract "$repo/contract.md" mcp-initialize
  python3 - "$repo/contract.md" <<'PY'
import sys
from pathlib import Path

import yaml

path = Path(sys.argv[1])
contract = yaml.safe_load(path.read_text(encoding="utf-8").split("\n---", 1)[0][4:])
contract["verification"]["targets"]["cli_main"]["items"][0][
    "required_capabilities"
] = ["mcp_runtime_probe"]
path.write_text(
    "---\n" + yaml.safe_dump(contract, sort_keys=False) + "---\n# body\n",
    encoding="utf-8",
)
PY
  cat >"$fake_bin/agent-setup-mcp-stdio-readonly" <<'SH'
#!/bin/sh
while IFS= read -r request; do
  printf '%s\n' 'not-json-rpc'
done
SH
  chmod +x "$fake_bin/agent-setup-mcp-stdio-readonly"

  if PATH="$fake_bin:$PATH" \
    AGENT_SETUP_MCP_FIXTURE="$fake_bin/agent-setup-mcp-stdio-readonly" \
    bash "$SCRIPT_DIR/verify-setup.sh" \
    --contract contract.md \
    "$repo" >"$result"; then
    return 1
  else
    status=$?
  fi
  [[ "$status" == "4" ]] || return 1

  python3 - "$result" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["verification_report"]
capability = report["capability_assessment"]["mcp_runtime_probe"]
assert capability["status"] == "available"
assert capability["reason"]
assert capability["evidence"]
item = report["targets"]["cli_main"]["items"][0]
assert item["status"] == "not_verified"
assert item["error_category"] == "runtime_failure"
PY
}

check_capability_assessment_reuses_policy_classifier_for_mcp_runtime() {
  local repo="$TEMP_DIR/capability-mcp-classifier-repo"
  local fake_bin="$TEMP_DIR/capability-mcp-classifier-bin"
  local result="$TEMP_DIR/capability-mcp-classifier-result.json"
  local status
  mkdir -p "$repo" "$fake_bin"
  write_audit_contract "$repo/contract.md" mcp-initialize
  python3 - "$repo/contract.md" <<'PY'
import sys
from pathlib import Path

import yaml

path = Path(sys.argv[1])
contract = yaml.safe_load(path.read_text(encoding="utf-8").split("\n---", 1)[0][4:])
target = contract["setup_target"]["cli_main"]
target["runtime"]["command"] = ["node", "--version"]
contract["verification"]["targets"]["cli_main"]["items"][0][
    "required_capabilities"
] = ["mcp_runtime_probe"]
path.write_text(
    "---\n" + yaml.safe_dump(contract, sort_keys=False) + "---\n# body\n",
    encoding="utf-8",
)
PY
  cat >"$fake_bin/node" <<'SH'
#!/bin/sh
exit 0
SH
  chmod +x "$fake_bin/node"

  if PATH="$fake_bin:$PATH" bash "$SCRIPT_DIR/verify-setup.sh" \
    --contract contract.md \
    "$repo" >"$result"; then
    return 1
  else
    status=$?
  fi
  [[ "$status" == "4" ]] || return 1

  python3 - "$result" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["verification_report"]
capability = report["capability_assessment"]["mcp_runtime_probe"]
assert capability["status"] == "available"
assert "classification: read_only (declaration_matches=True)" in capability["evidence"]
item = report["targets"]["cli_main"]["items"][0]
assert item["status"] == "not_verified"
assert item["error_category"] == "safety_blocked"
PY
}

check_verifier_does_not_duplicate_mcp_runtime_registry() {
  ! grep -q 'agent-setup-mcp-stdio-readonly' "$SCRIPT_DIR/verify-setup.sh"
}

check_capability_assessment_skill_handoff_boundary_keeps_capability_available() {
  local repo="$TEMP_DIR/capability-skill-handoff-repo"
  local result="$TEMP_DIR/capability-skill-handoff-result.json"
  local status
  mkdir -p "$repo/src"
  write_dry_run_contract "$repo/contract.md"
  python3 - "$repo/contract.md" <<'PY'
import sys
from pathlib import Path

import yaml

path = Path(sys.argv[1])
contract = yaml.safe_load(path.read_text(encoding="utf-8").split("\n---", 1)[0][4:])
skill_items = contract["verification"]["targets"]["skill_main"]["items"]
skill_items[0]["required_capabilities"] = ["agent_discovery_probe"]
skill_items[0]["handoff_id"] = "skill-discovery-review"
skill_items.append(
    {
        "id": "skill.activation",
        "phase": "activation",
        "target_type": "skill",
        "required_for_e2e": True,
        "blocked_by": [],
        "required_capabilities": ["representative_activation_probe"],
        "handoff_id": "skill-activation-review",
        "probe": {
            "kind": "agent_action",
            "action": "activation",
            "adapter": {
                "kind": "command",
                "argv": ["node", "--version"],
                "stdin": "empty",
                "safety": "read_only",
            },
        },
    }
)
contract["handoffs"] = {
    "skill-discovery-review": {
        "actor": "user",
        "action": "Review Skill discovery.",
        "prerequisites": [],
        "expected_outcome": "The Skill is discoverable.",
        "required_evidence": [{"type": "command_output", "summary": "discovery"}],
    },
    "skill-activation-review": {
        "actor": "user",
        "action": "Review Skill activation.",
        "prerequisites": [],
        "expected_outcome": "The Skill is activated.",
        "required_evidence": [{"type": "command_output", "summary": "activation"}],
    },
}
path.write_text(
    "---\n" + yaml.safe_dump(contract, sort_keys=False) + "---\n# body\n",
    encoding="utf-8",
)
PY

  if bash "$SCRIPT_DIR/verify-setup.sh" \
    --contract contract.md \
    "$repo" >"$result"; then
    return 1
  else
    status=$?
  fi
  [[ "$status" == "4" ]] || return 1

  python3 - "$result" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["verification_report"]
assessment = report["capability_assessment"]
assert assessment["agent_discovery_probe"]["status"] == "available"
assert assessment["representative_activation_probe"]["status"] == "available"
items = {
    item["id"]: item for item in report["targets"]["skill_main"]["items"]
}
for item_id, handoff_id in (
    ("skill.adapter", "skill-discovery-review"),
    ("skill.activation", "skill-activation-review"),
):
    assert items[item_id]["status"] == "not_verified"
    assert items[item_id]["error_category"] == "safety_blocked"
    assert items[item_id]["handoff_id"] == handoff_id
handoffs = {handoff["handoff_id"] for handoff in report["handoffs"]}
assert handoffs == {"skill-discovery-review", "skill-activation-review"}
PY
}

check_verification_report_records_runtime_failure() {
  local repo="$TEMP_DIR/report-runtime-failure-repo"
  local fake_bin="$TEMP_DIR/report-runtime-failure-bin"
  local report="$TEMP_DIR/report-runtime-failure.md"
  local result="$TEMP_DIR/report-runtime-failure.json"
  local status
  mkdir -p "$repo" "$fake_bin"
  write_audit_contract "$repo/contract.md" readonly-node
  cat >"$fake_bin/node" <<'SH'
#!/bin/sh
exit 17
SH
  chmod +x "$fake_bin/node"

  if PATH="$fake_bin:$PATH" bash "$SCRIPT_DIR/verify-setup.sh" \
    --contract contract.md \
    --report "$report" \
    "$repo" >"$result"; then
    return 1
  else
    status=$?
  fi
  [[ "$status" == "4" ]] || return 1

  python3 - "$result" "$report" <<'PY'
import json
import sys
from pathlib import Path

stdout = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
report = stdout["verification_report"]
item = report["targets"]["cli_main"]["items"][0]
assert item["status"] == "not_verified"
assert item["error_category"] == "runtime_failure"
assert report["targets"]["cli_main"]["e2e_status"] == "not_verified"
assert report["overall_status"] == "not_verified"
assert "overall_status: not_verified" in Path(sys.argv[2]).read_text(encoding="utf-8")
PY
}

check_verification_report_scopes_confirmed_audit_findings() {
  local repo="$TEMP_DIR/report-confirmed-isolation-repo"
  local report="$TEMP_DIR/report-confirmed-isolation.md"
  local result="$TEMP_DIR/report-confirmed-isolation.json"
  local status
  mkdir -p "$repo"
  write_topology_fixture "$repo"
  set_report_contract_probe_commands "$repo/contract.md"

  if bash "$SCRIPT_DIR/verify-setup.sh" \
    --contract contract.md \
    --report "$report" \
    "$repo" >"$result"; then
    return 1
  else
    status=$?
  fi
  [[ "$status" == "4" ]] || return 1

  python3 - "$result" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["verification_report"]
cli = report["targets"]["cli_main"]
other = report["targets"]["other_valid"]
assert cli["e2e_status"] == "not_verified"
assert all(
    item["status"] == "not_verified"
    and item["error_category"] == "audit_blocked"
    for item in cli["items"]
)
assert other["e2e_status"] == "verified"
assert all(item["status"] == "verified" for item in other["items"])
findings = report["audit"]["discrepancies"]
assert any(
    finding["finding_state"] == "confirmed"
    and finding["affected_target_ids"] == ["cli_main"]
    for finding in findings
)
assert report["overall_status"] == "not_verified"
PY
}

check_verification_report_keeps_unresolved_findings_target_scoped() {
  local repo="$TEMP_DIR/report-unresolved-isolation-repo"
  local report="$TEMP_DIR/report-unresolved-isolation.md"
  local result="$TEMP_DIR/report-unresolved-isolation.json"
  local status
  mkdir -p "$repo"
  write_topology_fixture "$repo"
  printf '%s\n' 'server:' '  port: 3000' >"$repo/src/config/generated.yaml"
  set_report_contract_probe_commands "$repo/contract.md"

  if bash "$SCRIPT_DIR/verify-setup.sh" \
    --contract contract.md \
    --report "$report" \
    "$repo" >"$result"; then
    return 1
  else
    status=$?
  fi
  [[ "$status" == "4" ]] || return 1

  python3 - "$result" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["verification_report"]
cli = report["targets"]["cli_main"]
other = report["targets"]["other_valid"]
assert all(item["status"] == "verified" for item in cli["items"])
assert cli["e2e_status"] == "not_verified"
assert other["e2e_status"] == "verified"
assert all(item["status"] == "verified" for item in other["items"])
assert any(
    finding["finding_state"] == "unresolved"
    and finding["affected_target_ids"] == ["cli_main"]
    for finding in report["audit"]["discrepancies"]
)
assert report["overall_status"] == "verified"
PY
}

check_verification_report_blocks_schema_errors() {
  local repo="$TEMP_DIR/report-schema-error-repo"
  local report="$TEMP_DIR/report-schema-error.md"
  local result="$TEMP_DIR/report-schema-error.json"
  local dry_report="$TEMP_DIR/report-schema-error-dry.md"
  local dry_result="$TEMP_DIR/report-schema-error-dry.json"
  local status
  local dry_status
  mkdir -p "$repo"
  write_audit_contract "$repo/contract.md" invalid-safety

  if bash "$SCRIPT_DIR/verify-setup.sh" \
    --contract contract.md \
    --report "$report" \
    "$repo" >"$result"; then
    return 1
  else
    status=$?
  fi
  [[ "$status" == "4" ]] || return 1

  python3 - "$result" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["verification_report"]
assert report["audit"]["schema_errors"]
item = report["targets"]["cli_main"]["items"][0]
assert item["status"] == "not_verified"
assert item["error_category"] == "audit_blocked"
assert report["targets"]["cli_main"]["e2e_status"] == "not_verified"
assert report["overall_status"] == "not_verified"
PY

  if bash "$SCRIPT_DIR/verify-setup.sh" \
    --dry-run \
    --contract contract.md \
    --report "$dry_report" \
    "$repo" >"$dry_result"; then
    return 1
  else
    dry_status=$?
  fi
  [[ "$dry_status" == "4" ]] || return 1
  python3 - "$dry_result" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["verification_report"]
assert report["audit"]["schema_errors"]
assert report["overall_status"] == "not_verified"
PY
}

check_verification_report_handles_blocked_by_cycles() {
  local repo="$TEMP_DIR/report-cycle-repo"
  local report="$TEMP_DIR/report-cycle.md"
  local result="$TEMP_DIR/report-cycle.json"
  local status
  mkdir -p "$repo"
  write_audit_contract "$repo/contract.md" cycle

  if bash "$SCRIPT_DIR/verify-setup.sh" \
    --contract contract.md \
    --report "$report" \
    "$repo" >"$result"; then
    return 1
  else
    status=$?
  fi
  [[ "$status" == "4" ]] || return 1

  python3 - "$result" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["verification_report"]
errors = report["audit"]["schema_errors"]
assert any(error["code"] == "blocked_by_cycle" for error in errors)
target = report["targets"]["cli_main"]
assert target["audit_blocked"] is True
assert [item["id"] for item in target["items"]] == ["cli.install", "cli.second"]
assert all(item["status"] == "not_verified" for item in target["items"])
assert all(item["error_category"] == "audit_blocked" for item in target["items"])
assert report["overall_status"] == "not_verified"
PY
}

check_verification_rejects_malformed_structure_with_audit_status() {
  local shape mode repo report result status

  for shape in verification targets; do
    for mode in normal dry-run; do
      repo="$TEMP_DIR/malformed-${shape}-${mode}-repo"
      report="$TEMP_DIR/malformed-${shape}-${mode}-report.md"
      result="$TEMP_DIR/malformed-${shape}-${mode}-result.json"
      mkdir -p "$repo"
      write_audit_contract "$repo/contract.md"

      python3 - "$repo/contract.md" "$shape" <<'PY'
import sys
from pathlib import Path

import yaml

path = Path(sys.argv[1])
shape = sys.argv[2]
contract = yaml.safe_load(path.read_text(encoding="utf-8").split("\n---", 1)[0][4:])
if shape == "verification":
    contract["verification"] = []
else:
    contract["verification"]["targets"] = []
path.write_text(
    "---\n" + yaml.safe_dump(contract, sort_keys=False) + "---\n# body\n",
    encoding="utf-8",
)
PY

      local -a args=(--contract contract.md --report "$report" "$repo")
      if [[ "$mode" == "dry-run" ]]; then
        args=(--dry-run "${args[@]}")
      fi
      if bash "$SCRIPT_DIR/verify-setup.sh" "${args[@]}" >"$result"; then
        return 1
      else
        status=$?
      fi
      [[ "$status" == "4" ]] || return 1

      python3 - "$result" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["verification_report"]
assert report["audit"]["schema_errors"]
assert report["overall_status"] == "not_verified"
PY
    done
  done
}

check_verification_report_marks_no_required_items_not_applicable() {
  local repo="$TEMP_DIR/report-not-applicable-repo"
  local report="$TEMP_DIR/report-not-applicable.md"
  local result="$TEMP_DIR/report-not-applicable.json"
  mkdir -p "$repo"
  write_audit_contract "$repo/contract.md" readonly-node
  python3 - "$repo/contract.md" <<'PY'
import sys
from pathlib import Path

import yaml

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
contract = yaml.safe_load(text.split("\n---", 1)[0][4:])
for verification in contract["verification"]["targets"].values():
    for item in verification["items"]:
        item["required_for_e2e"] = False
path.write_text(
    "---\n" + yaml.safe_dump(contract, sort_keys=False) + "---\n# body\n",
    encoding="utf-8",
)
PY

  bash "$SCRIPT_DIR/verify-setup.sh" \
    --contract contract.md \
    --report "$report" \
    "$repo" >"$result"

  python3 - "$result" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["verification_report"]
assert report["overall_status"] == "not_applicable"
assert report["targets"]["cli_main"]["e2e_status"] == "not_applicable"
PY
}

check_cli_grammar_rejects_missing_and_extra_arguments() {
  local repo="$TEMP_DIR/cli-grammar-repo"
  mkdir -p "$repo"

  for args in \
    "--dry-run" \
    "--contract" \
    "--report" \
    "--unknown-option $repo" \
    "--dry-run $repo extra" \
    "$repo --dry-run"; do
    read -r -a argv <<<"$args"
    if bash "$SCRIPT_DIR/verify-setup.sh" "${argv[@]}" >/dev/null 2>/dev/null; then
      return 1
    else
      local status=$?
    fi
    [[ "$status" == 2 ]] || return 1
  done

  if bash "$SCRIPT_DIR/verify-setup.sh" \
    --report "" \
    "$repo" >/dev/null 2>/dev/null; then
    return 1
  else
    status=$?
  fi
  [[ "$status" == 2 ]] || return 1
}

check_legacy_path_does_not_require_pyyaml() {
  local simple_repo="$TEMP_DIR/simple-without-pyyaml-repo"
  local enhanced_repo="$TEMP_DIR/enhanced-without-pyyaml-repo"
  local fake_bin="$TEMP_DIR/missing-pyyaml-bin"
  local pip_called="$TEMP_DIR/missing-pyyaml-pip-called"
  local real_python3
  local simple_result="$TEMP_DIR/simple-without-pyyaml-result.json"
  local simple_stderr="$TEMP_DIR/simple-without-pyyaml.stderr"
  local enhanced_stderr="$TEMP_DIR/enhanced-without-pyyaml.stderr"
  mkdir -p "$simple_repo" "$enhanced_repo/src" "$fake_bin"
  real_python3="$(command -v python3)"

  cat >"$simple_repo/package.json" <<'JSON'
{
  "scripts": {
    "test": "node --test"
  }
}
JSON
  write_dry_run_contract "$enhanced_repo/contract.md"

  cat >"$fake_bin/python3" <<'PYTHON'
#!/bin/sh
if [ "${1:-}" = "-c" ]; then
  case "${2:-}" in
    *"import yaml"*) exit 1 ;;
  esac
fi
if [ "${1:-}" = "-m" ] && [ "${2:-}" = "pip" ]; then
  touch "${MISSING_PYYAML_PIP_CALLED:?}"
  exit 1
fi
exec "${REAL_PYTHON3:?}" "$@"
PYTHON
  chmod +x "$fake_bin/python3"

  REAL_PYTHON3="$real_python3" MISSING_PYYAML_PIP_CALLED="$pip_called" \
    PATH="$fake_bin:$PATH" bash "$SCRIPT_DIR/verify-setup.sh" "$simple_repo" \
    >"$simple_result" 2>"$simple_stderr"
  python3 - "$simple_result" "$simple_stderr" <<'PY'
import json
from pathlib import Path
import sys

plan = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
assert any(entry["command"] == "npm test" for entry in plan["commands"])
stderr = Path(sys.argv[2]).read_text(encoding="utf-8")
assert "dependency_unavailable" not in stderr
assert "PyYAML" not in stderr
PY

  if REAL_PYTHON3="$real_python3" MISSING_PYYAML_PIP_CALLED="$pip_called" \
    PATH="$fake_bin:$PATH" bash "$SCRIPT_DIR/verify-setup.sh" \
    --dry-run \
    --contract contract.md \
    --report "$TEMP_DIR/enhanced-without-pyyaml-report.md" \
    "$enhanced_repo" >/dev/null 2>"$enhanced_stderr"; then
    return 1
  else
    local status=$?
  fi
  [[ "$status" == 3 ]] || return 1
  grep -q 'dependency_unavailable' "$enhanced_stderr" || return 1
  [[ ! -e "$pip_called" ]] || return 1
  [[ ! -e "$enhanced_repo/.agent-setup" ]] || return 1
}

check_legacy_path_honors_report() {
  local mode repo report result

  for mode in normal dry-run; do
    repo="$TEMP_DIR/legacy-report-${mode}-repo"
    report="$TEMP_DIR/legacy-report-${mode}.md"
    result="$TEMP_DIR/legacy-report-${mode}.json"
    mkdir -p "$repo"
    cat >"$repo/package.json" <<'JSON'
{
  "scripts": {
    "test": "node --test"
  }
}
JSON

    if [[ "$mode" == "dry-run" ]]; then
      bash "$SCRIPT_DIR/verify-setup.sh" \
        --dry-run \
        --report "$report" \
        "$repo" >"$result"
    else
      bash "$SCRIPT_DIR/verify-setup.sh" \
        --report "$report" \
        "$repo" >"$result"
    fi

    [[ -f "$report" ]] || return 1
    python3 - "$report" <<'PY'
import sys
from pathlib import Path

markdown = Path(sys.argv[1]).read_text(encoding="utf-8")
assert markdown.startswith("# Verification Report\n")
assert "overall_status: not_applicable" in markdown
assert '"commands"' in markdown
PY
  done
}

check_documentation_enhanced_probe_boundary() {
  grep -qF -- '--contract <repo-relative-path>' "$SKILL_DIR/SKILL.md" || return 1
  grep -qF -- '--target <target-id>' "$SKILL_DIR/SKILL.md" || return 1
  grep -qF -- '--item <verification-item-id>' "$SKILL_DIR/SKILL.md" || return 1
  grep -qF -- '--evidence-dir <external-temp-dir>' "$SKILL_DIR/SKILL.md" || return 1
  grep -qF -- 'requirements.txt' "$SKILL_DIR/SKILL.md" || return 1
  grep -qF -- 'temporary_fixture' "$SKILL_DIR/SKILL.md" || return 1
  grep -qF -- 'safety_blocked' "$SKILL_DIR/SKILL.md" || return 1
}

check_documentation_capability_references() {
  python3 - "$SKILL_DIR/references/setup-capability-matrix.md" \
    "$SKILL_DIR/references/agent-capability-matrix.md" \
    "$SKILL_DIR/references/verification-patterns.md" <<'PY'
from pathlib import Path
import sys

setup, generic, verification = [Path(path).read_text(encoding="utf-8") for path in sys.argv[1:]]
for phrase in (
    "mcp_runtime_probe", "agent_discovery_probe", "representative_activation_probe",
    "available", "unavailable", "unknown", "generic_prerequisites.candidates",
    "prerequisites do not derive availability", "target-operation separation",
    "declared safety", "effective safety", "unknown -> not_verified", "safety_blocked",
    "dry-run", "report", "handoff", "P1", "Target default profiles",
    "safety: read_only", "Mutating or unknown representative calls",
    "Skill classifier can return", "not_executed",
):
    assert phrase in setup or phrase in verification, phrase
for capability in (
    "repository_inspection", "file_operations", "command_execution",
    "structured_ask", "secret_input", "web_fetch",
):
    assert capability in generic, capability
assert "setup-specific" not in generic.lower()
PY
}

check_documentation_probe_safety_policy_v1_authority() {
  grep -q 'Probe Safety Policy v1' "$SKILL_DIR/SKILL.md" || return 1
  grep -q 'run-target-probes.sh' "$SKILL_DIR/SKILL.md" || return 1
}

check_documentation_classify_only_reuse() {
  grep -qF -- '--classify-only' "$SKILL_DIR/SKILL.md" || return 1
  grep -q 'run-target-probes.sh' "$SKILL_DIR/SKILL.md" || return 1
}

check_documentation_p1_skill_handoff() {
  grep -q 'agent_action' "$SKILL_DIR/SKILL.md" || return 1
  grep -q 'discovery.*activation\|activation.*discovery' "$SKILL_DIR/SKILL.md" || return 1
}

check_documentation_p1_temporary_fixture_handoff() {
  grep -q 'temporary_fixture' "$SKILL_DIR/SKILL.md" || return 1
  grep -q 'safety_blocked' "$SKILL_DIR/SKILL.md" || return 1
}

check_documentation_safety_declaration_not_execution_authority() {
  grep -q 'Safety declarations never authorize execution' "$SKILL_DIR/references/setup-contract-schema.md" || return 1
}

check_documentation_simple_path_preserved() {
  grep -qE 'simple[- ]repository' "$SKILL_DIR/SKILL.md" || return 1
  grep -q 'analyze-repo.sh' "$SKILL_DIR/SKILL.md" || return 1
  grep -q 'verify-setup.sh' "$SKILL_DIR/SKILL.md" || return 1
}

run_test "eval manifest parses" check_eval_manifest
run_test "analysis detects nested scripts and lockfiles" check_analysis
run_test "analysis uses package runner for npm tests" check_analysis_uses_package_runner_for_tests
run_test "analysis reads UTF-8 package metadata" check_analysis_reads_utf8_package_json
run_test "analysis ignores Makefile variable assignments" check_analysis_ignores_makefile_variable_assignments
run_test "analysis ignores recipe lines with colons" check_analysis_ignores_recipe_lines_with_colons
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
run_test "verification reanalyzes changed non-node inputs" check_verification_reanalyzes_changed_non_node_inputs
run_test "verification reanalyzes changed env templates" check_verification_reanalyzes_changed_env_templates
run_test "verification reanalyzes without fingerprint" check_verification_reanalyzes_without_fingerprint
run_test "analysis detects multi-target test rules" check_analysis_detects_multi_target_test_rule
run_test "analysis detects multi-target rules in any order" check_analysis_detects_multi_target_rules_in_any_order
run_test "analysis detects test targets with spaced colons" check_analysis_detects_test_target_with_space_before_colon
run_test "verification includes space-indented targets" check_verification_includes_space_indented_targets
run_test "analysis reports invalid repository paths" check_invalid_repo_path
run_test "verification retries after analysis failure without stale cache" check_analysis_failure_does_not_poison_cache
run_test "Setup Contract requires runtime and process runtime fields" check_setup_contract_required_runtime_fields
run_test "Setup Contract v1 MCP fixture validates" check_setup_contract_fixture
run_test "audit gives explicit contract priority" check_audit_explicit_contract_has_priority
run_test "audit rejects conflicting repository markers" check_audit_conflicting_repository_markers_are_ambiguous
run_test "audit rejects ambiguous marker scan" check_audit_marker_scan_candidates_are_ambiguous
run_test "audit reports deterministic not-found discovery" check_audit_not_found_is_deterministic
run_test "audit skips unreadable marker scan candidates" check_audit_skips_unreadable_marker_scan_candidates
run_test "audit ignores unreadable marker documents" check_audit_ignores_unreadable_marker_documents
run_test "audit reports unreadable selected contracts" check_audit_reports_unreadable_selected_contract
run_test "audit rejects escaping declared paths" check_audit_rejects_escaping_declared_path
run_test "audit rejects malformed explicit frontmatter" check_audit_rejects_malformed_explicit_frontmatter
run_test "audit rejects undefined handoffs" check_audit_rejects_undefined_handoff
run_test "audit rejects blocked-by cycles" check_audit_rejects_blocked_by_cycle
run_test "audit rejects empty argv lists" check_audit_rejects_empty_argv_lists
run_test "audit rejects invalid repository source paths" check_audit_rejects_invalid_repository_source_paths
run_test "audit validates all safety enums without execution" check_audit_validates_all_safety_enums_without_execution
run_test "audit validates capability IDs without matrix lookup" check_audit_validates_capability_ids_without_matrix_lookup
run_test "audit rejects unknown layer kinds" check_audit_rejects_unknown_layer_kind
run_test "audit writes both formats outside target" check_audit_writes_both_formats_only_outside_target
run_test "audit rejects target-internal output directories" check_audit_rejects_target_internal_output_dir
run_test "audit reports missing PyYAML without installing" check_audit_reports_dependency_unavailable_without_installing
run_test "audit reports static topology discrepancies" check_audit_reports_static_topology
run_test "analysis emits evidence-only complexity triggers" check_analysis_emits_complexity_triggers
run_test "documentation asserts exact Contract marker syntax" check_documentation_contract_marker_syntax
run_test "documentation asserts audit grammar" check_documentation_audit_grammar
run_test "documentation asserts mutation-surface investigation" check_documentation_mutation_surface_investigation
run_test "documentation asserts process runtime.safety shape" check_documentation_process_runtime_safety_shape
run_test "documentation asserts Probe Safety Policy v1 authority" check_documentation_probe_safety_policy_v1_authority
run_test "documentation asserts --classify-only reuse" check_documentation_classify_only_reuse
run_test "documentation asserts P1 Skill discovery/activation handoff" check_documentation_p1_skill_handoff
run_test "documentation asserts P1 temporary_fixture handoff" check_documentation_p1_temporary_fixture_handoff
run_test "documentation asserts safety declaration is not execution authority" check_documentation_safety_declaration_not_execution_authority
run_test "documentation asserts simple-path preservation" check_documentation_simple_path_preserved
run_test "audit assigns unmatched layer paths to unassigned" check_audit_unmatched_layer_path_is_unassigned
run_test "documentation rejects unrelated runtime.safety enum text" check_documentation_process_runtime_safety_shape_rejects_unrelated_enum
run_test "target probe classifier uses the fixed safety registry" check_target_probe_classifier
run_test "target probe classifier requires exact argv matches" check_target_probe_classifier_requires_exact_argv
run_test "target probe executes supported read-only commands" check_target_probe_readonly_command
run_test "target probe enforces command safety boundaries" check_target_probe_command_safety_boundaries
run_test "target probe enforces target type boundaries" check_target_probe_enforces_target_type_boundaries
run_test "target probe preserves normal and dry-run classifier parity" check_target_probe_normal_dry_run_classifier_parity
run_test "target probe enforces MCP runtime safety variants" check_target_probe_mcp_runtime_safety_variants
run_test "target probe blocks unsupported MCP runtime modes" check_target_probe_blocks_unsupported_mcp_runtime_modes
run_test "target probe executes the supported MCP initialize request" check_target_probe_mcp_initialize
run_test "target probe validates the caller-provided MCP fixture path" check_target_probe_validates_mcp_fixture_path
run_test "target probe executes MCP discovery and safe representative calls" check_target_probe_mcp_protocol_operations
run_test "target probe reports MCP initialize errors as runtime failures" check_target_probe_rejects_mcp_initialize_error
run_test "target probe rejects malformed MCP responses" check_target_probe_rejects_malformed_mcp_response
run_test "target probe blocks temporary fixtures before process start" check_target_probe_blocks_temporary_fixture
run_test "verification preserves the temporary fixture handoff boundary" check_verification_temporary_fixture_handoff_boundary
run_test "non-probe Plugin items use only their defined handoff" check_non_probe_plugin_uses_only_defined_handoff
run_test "target probe rejects internal evidence dirs without mutation" check_target_probe_rejects_internal_evidence_dir_without_mutation
run_test "verification exposes the enhanced probe workflow" check_verification_exposes_enhanced_workflow
run_test "dry-run preserves the target and reports snapshots" check_dry_run_preserves_target_and_reports_snapshots
run_test "dry-run classifies safety and blocks process starts" check_dry_run_classifies_policy_and_blocks_processes
run_test "dry-run blocks confirmed audit targets" check_dry_run_blocks_confirmed_audit_targets
run_test "dry-run Skill handoffs are reference-only" check_dry_run_skill_handoff_is_reference_only
run_test "normal Skill safety rejection records defined handoff" check_normal_skill_safety_rejection_records_only_defined_handoff
run_test "Skill discovery and activation never start adapters" check_skill_discovery_and_activation_never_start_adapters
run_test "dry-run rejects target-internal reports" check_dry_run_rejects_target_internal_report
run_test "verification detects a Contract marker in README" check_verification_detects_readme_contract_marker
run_test "verification rejects ambiguous Contract markers" check_verification_rejects_ambiguous_contract_markers
run_test "dry-run rejects a symlinked temp root inside target" check_dry_run_rejects_symlinked_temp_root_inside_target
run_test "verification rejects malformed CLI grammar" check_cli_grammar_rejects_missing_and_extra_arguments
run_test "legacy path does not require PyYAML" check_legacy_path_does_not_require_pyyaml
run_test "legacy path honors --report" check_legacy_path_honors_report
run_test "verification report marks all required items verified" check_verification_report_all_required_items_verified
run_test "capability assessment blocks undefined capabilities separately" check_capability_assessment_unknown_capability_blocks_item
run_test "capability assessment blocks unavailable MCP runtimes" check_capability_assessment_unavailable_mcp_runtime_blocks_probe
run_test "capability assessment separates available MCP runtime failures" check_capability_assessment_available_mcp_runtime_separates_failure
run_test "capability assessment reuses the Policy v1 classifier" check_capability_assessment_reuses_policy_classifier_for_mcp_runtime
run_test "verification does not duplicate the MCP runtime registry" check_verifier_does_not_duplicate_mcp_runtime_registry
run_test "capability assessment preserves the Skill P1 handoff boundary" check_capability_assessment_skill_handoff_boundary_keeps_capability_available
run_test "verification report records runtime failures" check_verification_report_records_runtime_failure
run_test "verification report scopes confirmed audit findings" check_verification_report_scopes_confirmed_audit_findings
run_test "verification report scopes unresolved audit findings" check_verification_report_keeps_unresolved_findings_target_scoped
run_test "verification report blocks schema errors" check_verification_report_blocks_schema_errors
run_test "verification report handles blocked-by cycles" check_verification_report_handles_blocked_by_cycles
run_test "verification rejects malformed structures with audit status" check_verification_rejects_malformed_structure_with_audit_status
run_test "verification report derives not-applicable status" check_verification_report_marks_no_required_items_not_applicable
run_test "documentation defines the enhanced probe boundary" check_documentation_enhanced_probe_boundary
run_test "documentation publishes capability and verification references" check_documentation_capability_references

if (( failures > 0 )); then
  exit 1
fi

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
                        "required_capabilities": ["future_capability"],
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
elif variant == "unknown-layer-kind":
    contract["configuration_branches"][0]["layers"][0]["kind"] = "future_layer"
elif variant != "valid":
    raise ValueError(f"unknown fixture variant: {variant}")

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
run_test "audit rejects escaping declared paths" check_audit_rejects_escaping_declared_path
run_test "audit rejects malformed explicit frontmatter" check_audit_rejects_malformed_explicit_frontmatter
run_test "audit rejects undefined handoffs" check_audit_rejects_undefined_handoff
run_test "audit rejects blocked-by cycles" check_audit_rejects_blocked_by_cycle
run_test "audit validates all safety enums without execution" check_audit_validates_all_safety_enums_without_execution
run_test "audit validates capability IDs without matrix lookup" check_audit_validates_capability_ids_without_matrix_lookup
run_test "audit rejects unknown layer kinds" check_audit_rejects_unknown_layer_kind
run_test "audit writes both formats outside target" check_audit_writes_both_formats_only_outside_target
run_test "audit rejects target-internal output directories" check_audit_rejects_target_internal_output_dir
run_test "audit reports missing PyYAML without installing" check_audit_reports_dependency_unavailable_without_installing

if (( failures > 0 )); then
  exit 1
fi

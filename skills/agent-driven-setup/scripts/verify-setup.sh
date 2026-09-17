#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_PATH=""
DRY_RUN=false
CONTRACT_PATH=""
REPORT_PATH=""
TEMP_ROOT=""
ANALYZE_JSON=""
AUDIT_JSON=""
SELECTED_CONTRACT=""
ENHANCED_PATH=false
REPORT_ABS=""
INPUT_FINGERPRINT=""
ANALYZE_FINGERPRINT=""
CACHE_IS_CURRENT=false

usage_error() {
  printf '%s\n' '{"error":"usage","message":"'"$1"'"}' >&2
  exit 2
}

dependency_error() {
  {
    printf '%s\n' 'dependency_unavailable: PyYAML (>=6.0,<7) is unavailable.'
    printf '%s\n' 'Provision it outside the target repository, for example:'
    printf '%s\n' '  python3 -m pip install -r skills/agent-driven-setup/requirements.txt'
    printf '%s\n' 'Then rerun verify-setup.sh.'
  } >&2
  exit 3
}

cleanup() {
  local status=$?
  if [[ -n "$TEMP_ROOT" && -d "$TEMP_ROOT" ]]; then
    if ! rm -rf -- "$TEMP_ROOT"; then
      printf '%s\n' 'invariant_violation: temporary-storage cleanup failed' >&2
      status=1
    fi
  fi
  exit "$status"
}

trap cleanup EXIT

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      [[ -z "$REPO_PATH" ]] || usage_error "options must precede repository path"
      DRY_RUN=true
      shift
      ;;
    --contract)
      [[ -z "$REPO_PATH" ]] || usage_error "options must precede repository path"
      [[ $# -ge 2 ]] || usage_error "missing value for --contract"
      CONTRACT_PATH="$2"
      shift 2
      ;;
    --contract=*)
      [[ -z "$REPO_PATH" ]] || usage_error "options must precede repository path"
      CONTRACT_PATH="${1#*=}"
      [[ -n "$CONTRACT_PATH" ]] || usage_error "missing value for --contract"
      shift
      ;;
    --report)
      [[ -z "$REPO_PATH" ]] || usage_error "options must precede repository path"
      [[ $# -ge 2 ]] || usage_error "missing value for --report"
      REPORT_PATH="$2"
      shift 2
      ;;
    --report=*)
      [[ -z "$REPO_PATH" ]] || usage_error "options must precede repository path"
      REPORT_PATH="${1#*=}"
      [[ -n "$REPORT_PATH" ]] || usage_error "missing value for --report"
      shift
      ;;
    --)
      [[ -z "$REPO_PATH" ]] || usage_error "unexpected argument: --"
      shift
      while [[ $# -gt 0 ]]; do
        if [[ -z "$REPO_PATH" ]]; then
          REPO_PATH="$1"
        else
          usage_error "unexpected argument: $1"
        fi
        shift
      done
      break
      ;;
    -*)
      usage_error "unknown option: $1"
      ;;
    *)
      if [[ -z "$REPO_PATH" ]]; then
        REPO_PATH="$1"
      else
        usage_error "unexpected argument: $1"
      fi
      shift
      ;;
  esac
done

[[ -n "$REPO_PATH" ]] || usage_error "missing repository path"

if ! REPO_PATH="$(cd "$REPO_PATH" 2>/dev/null && pwd -P)"; then
  echo '{"error":"cannot enter repository path"}' >&2
  exit 1
fi

if [[ -n "$CONTRACT_PATH" ]]; then
  if ! python3 - "$CONTRACT_PATH" <<'PY'
from pathlib import PurePosixPath
import sys

value = sys.argv[1]
if not value or value.startswith("/") or "\\" in value:
    raise SystemExit(1)
parts = PurePosixPath(value).parts
if not parts or any(part in {"", ".", ".."} for part in parts):
    raise SystemExit(1)
PY
  then
    usage_error "--contract must be a normalized repository-relative path"
  fi
fi

if [[ -n "$REPORT_PATH" ]]; then
  if ! REPORT_ABS="$(python3 - "$REPO_PATH" "$REPORT_PATH" <<'PY'
from pathlib import Path
import sys

repo = Path(sys.argv[1]).resolve()
report = Path(sys.argv[2]).expanduser().resolve(strict=False)
if report == repo or repo in report.parents:
    raise SystemExit(1)
if report.exists() and report.is_dir():
    raise SystemExit(1)
print(report)
PY
)"; then
    usage_error "--report must point outside the target repository"
  fi
fi

detect_contract_indicator() {
  python3 - "$REPO_PATH" <<'PY'
import os
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
marker = re.compile(r"^<!-- agent-setup-contract: (\S+) -->$")
version = re.compile(
    r"^\s*(?:['\"])?setup_contract_schema_version(?:['\"])?\s*:\s*"
    r"(?:!!int\s+)?1\s*(?:#.*)?$",
    re.MULTILINE,
)


def has_marker(path):
    if not path.is_file():
        return False
    try:
        with path.open(encoding="utf-8") as stream:
            return any(marker.fullmatch(line.rstrip("\n").rstrip("\r")) for line in stream)
    except Exception:
        return False


for filename in ("AGENTS.md", "README.md"):
    if has_marker(root / filename):
        raise SystemExit(0)


def has_version_candidate(path):
    if not path.is_file():
        return False
    try:
        text = path.read_text(encoding="utf-8")
    except Exception:
        return False
    if not text.startswith("---\n"):
        return False
    end = text.find("\n---", 4)
    return end != -1 and version.search(text[4:end]) is not None


if has_version_candidate(root / "SETUP-CONTRACT.md"):
    raise SystemExit(0)

docs_root = root / "docs"
if docs_root.is_dir() and not docs_root.is_symlink():
    for dirpath, dirnames, filenames in os.walk(docs_root):
        dirpath = Path(dirpath)
        dirnames[:] = [
            name for name in dirnames if not (dirpath / name).is_symlink()
        ]
        for filename in filenames:
            path = dirpath / filename
            if filename.endswith(".md") and not path.is_symlink() and has_version_candidate(path):
                raise SystemExit(0)

raise SystemExit(1)
PY
}

if [[ -n "$CONTRACT_PATH" ]]; then
  ENHANCED_PATH=true
elif detect_contract_indicator; then
  ENHANCED_PATH=true
fi

ANALYZE_FINGERPRINT="$REPO_PATH/.agent-setup/analyze.inputs.sha256"
INPUT_FINGERPRINT="$({
  python3 - "$REPO_PATH" <<'PY'
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

print(digest.hexdigest())
PY
})"

if [[ -f "$REPO_PATH/.agent-setup/analyze.json" && -f "$ANALYZE_FINGERPRINT" ]]; then
  cached_fingerprint="$(<"$ANALYZE_FINGERPRINT")"
  [[ "$cached_fingerprint" == "$INPUT_FINGERPRINT" ]] && CACHE_IS_CURRENT=true
fi

ensure_temp_root() {
  if [[ -n "$TEMP_ROOT" ]]; then
    return
  fi

  local tmp_base="${TMPDIR:-/tmp}"
  if ! tmp_base="$(python3 - "$tmp_base" <<'PY'
from pathlib import Path
import sys

print(Path(sys.argv[1]).expanduser().resolve(strict=False))
PY
)"; then
    printf '%s\n' 'invariant_violation: temporary-storage path resolution failed' >&2
    exit 1
  fi
  if [[ "$tmp_base" == "$REPO_PATH" || "$tmp_base" == "$REPO_PATH"/* ]]; then
    printf '%s\n' 'invariant_violation: temporary storage is inside the target repository' >&2
    exit 1
  fi
  if ! TEMP_ROOT="$(mktemp -d "$tmp_base/agent-driven-setup.XXXXXX")"; then
    printf '%s\n' 'invariant_violation: temporary-storage creation failed' >&2
    exit 1
  fi
  if ! TEMP_ROOT="$(cd "$TEMP_ROOT" 2>/dev/null && pwd -P)"; then
    printf '%s\n' 'invariant_violation: temporary-storage path resolution failed' >&2
    exit 1
  fi
  if [[ "$TEMP_ROOT" == "$REPO_PATH" || "$TEMP_ROOT" == "$REPO_PATH"/* ]]; then
    printf '%s\n' 'invariant_violation: temporary storage is inside the target repository' >&2
    exit 1
  fi
}

preflight_pyyaml() {
  python3 -c 'import yaml' >/dev/null 2>&1 || dependency_error
}

analyze_external() {
  ensure_temp_root
  local output="$TEMP_ROOT/analyze.json"
  local temporary="$TEMP_ROOT/analyze.json.tmp"

  if [[ "$CACHE_IS_CURRENT" == true ]]; then
    cp -- "$REPO_PATH/.agent-setup/analyze.json" "$output"
  else
    echo "Running analyze-repo.sh first" >&2
    if bash "$SCRIPT_DIR/analyze-repo.sh" "$REPO_PATH" >"$temporary"; then
      mv -- "$temporary" "$output"
    else
      local status=$?
      rm -f -- "$temporary"
      return "$status"
    fi
  fi
  ANALYZE_JSON="$output"
}

write_target_cache() {
  local analyze_tmp
  local fingerprint_tmp
  mkdir -p "$REPO_PATH/.agent-setup"
  analyze_tmp="$(mktemp "$REPO_PATH/.agent-setup/analyze.json.XXXXXX")"
  fingerprint_tmp="$(mktemp "$REPO_PATH/.agent-setup/analyze.inputs.sha256.XXXXXX")"
  trap 'rm -f -- "$analyze_tmp" "$fingerprint_tmp"' RETURN
  cp -- "$ANALYZE_JSON" "$analyze_tmp"
  printf '%s\n' "$INPUT_FINGERPRINT" >"$fingerprint_tmp"
  mv -- "$analyze_tmp" "$REPO_PATH/.agent-setup/analyze.json"
  mv -- "$fingerprint_tmp" "$ANALYZE_FINGERPRINT"
  trap - RETURN
  ANALYZE_JSON="$REPO_PATH/.agent-setup/analyze.json"
}

has_complexity_triggers() {
  python3 - "$1" <<'PY'
import json
from pathlib import Path
import sys

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
raise SystemExit(0 if data.get("complexity_triggers") else 1)
PY
}

snapshot_target() {
  local output="$1"
  if ! python3 - "$REPO_PATH" "$output" <<'PY'
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

root = Path(sys.argv[1]).resolve()
output = Path(sys.argv[2])

def tree_digest():
    digest = hashlib.sha256()
    for path in sorted(root.rglob("*")):
        relative = path.relative_to(root)
        if relative.parts and relative.parts[0] == ".git":
            continue
        stat = path.lstat()
        digest.update(str(relative).encode("utf-8", "surrogateescape"))
        digest.update(b"\0")
        if path.is_symlink():
            digest.update(b"symlink\0")
            digest.update(os.readlink(path).encode("utf-8", "surrogateescape"))
        elif path.is_file():
            digest.update(b"file\0")
            with path.open("rb") as stream:
                while chunk := stream.read(1024 * 1024):
                    digest.update(chunk)
        elif path.is_dir():
            digest.update(b"directory\0")
        else:
            digest.update(b"other\0")
        digest.update(str(stat.st_mode).encode())
        digest.update(b"\n")
    return digest.hexdigest()

git_status = None
probe = subprocess.run(
    ["git", "-C", str(root), "rev-parse", "--is-inside-work-tree"],
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    check=False,
)
if probe.returncode == 0 and probe.stdout.strip() == "true":
    status = subprocess.run(
        ["git", "-C", str(root), "status", "--porcelain"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if status.returncode != 0:
        raise RuntimeError(status.stderr.strip() or "git status failed")
    git_status = status.stdout
elif probe.returncode != 128:
    raise RuntimeError(probe.stderr.strip() or "git repository snapshot failed")

snapshot = {
    "agent_setup_exists": os.path.lexists(root / ".agent-setup"),
    "git_status": git_status,
    "tree_sha256": tree_digest(),
}
output.write_text(json.dumps(snapshot, ensure_ascii=False, sort_keys=True) + "\n", encoding="utf-8")
PY
  then
    printf '%s\n' 'invariant_violation: target snapshot failed' >&2
    exit 1
  fi
}

emit_legacy_plan() {
  python3 - "$ANALYZE_JSON" "$REPO_PATH" <<'PY'
import json
import re
import shlex
import sys
from pathlib import Path

analyze_path = Path(sys.argv[1])
repo_path = Path(sys.argv[2])
data = json.loads(analyze_path.read_text(encoding="utf-8"))

def classify(cmd: str) -> dict:
    """Classify a repo-defined command by likely side-effect risk."""
    if not cmd:
        return None
    lower = cmd.lower()
    safe_prefixes = (
        "npm test", "yarn test", "pnpm test", "bun test",
        "cargo test", "go test", "pytest", "python -m pytest",
        "bundle exec rspec", "make test", "make check",
        "npm run lint", "yarn lint", "pnpm lint", "make lint",
        "cargo check", "go vet",
    )
    review_keywords = (
        "sudo", "deploy", "publish", "push", "release",
        "provision", "apply", "destroy", "terraform", "aws ",
        "gcloud", "az ", "kubectl", "docker push", "fly deploy",
        "npm publish", "pip upload", "twine upload",
    )
    dry_run_actions = {
        "make": ("flag", "--dry-run"),
        "terraform": ("command", "terraform plan"),
        "kubectl": ("flag", "--dry-run=client"),
        "npm publish": ("flag", "--dry-run"),
        "twine upload": ("flag", "--dry-run"),
    }

    category = "review"

    def starts_with_command(command: str, candidate: str) -> bool:
        if re.search(r"[;&|<>`$()\n\r]", command):
            return False
        try:
            command_argv = shlex.split(command, posix=True)
            candidate_argv = shlex.split(candidate, posix=True)
        except ValueError:
            return False
        return command_argv[:len(candidate_argv)] == candidate_argv

    for prefix in safe_prefixes:
        if starts_with_command(lower, prefix):
            category = "safe"
            break
    for keyword in review_keywords:
        if keyword in lower:
            category = "review"
            break

    dry_run_flag = None
    dry_run_command = None
    if category == "review":
        for candidate, (action_type, action) in sorted(
            dry_run_actions.items(), key=lambda item: len(item[0]), reverse=True
        ):
            if starts_with_command(lower, candidate):
                if action_type == "flag":
                    dry_run_flag = action
                else:
                    dry_run_command = action
                break

    result = {
        "command": cmd,
        "category": category,
        "dry_run_flag": dry_run_flag,
        "note": (
            "Likely local-only; can be executed directly."
            if category == "safe" else
            "May mutate external state; use dry-run if available, otherwise ask the user before running."
        ),
    }
    if dry_run_command:
        result["dry_run_command"] = dry_run_command
    return result

plan = {"commands": [], "notes": []}
for key, label in (("install_command", "install"), ("build_command", "build"),
                   ("test_command", "test"), ("lint_command", "lint")):
    entry = classify(data.get(key))
    if entry:
        entry["phase"] = label
        plan["commands"].append(entry)

makefile_path = repo_path / "Makefile"
if makefile_path.exists():
    targets = []
    seen_targets = set()
    assignment_pattern = re.compile(
        r"^(?:(?:export|override)\s+)*"
        r"[A-Za-z_][A-Za-z0-9_.-]*\s*(?::=|\?=|\+=|!=|=)"
    )
    for line in makefile_path.read_text(encoding="utf-8", errors="replace").splitlines():
        if assignment_pattern.match(line) or line.lstrip().startswith("#"):
            continue
        if ":" in line and not line.startswith("\t"):
            for target in line.split(":", 1)[0].split():
                if (
                    target and not target.startswith(".") and "%" not in target
                    and target not in seen_targets
                ):
                    seen_targets.add(target)
                    targets.append(target)
    if targets:
        plan["makefile_targets"] = targets

if data.get("env_template"):
    plan["notes"].append(
        "Repository has an env template; verify secrets are handled per the secret policy before running any integration test."
    )

complexity_triggers = data.get("complexity_triggers") or []
if complexity_triggers:
    plan["enhanced_workflow"] = {
        "trigger_ids": [trigger.get("id") for trigger in complexity_triggers],
        "audit_command": "audit-contract.sh",
        "probe_executor": "run-target-probes.sh",
        "classify_only_command": "run-target-probes.sh --classify-only",
        "temporary_fixture_policy": "safety_blocked",
        "note": (
            "Use the Setup Contract audit and run-target-probes.sh for supported probes; "
            "do not execute Contract-defined temporary fixtures automatically."
        ),
    }

json.dump(plan, sys.stdout, indent=2, ensure_ascii=False)
print()
PY
}

emit_simple_dry_run() {
  local plan_json="$TEMP_ROOT/plan.json"
  local result_json="$TEMP_ROOT/result.json"
  local before_snapshot="$TEMP_ROOT/before.json"
  local after_snapshot="$TEMP_ROOT/after.json"
  emit_legacy_plan >"$plan_json"
  snapshot_target "$after_snapshot"
  if ! python3 - "$plan_json" "$before_snapshot" "$after_snapshot" "$result_json" <<'PY'
import json
from pathlib import Path
import sys

plan_path, before_path, after_path, result_path = map(Path, sys.argv[1:])
plan = json.loads(plan_path.read_text(encoding="utf-8"))
before = json.loads(before_path.read_text(encoding="utf-8"))
after = json.loads(after_path.read_text(encoding="utf-8"))
if before != after:
    print("invariant_violation: dry-run changed the target repository", file=sys.stderr)
    raise SystemExit(1)
plan["dry_run"] = {
    "decision": "not_executed",
    "probes": [],
    "runtimes": [],
    "before_snapshot": before,
    "after_snapshot": after,
}
result_path.write_text(json.dumps(plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
  then
    printf '%s\n' 'invariant_violation: dry-run snapshot comparison failed' >&2
    exit 1
  fi
  write_report "$result_json"
  cat "$result_json"
}

write_report() {
  local plan_path="$1"
  [[ -n "$REPORT_ABS" ]] || return 0
  python3 - "$plan_path" "$REPORT_ABS" <<'PY'
import datetime
import json
from pathlib import Path
import sys

plan = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
report_path = Path(sys.argv[2])
generated_at = datetime.datetime.now(datetime.timezone.utc).isoformat().replace(
    "+00:00", "Z"
)
report_path.parent.mkdir(parents=True, exist_ok=True)
report_path.write_text(
    "# Verification Report\n\n"
    f"generated_at: {generated_at}\n"
    "overall_status: not_applicable\n\n"
    "## Legacy verification plan\n\n"
    "```json\n"
    + json.dumps(plan, ensure_ascii=False, indent=2)
    + "\n```\n",
    encoding="utf-8",
)
PY
}

emit_enhanced_dry_run() {
  local plan_json="$TEMP_ROOT/plan.json"
  local result_json="$TEMP_ROOT/result.json"
  local before_snapshot="$TEMP_ROOT/before.json"
  emit_legacy_plan >"$plan_json"
  if ! python3 - "$plan_json" "$before_snapshot" "$REPO_PATH" "$SELECTED_CONTRACT" "$SCRIPT_DIR/run-target-probes.sh" "$AUDIT_JSON" "$result_json" "$REPORT_ABS" <<'PY'
import datetime
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

import yaml

plan_path = Path(sys.argv[1])
before_path = Path(sys.argv[2])
repo = Path(sys.argv[3]).resolve()
contract_relative = sys.argv[4]
classifier = sys.argv[5]
audit_path = Path(sys.argv[6])
result_path = Path(sys.argv[7])
report_path = Path(sys.argv[8]) if sys.argv[8] else None
audit = json.loads(audit_path.read_text(encoding="utf-8"))
schema_errors = audit.get("schema_errors", [])
if not isinstance(schema_errors, list):
    schema_errors = []
    audit["schema_errors"] = schema_errors

confirmed_target_ids = set()
for target_id in audit.get("affected_target_ids", []):
    if isinstance(target_id, str):
        confirmed_target_ids.add(target_id)
for finding in audit.get("discrepancies", []):
    if not isinstance(finding, dict) or finding.get("finding_state") != "confirmed":
        continue
    for target_id in finding.get("affected_target_ids", []):
        if isinstance(target_id, str):
            confirmed_target_ids.add(target_id)

SAFETY_VALUES = {"read_only", "mutating", "unknown"}

def snapshot_target():
    digest = hashlib.sha256()
    for path in sorted(repo.rglob("*")):
        relative = path.relative_to(repo)
        if relative.parts and relative.parts[0] == ".git":
            continue
        stat = path.lstat()
        digest.update(str(relative).encode("utf-8", "surrogateescape"))
        digest.update(b"\0")
        if path.is_symlink():
            digest.update(b"symlink\0")
            digest.update(os.readlink(path).encode("utf-8", "surrogateescape"))
        elif path.is_file():
            digest.update(b"file\0")
            with path.open("rb") as stream:
                while chunk := stream.read(1024 * 1024):
                    digest.update(chunk)
        elif path.is_dir():
            digest.update(b"directory\0")
        else:
            digest.update(b"other\0")
        digest.update(str(stat.st_mode).encode())
        digest.update(b"\n")

    git_status = None
    probe = subprocess.run(
        ["git", "-C", str(repo), "rev-parse", "--is-inside-work-tree"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if probe.returncode == 0 and probe.stdout.strip() == "true":
        status = subprocess.run(
            ["git", "-C", str(repo), "status", "--porcelain"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        if status.returncode != 0:
            raise RuntimeError(status.stderr.strip() or "git status failed")
        git_status = status.stdout
    elif probe.returncode != 128:
        raise RuntimeError(probe.stderr.strip() or "git repository snapshot failed")

    return {
        "agent_setup_exists": os.path.lexists(repo / ".agent-setup"),
        "git_status": git_status,
        "tree_sha256": digest.hexdigest(),
    }

def classify(argv, declared_safety):
    payload = json.dumps({"argv": argv, "declared_safety": declared_safety})
    completed = subprocess.run(
        ["bash", classifier, "--classify-only"],
        input=payload + "\n",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        raise RuntimeError(completed.stderr.strip() or "classifier failed")
    result = json.loads(completed.stdout)
    if (
        result.get("effective_safety") not in SAFETY_VALUES
        or not isinstance(result.get("declaration_matches"), bool)
    ):
        raise RuntimeError("classifier returned an invalid result")
    return result

def decision_record(target_id, item_id, kind, argv=None, declared_safety=None):
    result = {
        "target_id": target_id,
        "item_id": item_id,
        "kind": kind,
    }
    if argv is not None:
        result["argv"] = argv
        result["declared_safety"] = declared_safety
        result.update(classify(argv, declared_safety))
    return result

before = json.loads(before_path.read_text(encoding="utf-8"))
contract_path = (repo / contract_relative).resolve()
if repo not in contract_path.parents or not contract_path.is_file():
    raise RuntimeError("selected Contract is not a repository-relative file")
text = contract_path.read_text(encoding="utf-8")
if not text.startswith("---\n") or "\n---" not in text[4:]:
    raise RuntimeError("selected Contract frontmatter is missing")
frontmatter = text[4:].split("\n---", 1)[0]
contract = yaml.safe_load(frontmatter)
if not isinstance(contract, dict):
    raise RuntimeError("selected Contract frontmatter is not a mapping")

probes = []
runtimes = []
setup_targets = contract.get("setup_target", {})
if schema_errors:
    setup_targets = {}
for target_id, target in setup_targets.items():
    if not isinstance(target, dict):
        continue
    runtime = target.get("runtime")
    if isinstance(runtime, dict) and runtime.get("mode") == "process":
        argv = runtime.get("command")
        declared = runtime.get("safety")
        if not isinstance(argv, list) or not argv or declared not in SAFETY_VALUES:
            raise RuntimeError(f"invalid process runtime for {target_id}")
        classification = classify(argv, declared)
        runtimes.append({
            "target_id": target_id,
            "argv": argv,
            "declared_safety": declared,
            **classification,
            "decision": "not_executed",
            "reason": "dry-run never starts a target process",
        })

verification = contract.get("verification")
if not isinstance(verification, dict):
    message = "verification must be a mapping"
    verification_targets = {}
    if not any(
        isinstance(error, dict) and error.get("message") == message
        for error in schema_errors
    ):
        schema_errors.append({"code": "invalid_verification", "message": message})
    audit["schema_errors"] = schema_errors
else:
    verification_targets = verification.get("targets")
    if not isinstance(verification_targets, dict):
        message = "verification.targets must be a mapping"
        verification_targets = {}
        if not any(
            isinstance(error, dict) and error.get("message") == message
            for error in schema_errors
        ):
            schema_errors.append({"code": "invalid_verification", "message": message})
        audit["schema_errors"] = schema_errors
report_verification_targets = verification_targets
if schema_errors:
    verification_targets = {}
for target_id, verification in verification_targets.items():
    if not isinstance(verification, dict):
        continue
    for item in verification.get("items", []):
        if not isinstance(item, dict):
            continue
        item_id = item.get("id")
        if target_id in confirmed_target_ids:
            probes.append({
                "target_id": target_id,
                "item_id": item_id,
                "kind": (item.get("probe") or {}).get("kind"),
                "decision": "not_executed",
                "reason": "target has confirmed audit findings",
                "error_category": "audit_blocked",
            })
            continue
        probe = item.get("probe") or {}
        kind = probe.get("kind")
        if kind == "command":
            argv = probe.get("argv")
            declared = probe.get("safety")
            if not isinstance(argv, list) or not argv or declared not in SAFETY_VALUES:
                raise RuntimeError(f"invalid command probe for {target_id}.{item_id}")
            record = decision_record(target_id, item_id, kind, argv, declared)
            if record["effective_safety"] == "read_only" and record["declaration_matches"]:
                record["decision"] = "execute"
                record["reason"] = "effective read-only command probe"
            else:
                record["decision"] = "not_executed"
                record["reason"] = "Probe Safety Policy v1 rejected execution"
            probes.append(record)
        elif kind == "agent_action":
            adapter = probe.get("adapter") or {}
            argv = adapter.get("argv")
            declared = adapter.get("safety")
            if not isinstance(argv, list) or not argv or declared not in SAFETY_VALUES:
                raise RuntimeError(f"invalid agent_action adapter for {target_id}.{item_id}")
            record = decision_record(target_id, item_id, kind, argv, declared)
            record["decision"] = "not_executed"
            record["reason"] = "P1 agent_action remains a Contract-defined handoff boundary"
            probes.append(record)
        elif kind == "mcp_request":
            record = decision_record(target_id, item_id, kind)
            request = probe.get("request")
            if probe.get("mutation_surface_id"):
                record["reason"] = "temporary_fixture is not automatically executed in P1"
            elif request == "representative_tool_call" and probe.get("safety") != "read_only":
                record["reason"] = "mutating or unknown MCP representative call is safety-blocked"
            else:
                record["reason"] = "MCP runtime and protocol operation are classification-only in dry-run"
            record["decision"] = "not_executed"
            probes.append(record)
        else:
            probes.append({
                "target_id": target_id,
                "item_id": item_id,
                "kind": kind,
                "decision": "not_executed",
                "reason": "unsupported P1 probe kind",
            })

after = snapshot_target()
if before != after:
    raise RuntimeError("invariant_violation: dry-run changed the target repository")

plan = json.loads(plan_path.read_text(encoding="utf-8"))
trigger_ids = plan.get("enhanced_workflow", {}).get("trigger_ids", [])
plan["enhanced_workflow"] = {
    "trigger_ids": trigger_ids,
    "audit_command": "audit-contract.sh",
    "probe_executor": "run-target-probes.sh",
    "classify_only_command": "run-target-probes.sh --classify-only",
    "temporary_fixture_policy": "safety_blocked",
    "note": "Dry-run classification uses the bundled Probe Safety Policy v1 classifier.",
}
plan["contract_audit"] = audit
plan["dry_run"] = {
    "decision": "not_executed",
    "contract": contract_relative,
    "probes": probes,
    "runtimes": runtimes,
    "before_snapshot": before,
    "after_snapshot": after,
}

capabilities = {}
for verification in verification_targets.values():
    for item in verification.get("items", []) if isinstance(verification, dict) else []:
        for capability in item.get("required_capabilities", []) if isinstance(item, dict) else []:
            capabilities[capability] = "unknown"
plan["capabilities"] = [
    {"id": capability, "status": status}
    for capability, status in sorted(capabilities.items())
]

generated_at = datetime.datetime.now(datetime.timezone.utc).isoformat().replace(
    "+00:00", "Z"
)
handoff_definitions = contract.get("handoffs", {})
if not isinstance(handoff_definitions, dict):
    handoff_definitions = {}
audit_findings = audit.get("discrepancies", [])
handoff_references = []
report_targets = {}
for target_id in sorted(report_verification_targets):
    verification = report_verification_targets[target_id]
    if not isinstance(verification, dict):
        continue
    report_items = []
    for item in verification.get("items", []):
        if not isinstance(item, dict) or not isinstance(item.get("id"), str):
            continue
        report_item = {
            "id": item["id"],
            "phase": item.get("phase"),
            "required_for_e2e": item.get("required_for_e2e") is True,
            "status": "not_applicable",
            "reason": "dry-run did not execute verification",
            "evidence": [],
            "error_category": None,
        }
        if isinstance(item.get("handoff_id"), str):
            report_item["handoff_id"] = item["handoff_id"]
        report_items.append(report_item)
        handoff_id = item.get("handoff_id")
        probe = item.get("probe") or {}
        if (
            isinstance(probe, dict)
            and probe.get("kind") == "agent_action"
            and isinstance(handoff_id, str)
            and isinstance(handoff_definitions.get(handoff_id), dict)
        ):
            handoff_references.append({
                "handoff_id": handoff_id,
                "verification_item_id": item["id"],
                "definition": handoff_definitions[handoff_id],
            })
    target_findings = [
        finding
        for finding in audit_findings
        if target_id in finding.get("affected_target_ids", [])
    ]
    report_targets[target_id] = {
        "target_type": verification.get("target_type"),
        "audit_blocked": bool(schema_errors)
        or any(
            finding.get("finding_state") == "confirmed"
            for finding in target_findings
        )
        or target_id in confirmed_target_ids,
        "audit_findings": target_findings,
        "items": report_items,
        "e2e_status": "not_applicable",
        "e2e_status_reason": "dry-run did not execute verification",
    }
verification_report = {
    "generated_at": generated_at,
    "contract": contract_relative,
    "audit": audit,
    "targets": report_targets,
    "capability_assessment": {
        entry["id"]: {
            "status": entry["status"],
            "reason": "dry-run does not assess capability availability",
            "evidence": [],
        }
        for entry in plan["capabilities"]
    },
    "handoffs": [],
    "handoff_references": handoff_references,
    "dry_run": plan["dry_run"],
    "overall_status": (
        "not_verified"
        if schema_errors or confirmed_target_ids
        else "not_applicable"
    ),
}
plan["verification_report"] = verification_report

result_path.write_text(json.dumps(plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
if report_path:
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(
        "# Verification Report\n\n"
        "# Setup verification report\n\n"
        "```json\n"
        + json.dumps(verification_report, ensure_ascii=False, indent=2)
        + "\n```\n",
        encoding="utf-8",
    )
PY
  then
    printf '%s\n' 'invariant_violation: enhanced dry-run failed' >&2
    exit 1
  fi
  local verification_status
  verification_status="$(python3 - "$result_json" <<'PY'
import json
from pathlib import Path
import sys

result = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
report = result.get("verification_report", {})
print(4 if report.get("overall_status") == "not_verified" else 0)
PY
)"
  cat "$result_json"
  return "$verification_status"
}

emit_enhanced_plan() {
  local plan_json="$TEMP_ROOT/plan.json"
  local result_json="$TEMP_ROOT/result.json"
  local status_path="$TEMP_ROOT/verification.status"
  ensure_temp_root
  mkdir -p "$TEMP_ROOT/evidence"
  emit_legacy_plan >"$plan_json"
  if ! python3 - "$plan_json" "$AUDIT_JSON" "$SELECTED_CONTRACT" "$REPO_PATH" \
    "$SCRIPT_DIR/run-target-probes.sh" "$TEMP_ROOT/evidence" "$result_json" \
    "$REPORT_ABS" "$status_path" \
    "$SCRIPT_DIR/../references/setup-capability-matrix.md" <<'PY'
import datetime
import json
import re
import shutil
import subprocess
from pathlib import Path
import sys

import yaml

(
    plan_path,
    audit_path,
    contract_path,
    repo_path,
    probe_script,
    evidence_dir,
    result_path,
    report_path,
    status_path,
    matrix_path,
) = sys.argv[1:]

plan = json.loads(Path(plan_path).read_text(encoding="utf-8"))
audit = json.loads(Path(audit_path).read_text(encoding="utf-8"))
contract_file = (Path(repo_path) / contract_path).resolve()
contract_text = contract_file.read_text(encoding="utf-8")
if not contract_text.startswith("---\n") or "\n---" not in contract_text[4:]:
    raise RuntimeError("selected Contract frontmatter is missing")
contract = yaml.safe_load(contract_text[4:].split("\n---", 1)[0])
if not isinstance(contract, dict):
    raise RuntimeError("selected Contract frontmatter is not a mapping")

schema_errors = audit.get("schema_errors", [])
if not isinstance(schema_errors, list):
    schema_errors = []
    audit["schema_errors"] = schema_errors

def record_schema_error(message):
    if not any(
        isinstance(error, dict) and error.get("message") == message
        for error in schema_errors
    ):
        schema_errors.append({"code": "invalid_verification", "message": message})
    audit["schema_errors"] = schema_errors

verification = contract.get("verification")
if not isinstance(verification, dict):
    verification_targets = {}
    record_schema_error("verification must be a mapping")
else:
    verification_targets = verification.get("targets")
    if not isinstance(verification_targets, dict):
        verification_targets = {}
        record_schema_error("verification.targets must be a mapping")

findings = audit.get("discrepancies", [])
if not isinstance(findings, list):
    findings = []
confirmed_targets = {
    target_id
    for target_id in audit.get("affected_target_ids", [])
    if isinstance(target_id, str) and target_id in verification_targets
}
confirmed_targets.update({
    target_id
    for finding in findings
    if isinstance(finding, dict) and finding.get("finding_state") == "confirmed"
    for target_id in finding.get("affected_target_ids", [])
    if isinstance(target_id, str) and target_id in verification_targets
})

def findings_for(target_id):
    return [
        finding
        for finding in findings
        if target_id in finding.get("affected_target_ids", [])
    ]


def capability_result(status, reason, evidence):
    return {
        "status": status,
        "reason": reason,
        "evidence": evidence,
    }


def load_capability_definitions():
    text = Path(matrix_path).read_text(encoding="utf-8")
    definitions = set()
    in_definitions = False
    for line in text.splitlines():
        if line.startswith("## "):
            in_definitions = line.strip() == "## Capability definitions"
            continue
        if not in_definitions:
            continue
        match = re.match(r"^\|\s*`([^`]+)`\s*\|", line)
        if match:
            definitions.add(match.group(1))
    return definitions


def classify(argv, declared_safety):
    completed = subprocess.run(
        ["bash", probe_script, "--classify-only"],
        input=json.dumps({"argv": argv, "declared_safety": declared_safety}) + "\n",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        raise RuntimeError(completed.stderr.strip() or "classifier failed")
    result = json.loads(completed.stdout)
    if (
        result.get("effective_safety") not in {"read_only", "mutating", "unknown"}
        or not isinstance(result.get("declaration_matches"), bool)
    ):
        raise RuntimeError("classifier returned an invalid result")
    return result


def command_availability(argv, label):
    if (
        not isinstance(argv, list)
        or not argv
        or not all(isinstance(token, str) and token for token in argv)
    ):
        return capability_result(
            "unknown",
            f"{label} has no valid command declaration",
            [],
        )
    executable = argv[0]
    resolved = shutil.which(executable)
    evidence = [
        f"command -v {executable}: {resolved or 'unavailable'}",
    ]
    if resolved is None:
        return capability_result(
            "unavailable",
            f"{label} executable is unavailable",
            evidence,
        )
    return capability_result(
        "available",
        f"{label} executable is available",
        evidence,
    )


def mcp_runtime_availability(target, label):
    runtime = target.get("runtime") if isinstance(target, dict) else None
    if not isinstance(runtime, dict) or runtime.get("mode") != "process":
        return capability_result(
            "unknown",
            f"{label} has no process runtime declaration",
            [],
        )
    argv = runtime.get("command")
    declared_safety = runtime.get("safety")
    result = command_availability(argv, label)
    if result["status"] != "available":
        return result
    evidence = list(result["evidence"])
    try:
        classification = classify(argv, declared_safety)
    except (RuntimeError, json.JSONDecodeError) as exc:
        evidence.append(f"classification: unavailable ({exc})")
        return capability_result(
            "unknown",
            f"{label} safety classification could not be determined",
            evidence,
        )
    evidence.append(
        "classification: "
        f"{classification['effective_safety']} "
        f"(declaration_matches={classification['declaration_matches']})"
    )
    if (
        classification["effective_safety"] != "read_only"
        or not classification["declaration_matches"]
    ):
        return capability_result(
            "unavailable",
            f"{label} is outside the supported read-only MCP runtime boundary",
            evidence,
        )
    return capability_result(
        "available",
        f"{label} is available in PATH and passes the safety classifier",
        evidence,
    )


def capability_candidate(capability, target, item, target_id):
    probe = item.get("probe") if isinstance(item, dict) else None
    if not isinstance(probe, dict):
        return None
    target_type = target.get("target_type") if isinstance(target, dict) else None
    label = f"{capability} for {target_id}.{item.get('id', '<unknown>')}"
    if capability == "mcp_runtime_probe" and target_type == "mcp":
        return mcp_runtime_availability(target, label)
    if capability == "agent_discovery_probe":
        if probe.get("kind") == "agent_action" and probe.get("action") == "discovery":
            adapter = probe.get("adapter") or {}
            return command_availability(adapter.get("argv"), label)
        return None
    if capability == "representative_activation_probe":
        if probe.get("kind") == "agent_action" and probe.get("action") == "activation":
            adapter = probe.get("adapter") or {}
            return command_availability(adapter.get("argv"), label)
        if (
            target_type == "mcp"
            and probe.get("kind") == "mcp_request"
            and probe.get("request") == "representative_tool_call"
        ):
            return mcp_runtime_availability(target, label)
        if probe.get("kind") == "command":
            return command_availability(probe.get("argv"), label)
    return None


def assess_capabilities(targets_by_id, verification_targets_by_id):
    required = {}
    for target_id, verification_target in verification_targets_by_id.items():
        if not isinstance(verification_target, dict):
            continue
        target = targets_by_id.get(target_id, {})
        for item in verification_target.get("items", []):
            if not isinstance(item, dict):
                continue
            required_capabilities = item.get("required_capabilities", [])
            if not isinstance(required_capabilities, list):
                continue
            for capability in required_capabilities:
                if isinstance(capability, str):
                    required.setdefault(capability, []).append((target, item, target_id))

    definitions = load_capability_definitions()
    assessment = {}
    for capability in sorted(required):
        if capability not in definitions:
            assessment[capability] = capability_result(
                "unknown",
                "capability is not defined in setup-capability-matrix.md",
                [],
            )
            continue
        candidates = [
            capability_candidate(capability, target, item, target_id)
            for target, item, target_id in required[capability]
        ]
        candidates = [candidate for candidate in candidates if candidate is not None]
        if not candidates:
            assessment[capability] = capability_result(
                "unknown",
                "Contract has no supported probe for this capability",
                [],
            )
            continue
        evidence = []
        for candidate in candidates:
            for entry in candidate["evidence"]:
                if entry not in evidence:
                    evidence.append(entry)
        available = next(
            (candidate for candidate in candidates if candidate["status"] == "available"),
            None,
        )
        if available is not None:
            assessment[capability] = capability_result(
                "available",
                "at least one Contract-defined capability probe is available",
                evidence,
            )
            continue
        if any(candidate["status"] == "unknown" for candidate in candidates):
            assessment[capability] = capability_result(
                "unknown",
                "capability availability could not be determined",
                evidence,
            )
            continue
        assessment[capability] = capability_result(
            "unavailable",
            "all Contract-defined capability probes are unavailable",
            evidence,
        )
    return assessment


def invoke_probe(target_id, item_id):
    completed = subprocess.run(
        [
            "bash",
            probe_script,
            "--contract",
            contract_path,
            "--target",
            target_id,
            "--item",
            item_id,
            "--evidence-dir",
            evidence_dir,
            repo_path,
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        raise RuntimeError(
            completed.stderr.strip() or "target probe executor failed"
        )
    lines = [line for line in completed.stdout.splitlines() if line.strip()]
    if len(lines) != 1:
        raise RuntimeError("target probe executor did not return one JSON object")
    result = json.loads(lines[0])
    if result.get("target_id") != target_id or result.get("item_id") != item_id:
        raise RuntimeError("target probe result does not identify the requested item")
    return result


def handoff_record(item, item_record, handoffs):
    handoff_id = item.get("handoff_id")
    definition = handoffs.get(handoff_id) if handoff_id else None
    if (
        not isinstance(handoff_id, str)
        or not isinstance(definition, dict)
        or item_record["status"] == "verified"
        or item_record.get("error_category") == "audit_blocked"
    ):
        return None
    record = {
        "handoff_id": handoff_id,
        "verification_item_id": item_record["id"],
        **definition,
        "status": "pending",
        "evidence": [],
        "evaluation_result": "needs_review",
        "definition": definition,
    }
    return record


def derive_e2e(items, review_findings):
    required = [item for item in items if item["required_for_e2e"]]
    active_required = [item for item in required if item["status"] != "not_applicable"]
    if not active_required:
        status = "not_applicable"
        reason = "no required verification items"
    else:
        failed = next(
            (item for item in active_required if item["status"] != "verified"),
            None,
        )
        if failed is None:
            status = "verified"
            reason = "all required verification items verified"
        else:
            status = "not_verified"
            reason = f"required item {failed['id']} is {failed['status']}"
    if review_findings and status != "not_verified":
        status = "not_verified"
        reason = "affected audit findings require semantic review"
    return status, reason


handoffs = contract.get("handoffs", {})
if not isinstance(handoffs, dict):
    handoffs = {}
setup_targets = contract.get("setup_target", {})
if not isinstance(setup_targets, dict):
    setup_targets = {}
capability_assessment = assess_capabilities(setup_targets, verification_targets)
targets = {}
execution_handoffs = []

for target_id in sorted(verification_targets):
    verification = verification_targets[target_id]
    if not isinstance(verification, dict):
        continue
    target_type = verification.get("target_type")
    target_findings = findings_for(target_id)
    review_findings = [
        finding
        for finding in target_findings
        if finding.get("finding_state") in {"candidate", "unresolved"}
    ]
    audit_blocked = bool(schema_errors) or target_id in confirmed_targets
    item_records = []
    item_records_by_id = {}
    items = verification.get("items", [])
    if not isinstance(items, list):
        items = []
    item_by_id = {
        item["id"]: item
        for item in items
        if isinstance(item, dict) and isinstance(item.get("id"), str)
    }
    ordered_items = []
    visited = set()

    def visit(item):
        item_id = item["id"]
        if item_id in visited:
            return
        for dependency in item.get("blocked_by", []):
            dependency_item = item_by_id.get(dependency)
            if dependency_item is not None:
                visit(dependency_item)
        visited.add(item_id)
        ordered_items.append(item)

    for item in items:
        if isinstance(item, dict) and isinstance(item.get("id"), str):
            visit(item)

    for item in ordered_items:
        if not isinstance(item, dict) or not isinstance(item.get("id"), str):
            continue
        item_id = item["id"]
        required_for_e2e = item.get("required_for_e2e") is True
        required_capabilities = item.get("required_capabilities", [])
        if not isinstance(required_capabilities, list):
            required_capabilities = []
        record = {
            "id": item_id,
            "phase": item.get("phase"),
            "required_for_e2e": required_for_e2e,
            "required_capabilities": required_capabilities,
            "status": "not_verified",
            "reason": "",
            "evidence": [],
            "error_category": "audit_blocked",
        }
        if isinstance(item.get("handoff_id"), str):
            record["handoff_id"] = item["handoff_id"]

        if audit_blocked:
            record["reason"] = (
                "Setup Contract audit reported schema errors"
                if schema_errors
                else "target has confirmed audit findings"
            )
        else:
            capability_issue = next(
                (
                    (capability, capability_assessment.get(capability))
                    for capability in required_capabilities
                    if isinstance(capability, str)
                    and capability_assessment.get(capability, {}).get("status")
                    in {"unavailable", "unknown"}
                ),
                None,
            )
            if capability_issue:
                capability, capability_record = capability_issue
                capability_status = capability_record["status"]
                record["status"] = "not_verified"
                record["reason"] = (
                    f"required capability {capability} is {capability_status}"
                )
                record["evidence"] = capability_record.get("evidence", [])
                record["error_category"] = f"capability_{capability_status}"
            else:
                dependencies = item.get("blocked_by", [])
                blocked_dependency = next(
                    (
                        dependency
                        for dependency in dependencies
                        if item_records_by_id.get(dependency, {}).get("status")
                        == "not_verified"
                    ),
                    None,
                )
                if blocked_dependency:
                    record["reason"] = "blocked_by_unverified_dependency"
                    record["error_category"] = "dependency_blocked"
                else:
                    probe_result = invoke_probe(target_id, item_id)
                    record["status"] = probe_result.get("status")
                    record["reason"] = probe_result.get("reason")
                    record["evidence"] = probe_result.get("evidence", [])
                    record["error_category"] = probe_result.get("error_category")
                    if record["status"] not in {
                        "verified",
                        "not_verified",
                        "not_applicable",
                    }:
                        raise RuntimeError("target probe returned an invalid status")
        item_records.append(record)
        item_records_by_id[item_id] = record
        handoff = handoff_record(item, record, handoffs)
        if handoff is not None:
            execution_handoffs.append(handoff)

    item_records = [
        item_records_by_id[item["id"]]
        for item in items
        if isinstance(item, dict) and item.get("id") in item_records_by_id
    ]

    e2e_status, e2e_reason = derive_e2e(item_records, review_findings)
    targets[target_id] = {
        "target_type": target_type,
        "audit_blocked": audit_blocked,
        "audit_findings": target_findings,
        "items": item_records,
        "e2e_status": e2e_status,
        "e2e_status_reason": e2e_reason,
    }

plan["capabilities"] = [
    {"id": capability, "status": result["status"]}
    for capability, result in capability_assessment.items()
]
required_items = [
    item
    for target in targets.values()
    for item in target["items"]
    if item["required_for_e2e"] and item["status"] != "not_applicable"
]
if not required_items:
    overall_status = "not_applicable"
elif all(item["status"] == "verified" for item in required_items):
    overall_status = "verified"
else:
    overall_status = "not_verified"
if schema_errors or any(target["audit_blocked"] for target in targets.values()):
    overall_status = "not_verified"

generated_at = datetime.datetime.now(datetime.timezone.utc).isoformat().replace(
    "+00:00", "Z"
)
verification_report = {
    "generated_at": generated_at,
    "contract": contract_path,
    "audit": audit,
    "targets": targets,
    "capability_assessment": capability_assessment,
    "handoffs": execution_handoffs,
    "dry_run": {"decision": "not_executed", "probes": [], "runtimes": []},
    "overall_status": overall_status,
}
plan["enhanced_workflow"] = {
    "trigger_ids": plan.get("enhanced_workflow", {}).get("trigger_ids", []),
    "audit_command": "audit-contract.sh",
    "probe_executor": "run-target-probes.sh",
    "classify_only_command": "run-target-probes.sh --classify-only",
    "temporary_fixture_policy": "safety_blocked",
    "note": "Use the Setup Contract audit and the bundled target probe executor.",
}
plan["contract_audit"] = audit
plan["contract"] = contract_path
plan["verification_report"] = verification_report

result = json.dumps(plan, ensure_ascii=False, indent=2) + "\n"
Path(result_path).write_text(result, encoding="utf-8")
if report_path:
    report = Path(report_path)
    report.parent.mkdir(parents=True, exist_ok=True)
    markdown = (
        "---\n"
        "report_type: verification\n"
        f"generated_at: {generated_at}\n"
        f"overall_status: {overall_status}\n"
        "---\n\n"
        "# Verification Report\n\n"
        "## Target summary\n\n"
        + "\n".join(
            f"- `{target_id}`: {target['e2e_status']}"
            for target_id, target in targets.items()
        )
        + "\n\n```json\n"
        + json.dumps(verification_report, ensure_ascii=False, indent=2)
        + "\n```\n"
    )
    report.write_text(markdown, encoding="utf-8")
exit_status = 4 if (
    overall_status == "not_verified"
    or any(target["e2e_status"] == "not_verified" for target in targets.values())
) else 0
Path(status_path).write_text(f"{exit_status}\n", encoding="ascii")
PY
  then
    printf '%s\n' 'invariant_violation: enhanced report generation failed' >&2
    exit 1
  fi
  cat "$result_json"
  return "$(<"$status_path")"
}

run_contract_audit() {
  local audit_stderr="$TEMP_ROOT/audit.stderr"
  AUDIT_JSON="$TEMP_ROOT/audit.json"
  local audit_status
  if [[ -n "$CONTRACT_PATH" ]]; then
    if bash "$SCRIPT_DIR/audit-contract.sh" --contract "$CONTRACT_PATH" "$REPO_PATH" >"$AUDIT_JSON" 2>"$audit_stderr"; then
      audit_status=0
    else
      audit_status=$?
    fi
  else
    if bash "$SCRIPT_DIR/audit-contract.sh" "$REPO_PATH" >"$AUDIT_JSON" 2>"$audit_stderr"; then
      audit_status=0
    else
      audit_status=$?
    fi
  fi
  if (( audit_status != 0 )); then
    local schema_gate=false
    if (( audit_status == 2 )) && [[ -s "$AUDIT_JSON" ]]; then
      if python3 - "$AUDIT_JSON" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
discovery = data.get("contract_discovery", {})
raise SystemExit(
    0
    if discovery.get("status") == "found" and data.get("schema_errors")
    else 1
)
PY
      then
        schema_gate=true
      fi
    fi
    if [[ "$schema_gate" != true ]]; then
      cat "$audit_stderr" >&2
      if [[ -s "$AUDIT_JSON" ]]; then
        cat "$AUDIT_JSON" >&2
      fi
      exit "$audit_status"
    fi
  fi
  if ! SELECTED_CONTRACT="$(python3 - "$AUDIT_JSON" <<'PY'
import json
from pathlib import Path
import sys

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
discovery = data.get("contract_discovery", {})
if discovery.get("status") != "found":
    print("contract discovery did not find exactly one Contract", file=sys.stderr)
    raise SystemExit(1)
path = discovery.get("path")
if not isinstance(path, str) or not path:
    print("contract discovery returned no path", file=sys.stderr)
    raise SystemExit(1)
print(path)
PY
)"; then
    cat "$AUDIT_JSON" >&2
    exit 2
  fi
}

if [[ "$ENHANCED_PATH" == true ]]; then
  preflight_pyyaml
  ensure_temp_root
  if [[ "$DRY_RUN" == true ]]; then
    snapshot_target "$TEMP_ROOT/before.json"
  fi
  run_contract_audit
  analyze_external
  if [[ "$DRY_RUN" == true ]]; then
    if emit_enhanced_dry_run; then
      :
    else
      verification_status=$?
      exit "$verification_status"
    fi
  else
    if emit_enhanced_plan; then
      :
    else
      verification_status=$?
      exit "$verification_status"
    fi
  fi
  exit 0
fi

if [[ "$DRY_RUN" == true ]]; then
  ensure_temp_root
  snapshot_target "$TEMP_ROOT/before.json"
  analyze_external
  if has_complexity_triggers "$ANALYZE_JSON"; then
    preflight_pyyaml
    run_contract_audit
    if emit_enhanced_dry_run; then
      :
    else
      verification_status=$?
      exit "$verification_status"
    fi
  else
    emit_simple_dry_run
  fi
  exit 0
fi

if [[ "$CACHE_IS_CURRENT" == true ]]; then
  echo "Using current analyze.json" >&2
  ANALYZE_JSON="$REPO_PATH/.agent-setup/analyze.json"
else
  ensure_temp_root
  analyze_external
fi

if has_complexity_triggers "$ANALYZE_JSON"; then
  preflight_pyyaml
  ensure_temp_root
  run_contract_audit
  if emit_enhanced_plan; then
    exit 0
  else
    verification_status=$?
    exit "$verification_status"
  fi
fi

if [[ "$ANALYZE_JSON" != "$REPO_PATH/.agent-setup/analyze.json" ]]; then
  write_target_cache
fi
if [[ -n "$REPORT_ABS" ]]; then
  ensure_temp_root
  legacy_plan="$TEMP_ROOT/plan.json"
  emit_legacy_plan >"$legacy_plan"
  write_report "$legacy_plan"
  cat "$legacy_plan"
else
  emit_legacy_plan
fi

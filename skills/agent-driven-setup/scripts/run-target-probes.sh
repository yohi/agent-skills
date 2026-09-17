#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLASSIFY_ONLY=false
CONTRACT_PATH=""
TARGET_ID=""
ITEM_ID=""
EVIDENCE_DIR=""
REPO_PATH=""

usage_error() {
  printf '%s\n' "{\"error\":\"usage\",\"message\":\"$1\"}" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --classify-only)
      CLASSIFY_ONLY=true
      shift
      ;;
    --contract)
      [[ $# -ge 2 ]] || usage_error "missing value for --contract"
      CONTRACT_PATH="$2"
      shift 2
      ;;
    --target)
      [[ $# -ge 2 ]] || usage_error "missing value for --target"
      TARGET_ID="$2"
      shift 2
      ;;
    --item)
      [[ $# -ge 2 ]] || usage_error "missing value for --item"
      ITEM_ID="$2"
      shift 2
      ;;
    --evidence-dir)
      [[ $# -ge 2 ]] || usage_error "missing value for --evidence-dir"
      EVIDENCE_DIR="$2"
      shift 2
      ;;
    --)
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

if [[ "$CLASSIFY_ONLY" == true ]]; then
  [[ -z "$CONTRACT_PATH" && -z "$TARGET_ID" && -z "$ITEM_ID" &&
    -z "$EVIDENCE_DIR" && -z "$REPO_PATH" ]] ||
    usage_error "--classify-only does not accept target probe options"

  CLASSIFY_INPUT="$(cat)"
  exec python3 - "$CLASSIFY_INPUT" <<'PY'
import json
import sys

SAFETY_VALUES = {"read_only", "mutating", "unknown"}
READ_ONLY_ARGV = {
    ("node", "--version"),
    ("git", "status", "--porcelain"),
    ("agent-setup-mcp-stdio-readonly",),
}
MUTATING_ARGV = {
    ("npm", "install"),
}


def fail(message):
    print(json.dumps({"error": "invalid_input", "message": message}), file=sys.stderr)
    raise SystemExit(2)


try:
    value = json.loads(sys.argv[1])
except (json.JSONDecodeError, IndexError) as exc:
    fail(f"invalid JSON input: {exc}")

if not isinstance(value, dict):
    fail("input must be a JSON object")
argv = value.get("argv")
declared_safety = value.get("declared_safety")
if (
    not isinstance(argv, list)
    or not argv
    or not all(isinstance(token, str) and token for token in argv)
):
    fail("argv must be a non-empty string list")
if any("/" in token for token in argv):
    fail("argv tokens must not contain path separators")
if declared_safety not in SAFETY_VALUES:
    fail("declared_safety must be read_only, mutating, or unknown")

argv_tuple = tuple(argv)
if argv_tuple in MUTATING_ARGV:
    effective_safety = "mutating"
elif argv_tuple in READ_ONLY_ARGV:
    effective_safety = "read_only"
else:
    effective_safety = "unknown"

print(json.dumps({
    "effective_safety": effective_safety,
    "declaration_matches": declared_safety == effective_safety,
}, separators=(",", ":")))
PY
fi

[[ -n "$CONTRACT_PATH" ]] || usage_error "missing --contract"
[[ -n "$TARGET_ID" ]] || usage_error "missing --target"
[[ -n "$ITEM_ID" ]] || usage_error "missing --item"
[[ -n "$EVIDENCE_DIR" ]] || usage_error "missing --evidence-dir"
[[ -n "$REPO_PATH" ]] || usage_error "missing repository path"

if ! REPO_ROOT="$(cd "$REPO_PATH" 2>/dev/null && pwd -P)"; then
  usage_error "cannot enter repository path"
fi

if ! EVIDENCE_ROOT="$(python3 - "$EVIDENCE_DIR" <<'PY'
from pathlib import Path
import sys

print(Path(sys.argv[1]).resolve(strict=False))
PY
)"; then
  usage_error "cannot enter evidence directory"
fi
if [[ "$EVIDENCE_ROOT" == "$REPO_ROOT" || "$EVIDENCE_ROOT" == "$REPO_ROOT"/* ]]; then
  usage_error "evidence directory must be outside the target repository"
fi
if ! mkdir -p "$EVIDENCE_ROOT" 2>/dev/null; then
  usage_error "cannot create evidence directory"
fi

AUDIT_STDERR="$EVIDENCE_ROOT/contract-audit.stderr"
if ! bash "$SCRIPT_DIR/audit-contract.sh" \
  --contract "$CONTRACT_PATH" "$REPO_ROOT" >/dev/null 2>"$AUDIT_STDERR"; then
  python3 - "$TARGET_ID" "$ITEM_ID" <<'PY'
import json
import sys

print(json.dumps({
    "target_id": sys.argv[1],
    "item_id": sys.argv[2],
    "status": "not_verified",
    "reason": "Setup Contract audit failed",
    "evidence": [],
    "error_category": "audit_blocked",
}, separators=(",", ":")))
PY
  exit 0
fi

python3 - "$REPO_ROOT" "$CONTRACT_PATH" "$TARGET_ID" "$ITEM_ID" "$EVIDENCE_ROOT" <<'PY'
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path

import yaml

REPO_ROOT = Path(sys.argv[1]).resolve()
CONTRACT_PATH = sys.argv[2]
TARGET_ID = sys.argv[3]
ITEM_ID = sys.argv[4]
EVIDENCE_ROOT = Path(sys.argv[5]).resolve()
READ_ONLY_ARGV = {
    ("node", "--version"),
    ("git", "status", "--porcelain"),
    ("agent-setup-mcp-stdio-readonly",),
}
MUTATING_ARGV = {
    ("npm", "install"),
}
SAFETY_VALUES = {"read_only", "mutating", "unknown"}


def emit(status, reason, error_category=None, evidence=None):
    print(json.dumps({
        "target_id": TARGET_ID,
        "item_id": ITEM_ID,
        "status": status,
        "reason": reason,
        "evidence": evidence or [],
        "error_category": error_category,
    }, ensure_ascii=False, separators=(",", ":")))
    raise SystemExit(0)


def classify(argv, declared_safety):
    argv_tuple = tuple(argv)
    if argv_tuple in MUTATING_ARGV:
        effective_safety = "mutating"
    elif argv_tuple in READ_ONLY_ARGV:
        effective_safety = "read_only"
    else:
        effective_safety = "unknown"
    return effective_safety, declared_safety == effective_safety


def evidence_file(record):
    safe_target = re.sub(r"[^A-Za-z0-9_.-]", "_", TARGET_ID)
    safe_item = re.sub(r"[^A-Za-z0-9_.-]", "_", ITEM_ID)
    path = EVIDENCE_ROOT / f"{safe_target}.{safe_item}.json"
    path.write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return str(path)


def summarize_output(stdout, stderr, returncode):
    return {
        "returncode": returncode,
        "stdout_bytes": len(stdout),
        "stderr_bytes": len(stderr),
        "stdout_sha256": hashlib.sha256(stdout).hexdigest(),
        "stderr_sha256": hashlib.sha256(stderr).hexdigest(),
    }


def load_contract():
    path = (REPO_ROOT / CONTRACT_PATH).resolve()
    if not path.is_file() or REPO_ROOT not in path.parents:
        emit("not_verified", "Setup Contract path is not a repository-relative file", "audit_blocked")
    text = path.read_text(encoding="utf-8")
    if not text.startswith("---\n") or "\n---" not in text[4:]:
        emit("not_verified", "Setup Contract frontmatter is missing", "audit_blocked")
    frontmatter = text[4:].split("\n---", 1)[0]
    data = yaml.safe_load(frontmatter)
    if not isinstance(data, dict):
        emit("not_verified", "Setup Contract frontmatter is not a mapping", "audit_blocked")
    return data


contract = load_contract()
targets = contract.get("setup_target", {})
verification_targets = contract.get("verification", {}).get("targets", {})
target = targets.get(TARGET_ID)
verification_target = verification_targets.get(TARGET_ID)
if not isinstance(target, dict) or not isinstance(verification_target, dict):
    emit("not_verified", "target or verification target was not found", "audit_blocked")

items = verification_target.get("items", [])
item = next((candidate for candidate in items if candidate.get("id") == ITEM_ID), None)
if not isinstance(item, dict):
    emit("not_verified", "verification item was not found", "audit_blocked")

probe = item.get("probe")
if not isinstance(probe, dict):
    emit("not_verified", "verification item has no probe", "audit_blocked")

kind = probe.get("kind")
if kind == "agent_action":
    emit("not_verified", "P1 does not start agent_action adapters; use the Contract-defined handoff", "safety_blocked")

if kind == "command":
    argv = probe.get("argv")
    declared_safety = probe.get("safety")
    if not isinstance(argv, list) or not argv or not all(isinstance(token, str) and token for token in argv):
        emit("not_verified", "command probe argv is invalid", "audit_blocked")
    if declared_safety not in SAFETY_VALUES:
        emit("not_verified", "command probe safety is invalid", "audit_blocked")
    effective_safety, declaration_matches = classify(argv, declared_safety)
    if not declaration_matches or effective_safety != "read_only":
        emit("not_verified", "command probe failed the Probe Safety Policy v1 gate", "safety_blocked")
    try:
        completed = subprocess.run(
            argv,
            cwd=REPO_ROOT,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
            check=False,
        )
    except FileNotFoundError:
        emit("not_verified", "read-only command executable is unavailable", "capability_unavailable")
    except subprocess.TimeoutExpired:
        emit("not_verified", "read-only command timed out", "runtime_failure")
    record = summarize_output(completed.stdout, completed.stderr, completed.returncode)
    evidence = [evidence_file(record)]
    if completed.returncode != 0:
        emit("not_verified", "read-only command returned a non-zero exit status", "runtime_failure", evidence)
    emit("verified", "supported read-only command completed", None, evidence)

if kind == "mcp_request":
    request = probe.get("request")
    if request == "representative_tool_call" and probe.get("mutation_surface_id"):
        emit("not_verified", "Contract-defined temporary_fixture is not automatically executed in P1", "safety_blocked")
    if request == "representative_tool_call" and probe.get("safety") != "read_only":
        emit("not_verified", "mutating or unknown MCP representative calls are not automatically executed in P1", "safety_blocked")

    runtime = target.get("runtime", {})
    argv = runtime.get("command") if isinstance(runtime, dict) else None
    declared_safety = runtime.get("safety") if isinstance(runtime, dict) else None
    if not isinstance(argv, list) or not argv or not all(isinstance(token, str) and token for token in argv):
        emit("not_verified", "MCP runtime command is invalid", "audit_blocked")
    if declared_safety not in SAFETY_VALUES:
        emit("not_verified", "MCP runtime safety is invalid", "audit_blocked")
    effective_safety, declaration_matches = classify(argv, declared_safety)
    if not declaration_matches or effective_safety != "read_only":
        emit("not_verified", "MCP runtime failed the Probe Safety Policy v1 gate", "safety_blocked")
    if tuple(argv) != ("agent-setup-mcp-stdio-readonly",):
        emit("not_verified", "MCP runtime is outside the supported P1 fixture boundary", "safety_blocked")
    fixture = os.environ.get("AGENT_SETUP_MCP_FIXTURE")
    if not fixture or not Path(fixture).is_absolute():
        emit("not_verified", "AGENT_SETUP_MCP_FIXTURE must name the caller-provided absolute fixture path", "capability_unavailable")
    try:
        fixture_path = Path(fixture).resolve(strict=True)
    except OSError:
        emit("not_verified", "caller-provided MCP fixture path is unavailable", "capability_unavailable")
    if not fixture_path.is_file() or not os.access(fixture_path, os.X_OK):
        emit("not_verified", "caller-provided MCP fixture is not executable", "capability_unavailable")
    if REPO_ROOT == fixture_path or REPO_ROOT in fixture_path.parents:
        emit("not_verified", "MCP fixture must be outside the target repository", "safety_blocked")
    launch_argv = [str(fixture_path), *argv[1:]]

    if request == "initialize":
        messages = [{"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}}]
    elif request == "tool_discovery":
        messages = [{"jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": {}}]
    elif request == "representative_tool_call":
        messages = [{
            "jsonrpc": "2.0",
            "id": 1,
            "method": "tools/call",
            "params": {"name": probe.get("tool"), "arguments": probe.get("arguments", {})},
        }]
    else:
        emit("not_verified", "MCP request is unsupported", "audit_blocked")

    payload = "".join(json.dumps(message, separators=(",", ":")) + "\n" for message in messages)
    try:
        process = subprocess.Popen(
            launch_argv,
            cwd=REPO_ROOT,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        stdout, stderr = process.communicate(payload, timeout=30)
    except FileNotFoundError:
        emit("not_verified", "supported MCP runtime executable is unavailable", "capability_unavailable")
    except subprocess.TimeoutExpired:
        process.kill()
        process.communicate()
        emit("not_verified", "supported MCP runtime timed out", "runtime_failure")
    record = summarize_output(stdout.encode(), stderr.encode(), process.returncode)
    response_lines = [line for line in stdout.splitlines() if line.strip()]
    expected_ids = [message["id"] for message in messages]
    valid_responses = len(response_lines) == len(expected_ids)
    for line, expected_id in zip(response_lines, expected_ids):
        try:
            response = json.loads(line)
        except json.JSONDecodeError:
            valid_responses = False
            break
        has_result = "result" in response if isinstance(response, dict) else False
        has_error = "error" in response if isinstance(response, dict) else False
        if (
            not isinstance(response, dict)
            or response.get("jsonrpc") != "2.0"
            or response.get("id") != expected_id
            or has_result == has_error
            or has_error
        ):
            valid_responses = False
            break
    record["responses_observed"] = len(response_lines)
    record["responses_valid"] = valid_responses
    evidence = [evidence_file(record)]
    if not valid_responses or process.returncode != 0:
        emit("not_verified", "supported MCP runtime did not produce the expected response", "runtime_failure", evidence)
    emit("verified", "supported MCP read-only request completed", None, evidence)

emit("not_verified", "probe kind is outside the supported P1 executor boundary", "safety_blocked")
PY

#!/bin/bash
# audit-contract.sh — Deterministic Setup Contract audit (Spec 1: discovery + schema/referential validation).
#
# Read-only: never writes to the target repository.
#
# Usage:
#   bash audit-contract.sh [--contract <repo-relative-path>] \
#     [--format json|markdown|both] [--output-dir <target-external-dir>] <repo-path>
#
# Exit codes:
#   0 — audit completed (report emitted; discovery may still be not_found/ambiguous)
#   2 — usage error or malformed Setup Contract (contract_error/schema errors)
#   3 — PyYAML dependency unavailable

set -euo pipefail

PYTHON_BIN=python3

usage_error() {
  printf '%s\n' '{"error":"usage","message":"'"$1"'"}' >&2
  exit 2
}

# --- preflight PyYAML (exit 3 without installing) ---
if ! "$PYTHON_BIN" -c 'import yaml' 2>/dev/null; then
  {
    printf '%s\n' 'dependency_unavailable: PyYAML (>=6.0,<7) is unavailable.'
    printf '%s\n' 'Provision it outside the target repository, for example:'
    printf '%s\n' '  python3 -m pip install -r skills/agent-driven-setup/requirements.txt'
    printf '%s\n' 'Then rerun audit-contract.sh.'
  } >&2
  exit 3
fi

# --- argument parsing ---
CONTRACT_PATH=""
FORMAT="json"
OUTPUT_DIR=""
REPO_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --contract)
      [[ $# -ge 2 ]] || usage_error "missing value for --contract"
      CONTRACT_PATH="$2"
      shift 2
      ;;
    --contract=*)
      CONTRACT_PATH="${1#*=}"
      shift
      ;;
    --format)
      [[ $# -ge 2 ]] || usage_error "missing value for --format"
      FORMAT="$2"
      shift 2
      ;;
    --format=*)
      FORMAT="${1#*=}"
      shift
      ;;
    --output-dir)
      [[ $# -ge 2 ]] || usage_error "missing value for --output-dir"
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --output-dir=*)
      OUTPUT_DIR="${1#*=}"
      shift
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

if [[ -z "$REPO_PATH" ]]; then
  usage_error "missing repository path"
fi

case "$FORMAT" in
  json|markdown|both) ;;
  *) usage_error "invalid --format: $FORMAT (expected json, markdown, or both)" ;;
esac

if [[ "$FORMAT" == "both" && -z "$OUTPUT_DIR" ]]; then
  usage_error "--format both requires --output-dir"
fi

if ! REPO_ROOT="$(cd "$REPO_PATH" 2>/dev/null && pwd -P)"; then
  printf '%s\n' '{"error":"cannot enter repository path"}' >&2
  exit 2
fi

OUT_ABS=""
if [[ -n "$OUTPUT_DIR" ]]; then
  probe="$OUTPUT_DIR"
  while [[ ! -d "$probe" ]]; do
    parent="$(dirname "$probe")"
    if [[ "$parent" == "$probe" ]]; then
      usage_error "output directory is not accessible"
    fi
    probe="$parent"
  done
  if ! OUT_ABS="$(cd "$probe" 2>/dev/null && pwd -P)"; then
    usage_error "output directory is not accessible"
  fi
  if [[ "$OUT_ABS" == "$REPO_ROOT" || "$OUT_ABS" == "$REPO_ROOT"/* ]]; then
    usage_error "output directory must be outside the target repository"
  fi
  if ! mkdir -p "$OUTPUT_DIR" 2>/dev/null; then
    usage_error "cannot create output directory"
  fi
  if ! OUT_ABS="$(cd "$OUTPUT_DIR" 2>/dev/null && pwd -P)"; then
    usage_error "output directory is not accessible"
  fi
  if [[ "$OUT_ABS" == "$REPO_ROOT" || "$OUT_ABS" == "$REPO_ROOT"/* ]]; then
    usage_error "output directory must be outside the target repository"
  fi
fi

OUT_JSON=""
OUT_MD=""
if [[ "$FORMAT" == "both" ]]; then
  OUT_JSON="$OUT_ABS/audit-report.json"
  OUT_MD="$OUT_ABS/audit-report.md"
fi

"$PYTHON_BIN" - "$REPO_ROOT" "$CONTRACT_PATH" "$FORMAT" "$OUT_JSON" "$OUT_MD" <<'PY'
import json
import os
import re
import sys

import yaml

REPO_ROOT = sys.argv[1]
EXPLICIT_CONTRACT = sys.argv[2]
FORMAT = sys.argv[3]
OUT_JSON = sys.argv[4] or None
OUT_MD = sys.argv[5] or None

TARGET_ID_RE = re.compile(r"[a-z][a-z0-9_-]*\Z")
CAPABILITY_ID_RE = re.compile(r"[a-z][a-z0-9_-]*\Z")
SAFETY_VALUES = {"read_only", "mutating", "unknown"}
TARGET_TYPES = {"skill", "mcp", "plugin", "hook", "cli", "service", "other/custom"}
SOURCE_KINDS = {"repository_path", "url", "registry", "external_resource"}
REF_MODES = {"immutable", "mutable", "not_applicable"}
RUNTIME_MODES = {"process", "in_process", "agent_discovery", "external_service", "not_applicable"}
LAYER_KINDS = {
    "choice", "installer", "cli", "env", "settings", "generated_config",
    "registration", "discovery", "runtime_consumer", "activation",
    "representative_operation", "verification",
}
PHASES = {
    "installation", "registration", "discovery", "activation", "runtime_start",
    "initialize", "tool_discovery", "representative_operation",
}
AGENT_ACTIONS = {"discovery", "activation"}
ADAPTER_STDINS = {"prompt", "empty"}
MCP_REQUESTS = {"initialize", "tool_discovery", "representative_tool_call"}
MUTATION_SCOPES = {"repository", "user_local", "global", "external"}
MUTATION_KINDS = {"path", "glob", "external_resource"}
SNAPSHOT_MODES = {"required", "not_supported"}

schema_errors = []


def err(code, message):
    schema_errors.append({"code": code, "message": message})


def is_str(value):
    return isinstance(value, str)


def is_str_list(value):
    return isinstance(value, list) and bool(value) and all(is_str(item) and item for item in value)


def is_normalized_relative_path(path):
    if not is_str(path) or not path:
        return False
    if path.startswith("/"):
        return False
    for part in path.replace("\\", "/").split("/"):
        if part in ("", ".", ".."):
            return False
    return True


def path_stays_inside(relative):
    if not is_normalized_relative_path(relative):
        return False
    resolved = os.path.realpath(os.path.join(REPO_ROOT, relative))
    return resolved == REPO_ROOT or resolved.startswith(REPO_ROOT + os.sep)


def contract_file(relative, source):
    if not is_normalized_relative_path(relative):
        err("invalid_contract_path", f"contract path is not a normalized repository-relative path: {relative}")
        return None
    full = os.path.realpath(os.path.join(REPO_ROOT, relative))
    if not (full == REPO_ROOT or full.startswith(REPO_ROOT + os.sep)):
        err("invalid_contract_path", f"contract path escapes the target repository: {relative}")
        return None
    if not os.path.isfile(full):
        err("invalid_contract_path", f"contract file does not exist: {relative}")
        return None
    return full


def read_frontmatter(path):
    with open(path, encoding="utf-8") as f:
        first = f.readline()
    if first.rstrip("\n").rstrip("\r") != "---":
        return None, "missing frontmatter marker"
    with open(path, encoding="utf-8") as f:
        content = f.read()
    if not content.startswith("---\n"):
        return None, "missing frontmatter marker"
    end = content.find("\n---", 4)
    if end == -1:
        return None, "unterminated frontmatter"
    fm_text = content[4:end]
    try:
        fm = yaml.safe_load(fm_text)
    except yaml.YAMLError as exc:
        return None, f"invalid YAML frontmatter: {exc}"
    if not isinstance(fm, dict):
        return None, "frontmatter is not a mapping"
    return fm, None


def find_markers():
    markers = []
    for filename in ("AGENTS.md", "README.md"):
        path = os.path.join(REPO_ROOT, filename)
        file_markers = []
        if os.path.isfile(path):
            try:
                with open(path, encoding="utf-8") as f:
                    for line in f:
                        line = line.rstrip("\n").rstrip("\r")
                        m = re.match(r"^<!-- agent-setup-contract: (\S+) -->$", line)
                        if m:
                            file_markers.append(m.group(1))
            except Exception:
                file_markers = []
        markers.append(file_markers)
    return markers


def has_version_candidate(path):
    if not os.path.isfile(path):
        return False
    try:
        with open(path, encoding="utf-8") as f:
            first = f.readline()
        if first.rstrip("\n").rstrip("\r") != "---":
            return False
        fm, _ = read_frontmatter(path)
    except Exception:
        return False
    if fm is None:
        return False
    return fm.get("setup_contract_schema_version") == 1


def marker_scan_candidates():
    candidates = []
    setup_path = os.path.join(REPO_ROOT, "SETUP-CONTRACT.md")
    if has_version_candidate(setup_path):
        candidates.append("SETUP-CONTRACT.md")
    docs_root = os.path.join(REPO_ROOT, "docs")
    if os.path.isdir(docs_root) and not os.path.islink(docs_root):
        for dirpath, dirnames, filenames in os.walk(docs_root):
            dirnames[:] = [d for d in dirnames if not os.path.islink(os.path.join(dirpath, d))]
            for name in filenames:
                if not name.endswith(".md"):
                    continue
                full = os.path.join(dirpath, name)
                if os.path.islink(full):
                    continue
                rel = os.path.relpath(full, REPO_ROOT)
                if has_version_candidate(full):
                    candidates.append(rel)
    candidates.sort()
    return candidates


def discover():
    if EXPLICIT_CONTRACT:
        full = contract_file(EXPLICIT_CONTRACT, "explicit")
        if full is None:
            return {"status": "contract_error", "source": "explicit"}, None
        return {"status": "found", "path": EXPLICIT_CONTRACT, "source": "explicit"}, full

    agent_markers, readme_markers = find_markers()
    all_markers = []
    for m in agent_markers:
        all_markers.append(("AGENTS.md", m))
    for m in readme_markers:
        all_markers.append(("README.md", m))
    marker_paths = [m[1] for m in all_markers]
    if len(marker_paths) > 1 and len(set(marker_paths)) > 1:
        return {"status": "ambiguous", "source": "repository_declared"}, None
    if any(len(m) > 1 for m in (agent_markers, readme_markers)):
        return {"status": "ambiguous", "source": "repository_declared"}, None
    if marker_paths:
        rel = marker_paths[0]
        full = contract_file(rel, "repository_declared")
        if full is None:
            return {"status": "contract_error", "source": "repository_declared"}, None
        return {"status": "found", "path": rel, "source": "repository_declared"}, full

    candidates = marker_scan_candidates()
    if len(candidates) > 1:
        return {"status": "ambiguous", "source": "marker_scan"}, None
    if len(candidates) == 1:
        rel = candidates[0]
        full = contract_file(rel, "marker_scan")
        if full is None:
            return {"status": "contract_error", "source": "marker_scan"}, None
        return {"status": "found", "path": rel, "source": "marker_scan"}, full

    return {"status": "not_found", "source": "none"}, None


def validate_top_level(data):
    required = {
        "setup_contract_schema_version", "setup_intent", "setup_target",
        "complexity_triggers", "configuration_branches", "installation",
        "registration", "discovery", "activation", "verification", "handoffs",
        "external_effects",
    }
    if not isinstance(data, dict):
        err("invalid_frontmatter", "contract frontmatter is not a mapping")
        return False
    for key in required:
        if key not in data or data[key] is None:
            err("missing_field", f"required top-level field missing or null: {key}")
    if "setup_contract_schema_version" in data and data["setup_contract_schema_version"] != 1:
        err("invalid_schema_version", "setup_contract_schema_version must be integer 1")
    if any(schema_errors):
        return False
    return True


def validate_targets(data):
    targets = data.get("setup_target")
    if not isinstance(targets, dict) or not targets:
        err("invalid_target", "setup_target must be a non-empty mapping")
        return {}
    for target_id, target in targets.items():
        if not TARGET_ID_RE.fullmatch(target_id):
            err("invalid_target_id", f"target id does not match [a-z][a-z0-9_-]*: {target_id}")
            continue
        if not isinstance(target, dict):
            err("invalid_target", f"target {target_id} is not a mapping")
            continue
        if target.get("target_type") not in TARGET_TYPES:
            err("invalid_target_type", f"target {target_id} has invalid target_type")
        source = target.get("canonical_source")
        if not isinstance(source, dict):
            err("invalid_canonical_source", f"target {target_id} canonical_source is not a mapping")
        else:
            source_kind = source.get("kind")
            if source_kind not in SOURCE_KINDS:
                err("invalid_canonical_source", f"target {target_id} canonical_source.kind invalid")
            if source_kind == "repository_path":
                if not path_stays_inside(source.get("value")):
                    err(
                        "invalid_canonical_source",
                        f"target {target_id} repository_path canonical_source.value must be a normalized repository-relative path inside the target repository",
                    )
            elif not is_str(source.get("value")) or not source.get("value"):
                err("invalid_canonical_source", f"target {target_id} canonical_source.value must be a non-empty string")
            if source.get("ref_mode") not in REF_MODES:
                err("invalid_canonical_source", f"target {target_id} canonical_source.ref_mode invalid")
            else:
                if source["ref_mode"] == "not_applicable":
                    if "ref" in source and source["ref"] is not None:
                        err("invalid_canonical_source", f"target {target_id} canonical_source.ref forbidden for not_applicable")
                else:
                    if not is_str(source.get("ref")) or not source.get("ref"):
                        err("invalid_canonical_source", f"target {target_id} canonical_source.ref required for ref_mode {source['ref_mode']}")
        runtime = target.get("runtime")
        if not isinstance(runtime, dict):
            err("invalid_runtime", f"target {target_id} runtime is not a mapping")
        else:
            mode = runtime.get("mode")
            if mode not in RUNTIME_MODES:
                err("invalid_runtime", f"target {target_id} runtime.mode invalid")
            elif mode == "process":
                if not is_str_list(runtime.get("command")):
                    err("invalid_runtime", f"target {target_id} process runtime.command must be a non-empty argv list")
                if runtime.get("safety") not in SAFETY_VALUES:
                    err("invalid_safety", f"target {target_id} process runtime.safety must be read_only|mutating|unknown")
            else:
                if "command" in runtime:
                    err("invalid_runtime", f"target {target_id} runtime.command forbidden for mode {mode}")
                if "safety" in runtime:
                    err("invalid_runtime", f"target {target_id} runtime.safety forbidden for mode {mode}")
    return targets


def validate_complexity_triggers(data):
    triggers = data.get("complexity_triggers")
    if not isinstance(triggers, list):
        err("invalid_complexity_triggers", "complexity_triggers must be a list")
        return
    seen = set()
    for i, trigger in enumerate(triggers):
        if not isinstance(trigger, dict):
            err("invalid_complexity_trigger", f"complexity_triggers[{i}] is not a mapping")
            continue
        tid = trigger.get("id")
        if not is_str(tid) or not tid:
            err("invalid_complexity_trigger", f"complexity_triggers[{i}] missing id")
            continue
        if tid in seen:
            err("duplicate_complexity_trigger_id", f"duplicate complexity trigger id: {tid}")
        seen.add(tid)
        if not is_str(trigger.get("evidence")) or not trigger.get("evidence"):
            err("invalid_complexity_trigger", f"complexity_triggers[{i}] evidence must be a non-empty string")
        if not is_str(trigger.get("note")) or not trigger.get("note"):
            err("invalid_complexity_trigger", f"complexity_triggers[{i}] note must be a non-empty string")


def validate_layers(data):
    branches = data.get("configuration_branches")
    if not isinstance(branches, list) or not branches:
        err("invalid_configuration_branches", "configuration_branches must be a non-empty list")
        return
    branch_ids = set()
    for i, branch in enumerate(branches):
        if not isinstance(branch, dict):
            err("invalid_configuration_branch", f"configuration_branches[{i}] is not a mapping")
            continue
        bid = branch.get("id")
        if not is_str(bid) or not bid:
            err("invalid_configuration_branch", f"configuration_branches[{i}] missing id")
            continue
        if bid in branch_ids:
            err("duplicate_branch_id", f"duplicate branch id: {bid}")
        branch_ids.add(bid)
        layers = branch.get("layers")
        if not isinstance(layers, list) or not layers:
            err("invalid_configuration_branch", f"branch {bid} layers must be a non-empty list")
            continue
        layer_ids = set()
        for j, layer in enumerate(layers):
            if not isinstance(layer, dict):
                err("invalid_layer", f"branch {bid} layer[{j}] is not a mapping")
                continue
            lid = layer.get("id")
            if not is_str(lid) or not lid:
                err("invalid_layer", f"branch {bid} layer[{j}] missing id")
                continue
            if lid in layer_ids:
                err("duplicate_layer_id", f"branch {bid} duplicate layer id: {lid}")
            layer_ids.add(lid)
            kind = layer.get("kind")
            if kind not in LAYER_KINDS:
                err("invalid_layer_kind", f"branch {bid} layer {lid} has unknown kind: {kind}")
                continue
            allowed = {"id", "kind"}
            required = {"id", "kind"}
            if kind == "env":
                allowed.add("key")
                allowed.add("path")
                required.add("key")
            elif kind == "cli":
                allowed.add("option")
                allowed.add("path")
                required.add("option")
            elif kind == "generated_config":
                allowed.add("path")
                allowed.add("key")
                required |= {"path", "key"}
            elif kind == "runtime_consumer":
                allowed.add("path")
                allowed.add("symbol")
                required |= {"path", "symbol"}
            else:
                allowed |= {"path", "key", "symbol"}
            for key in required:
                if key not in layer or layer[key] is None:
                    err("invalid_layer_shape", f"branch {bid} layer {lid} missing required field {key}")
            for key, value in layer.items():
                if key not in allowed:
                    err("invalid_layer_shape", f"branch {bid} layer {lid} has undeclared field {key}")
                elif key in ("key", "symbol", "option"):
                    if not is_str(value) or not value:
                        err("invalid_layer_shape", f"branch {bid} layer {lid} field {key} must be a non-empty string")
                elif key == "path":
                    if not is_normalized_relative_path(value):
                        err("invalid_contract_path", f"branch {bid} layer {lid} path is not normalized: {value}")


def validate_phase_maps(data, targets):
    items_by_target = {}
    verification = data.get("verification")
    if isinstance(verification, dict) and isinstance(verification.get("targets"), dict):
        for target_id, vt in verification["targets"].items():
            if isinstance(vt, dict) and isinstance(vt.get("items"), list):
                items_by_target[target_id] = {item.get("id") for item in vt["items"] if is_str(item.get("id"))}
    for phase_name in ("installation", "registration", "discovery", "activation"):
        phase_map = data.get(phase_name)
        if not isinstance(phase_map, dict):
            err("invalid_phase_map", f"{phase_name} must be a mapping keyed by target id")
            continue
        for target_id, refs in phase_map.items():
            if target_id not in targets:
                err("invalid_phase_map", f"{phase_name} references unknown target id: {target_id}")
                continue
            if not isinstance(refs, list):
                err("invalid_phase_map", f"{phase_name}.{target_id} must be a list")
                continue
            seen_ids = set()
            for ref in refs:
                if not isinstance(ref, dict):
                    err("invalid_phase_reference", f"{phase_name}.{target_id} entry is not a mapping")
                    continue
                rid = ref.get("id")
                if not is_str(rid) or not rid:
                    err("invalid_phase_reference", f"{phase_name}.{target_id} entry missing id")
                    continue
                if rid in seen_ids:
                    err("duplicate_phase_reference_id", f"{phase_name}.{target_id} duplicate reference id: {rid}")
                seen_ids.add(rid)
                reference = ref.get("reference")
                if not isinstance(reference, dict):
                    err("invalid_phase_reference", f"{phase_name}.{target_id}.{rid} reference is not a mapping")
                    continue
                rkind = reference.get("kind")
                if rkind == "path":
                    if not is_normalized_relative_path(reference.get("path")):
                        err("invalid_contract_path", f"{phase_name}.{target_id}.{rid} path is not normalized")
                    extra = set(reference.keys()) - {"kind", "path", "symbol"}
                    if extra:
                        err("invalid_phase_reference", f"{phase_name}.{target_id}.{rid} path reference has extra fields")
                elif rkind == "external_resource":
                    if not is_str(reference.get("value")) or not reference.get("value"):
                        err("invalid_phase_reference", f"{phase_name}.{target_id}.{rid} external_resource value must be non-empty")
                    extra = set(reference.keys()) - {"kind", "value"}
                    if extra:
                        err("invalid_phase_reference", f"{phase_name}.{target_id}.{rid} external_resource reference has extra fields")
                else:
                    err("invalid_phase_reference", f"{phase_name}.{target_id}.{rid} reference kind must be path or external_resource")
                if "verification_item_id" in ref:
                    if ref["verification_item_id"] not in items_by_target.get(target_id, set()):
                        err("unresolved_verification_item_id", f"{phase_name}.{target_id}.{rid} verification_item_id unresolved")
                if "handoff_id" in ref:
                    handoffs = data.get("handoffs")
                    if not isinstance(handoffs, dict) or ref["handoff_id"] not in handoffs:
                        err("unresolved_handoff_id", f"{phase_name}.{target_id}.{rid} handoff_id unresolved")


def validate_handoffs(data):
    handoffs = data.get("handoffs")
    if not isinstance(handoffs, dict):
        err("invalid_handoffs", "handoffs must be a mapping")
        return
    for hid, handoff in handoffs.items():
        if not isinstance(handoff, dict):
            err("invalid_handoff", f"handoff {hid} is not a mapping")
            continue
        for key in ("actor", "action", "prerequisites", "expected_outcome", "required_evidence"):
            if key not in handoff or handoff[key] is None:
                err("invalid_handoff", f"handoff {hid} missing required field {key}")
        if is_str(handoff.get("actor")) and handoff["actor"] not in {"agent", "user", "external"}:
            err("invalid_handoff", f"handoff {hid} actor must be agent|user|external")


def validate_mutation_surfaces(data):
    effects = data.get("external_effects")
    if not isinstance(effects, dict):
        err("invalid_external_effects", "external_effects must be a mapping")
        return {}
    surfaces = effects.get("mutation_surfaces")
    if not isinstance(surfaces, list):
        err("invalid_external_effects", "external_effects.mutation_surfaces must be a list")
        return {}
    surface_ids = set()
    eligible = set()
    for surface in surfaces:
        if not isinstance(surface, dict):
            err("invalid_mutation_surface", "mutation surface is not a mapping")
            continue
        sid = surface.get("id")
        if not is_str(sid) or not sid:
            err("invalid_mutation_surface", "mutation surface missing id")
            continue
        if sid in surface_ids:
            err("duplicate_mutation_surface_id", f"duplicate mutation surface id: {sid}")
        surface_ids.add(sid)
        if surface.get("scope") not in MUTATION_SCOPES:
            err("invalid_mutation_surface", f"surface {sid} has invalid scope")
        if surface.get("kind") not in MUTATION_KINDS:
            err("invalid_mutation_surface", f"surface {sid} has invalid kind")
        if not is_str(surface.get("value")) or not surface.get("value"):
            err("invalid_mutation_surface", f"surface {sid} value must be a non-empty string")
        if surface.get("snapshot") not in SNAPSHOT_MODES:
            err("invalid_mutation_surface", f"surface {sid} has invalid snapshot")
        if not isinstance(surface.get("cleanup_required"), bool):
            err("invalid_mutation_surface", f"surface {sid} cleanup_required must be boolean")
        if (surface.get("scope") == "external" and surface.get("kind") == "external_resource"
                and surface.get("snapshot") == "required" and surface.get("cleanup_required") is True):
            eligible.add(sid)
    return eligible


def validate_probe(item_id, probe, target_id, eligible_surfaces):
    if not isinstance(probe, dict):
        err("invalid_probe", f"target {target_id} item {item_id} probe is not a mapping")
        return
    kind = probe.get("kind")
    if kind == "command":
        if not is_str_list(probe.get("argv")):
            err("invalid_probe", f"target {target_id} item {item_id} command argv must be a non-empty string list")
        if probe.get("safety") not in SAFETY_VALUES:
            err("invalid_safety", f"target {target_id} item {item_id} command.safety must be read_only|mutating|unknown")
        extra = set(probe.keys()) - {"kind", "argv", "safety"}
        if extra:
            err("invalid_probe", f"target {target_id} item {item_id} command probe has extra fields")
    elif kind == "agent_action":
        if probe.get("action") not in AGENT_ACTIONS:
            err("invalid_probe", f"target {target_id} item {item_id} agent_action action invalid")
        adapter = probe.get("adapter")
        if not isinstance(adapter, dict):
            err("invalid_probe", f"target {target_id} item {item_id} agent_action adapter missing")
        else:
            if adapter.get("kind") != "command":
                err("invalid_probe", f"target {target_id} item {item_id} adapter.kind must be command")
            if not is_str_list(adapter.get("argv")):
                err("invalid_probe", f"target {target_id} item {item_id} adapter.argv must be a non-empty string list")
            if adapter.get("stdin") not in ADAPTER_STDINS:
                err("invalid_probe", f"target {target_id} item {item_id} adapter.stdin must be prompt|empty")
            if adapter.get("safety") not in SAFETY_VALUES:
                err("invalid_safety", f"target {target_id} item {item_id} agent_action.adapter.safety must be read_only|mutating|unknown")
            extra = set(adapter.keys()) - {"kind", "argv", "stdin", "safety"}
            if extra:
                err("invalid_probe", f"target {target_id} item {item_id} adapter has extra fields")
        if isinstance(adapter, dict):
            if adapter.get("stdin") == "prompt":
                if not is_str(probe.get("prompt")) or not probe.get("prompt"):
                    err("invalid_probe", f"target {target_id} item {item_id} prompt required for stdin: prompt")
            elif "prompt" in probe:
                err("invalid_probe", f"target {target_id} item {item_id} prompt forbidden for stdin: empty")
        extra = set(probe.keys()) - {"kind", "action", "adapter", "prompt"}
        if extra:
            err("invalid_probe", f"target {target_id} item {item_id} agent_action probe has extra fields")
    elif kind == "mcp_request":
        request = probe.get("request")
        if request not in MCP_REQUESTS:
            err("invalid_probe", f"target {target_id} item {item_id} mcp_request request invalid")
            return
        if request in ("initialize", "tool_discovery"):
            for field in ("tool", "arguments", "safety", "mutation_surface_id"):
                if field in probe:
                    err("invalid_probe", f"target {target_id} item {item_id} {request} forbids field {field}")
        else:  # representative_tool_call
            if not is_str(probe.get("tool")) or not probe.get("tool"):
                err("invalid_probe", f"target {target_id} item {item_id} representative_tool_call requires tool")
            if not isinstance(probe.get("arguments"), dict):
                err("invalid_probe", f"target {target_id} item {item_id} representative_tool_call requires arguments object")
            safety = probe.get("safety")
            if safety not in SAFETY_VALUES:
                err("invalid_safety", f"target {target_id} item {item_id} representative_tool_call.safety must be read_only|mutating|unknown")
                return
            if safety == "read_only":
                if "mutation_surface_id" in probe:
                    err("invalid_probe", f"target {target_id} item {item_id} read_only representative_tool_call forbids mutation_surface_id")
            else:
                surface_ref = probe.get("mutation_surface_id")
                if not is_str(surface_ref) or not surface_ref:
                    err("invalid_probe", f"target {target_id} item {item_id} mutating/unknown representative_tool_call requires mutation_surface_id")
                elif surface_ref not in eligible_surfaces:
                    err("unresolved_mutation_surface", f"target {target_id} item {item_id} mutation_surface_id unresolved or ineligible")
        extra = set(probe.keys()) - {"kind", "request", "tool", "arguments", "safety", "mutation_surface_id"}
        if extra:
            err("invalid_probe", f"target {target_id} item {item_id} mcp_request probe has extra fields")
    else:
        err("invalid_probe", f"target {target_id} item {item_id} unknown probe kind: {kind}")


def validate_verification(data, targets, eligible_surfaces):
    verification = data.get("verification")
    if not isinstance(verification, dict):
        err("invalid_verification", "verification must be a mapping")
        return
    vt_map = verification.get("targets")
    if not isinstance(vt_map, dict):
        err("invalid_verification", "verification.targets must be a mapping")
        return
    expected = set(targets.keys())
    actual = set(vt_map.keys())
    if expected != actual:
        for tid in actual - expected:
            err("invalid_verification_target", f"verification target id not in setup_target: {tid}")
        for tid in expected - actual:
            err("invalid_verification_target", f"setup_target {tid} missing from verification.targets")
        return
    blocked_map = {}
    target_item_ids = {}
    for target_id, vt in vt_map.items():
        if not isinstance(vt, dict):
            err("invalid_verification_target", f"verification target {target_id} is not a mapping")
            continue
        if vt.get("target_type") != targets[target_id].get("target_type"):
            err("invalid_verification_target", f"verification target {target_id} target_type mismatch")
        items = vt.get("items")
        if not isinstance(items, list) or not items:
            err("invalid_verification_target", f"verification target {target_id} items must be a non-empty list")
            continue
        ids = set()
        for item in items:
            if isinstance(item, dict) and is_str(item.get("id")) and item["id"]:
                ids.add(item["id"])
        target_item_ids[target_id] = ids

    for target_id, vt in vt_map.items():
        if not isinstance(vt, dict) or target_id not in target_item_ids:
            continue
        items = vt.get("items")
        all_item_ids = target_item_ids[target_id]
        item_ids = set()
        blocked_map[target_id] = {}
        for item in items:
            if not isinstance(item, dict):
                err("invalid_verification_item", f"target {target_id} item is not a mapping")
                continue
            iid = item.get("id")
            if not is_str(iid) or not iid:
                err("invalid_verification_item", f"target {target_id} item missing id")
                continue
            if iid in item_ids:
                err("duplicate_verification_item_id", f"target {target_id} duplicate item id: {iid}")
            item_ids.add(iid)
            if item.get("phase") not in PHASES:
                err("invalid_verification_item", f"target {target_id} item {iid} has invalid phase")
            if item.get("target_type") != targets[target_id].get("target_type"):
                err("invalid_verification_item", f"target {target_id} item {iid} target_type mismatch")
            if not isinstance(item.get("required_for_e2e"), bool):
                err("invalid_verification_item", f"target {target_id} item {iid} required_for_e2e must be boolean")
            capabilities = item.get("required_capabilities")
            if capabilities is not None:
                if not isinstance(capabilities, list):
                    err("invalid_required_capabilities", f"target {target_id} item {iid} required_capabilities must be a list")
                else:
                    seen_caps = set()
                    for cap in capabilities:
                        if not is_str(cap) or not CAPABILITY_ID_RE.fullmatch(cap):
                            err("invalid_capability_id", f"target {target_id} item {iid} invalid capability id: {cap}")
                        elif cap in seen_caps:
                            err("duplicate_required_capability", f"target {target_id} item {iid} duplicate capability id: {cap}")
                        seen_caps.add(cap)
            blocked_by = item.get("blocked_by")
            if isinstance(blocked_by, list):
                blocked_map[target_id][iid] = blocked_by
                for dep in blocked_by:
                    if dep not in all_item_ids:
                        err("unknown_blocked_by", f"target {target_id} item {iid} blocked_by references unknown id: {dep}")
                    if dep == iid:
                        err("blocked_by_self_reference", f"target {target_id} item {iid} blocked_by self-reference")
            elif blocked_by is not None:
                err("invalid_blocked_by", f"target {target_id} item {iid} blocked_by must be a list")
            probe = item.get("probe")
            if item.get("required_for_e2e") and probe is None:
                err("missing_probe", f"target {target_id} item {iid} required_for_e2e item missing probe")
            if probe is not None:
                validate_probe(iid, probe, target_id, eligible_surfaces)

    # Cycle detection per target.
    for target_id, deps in blocked_map.items():
        visiting = set()
        visited = set()

        def visit(iid):
            if iid in visiting:
                err("blocked_by_cycle", f"target {target_id} blocked_by cycle detected involving {iid}")
                return
            if iid in visited:
                return
            visiting.add(iid)
            for dep in deps.get(iid, []):
                visit(dep)
            visiting.remove(iid)
            visited.add(iid)

        for iid in deps:
            visit(iid)


def render_markdown(report):
    lines = ["# Setup Contract Audit Report", "", "```yaml", "contract_discovery:", f"  status: {report['contract_discovery']['status']}"]
    if "path" in report["contract_discovery"]:
        lines.append(f"  path: {report['contract_discovery']['path']}")
    lines.append(f"  source: {report['contract_discovery']['source']}")
    lines.extend(["```", ""])
    lines.append("## Schema Errors")
    if report["schema_errors"]:
        for entry in report["schema_errors"]:
            lines.append(f"- `{entry['code']}`: {entry['message']}")
    else:
        lines.append("None.")
    lines.append("")
    lines.append("## Discrepancies")
    if report["discrepancies"]:
        for entry in report["discrepancies"]:
            lines.append(f"- {entry}")
    else:
        lines.append("None.")
    lines.append("")
    return "\n".join(lines)


def main():
    discovery, contract_path = discover()
    observed_topology = None
    discrepancies = []
    next_actions = []

    if contract_path is not None:
        try:
            fm, fm_err = read_frontmatter(contract_path)
        except Exception:
            fm, fm_err = None, "unable to read contract file"
        if fm is None:
            err("invalid_frontmatter", fm_err)
            discovery = {
                "status": "contract_error",
                "source": discovery["source"],
            }
        elif validate_top_level(fm):
            targets = validate_targets(fm)
            validate_complexity_triggers(fm)
            validate_layers(fm)
            validate_handoffs(fm)
            eligible_surfaces = validate_mutation_surfaces(fm)
            validate_phase_maps(fm, targets)
            validate_verification(fm, targets, eligible_surfaces)

    report = {
        "contract_discovery": discovery,
        "observed_topology": observed_topology,
        "discrepancies": discrepancies,
        "schema_errors": schema_errors,
        "next_actions": next_actions,
    }

    if FORMAT == "json":
        print(json.dumps(report, indent=2, ensure_ascii=False))
    elif FORMAT == "markdown":
        print(render_markdown(report))
    else:  # both
        with open(OUT_JSON, "w", encoding="utf-8") as f:
            json.dump(report, f, indent=2, ensure_ascii=False)
            f.write("\n")
        with open(OUT_MD, "w", encoding="utf-8") as f:
            f.write(render_markdown(report))
            f.write("\n")

    if schema_errors:
        sys.exit(2)


if __name__ == "__main__":
    main()
PY

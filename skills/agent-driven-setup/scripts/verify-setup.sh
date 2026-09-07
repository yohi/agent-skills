#!/bin/bash
# verify-setup.sh — Build a safe, repository-defined verification plan.
#
# Reads the JSON produced by analyze-repo.sh and emits a verification plan
# that classifies each candidate command as safe-to-run, dry-run-only, or
# requires-user-review. The script does NOT run arbitrary repo commands on its
# own; it only prepares the plan so an AI agent can decide what to execute.
#
# Usage:
#   bash scripts/verify-setup.sh [repo-path]
#
# If <repo-path>/.agent-setup/analyze.json exists, it is used. Otherwise
# analyze-repo.sh is run first.

set -euo pipefail

REPO_PATH="${1:-$PWD}"
if ! REPO_PATH="$(cd "$REPO_PATH" 2>/dev/null && pwd)"; then
  echo '{"error":"cannot enter repository path"}' >&2
  exit 1
fi
ANALYZE_JSON="$REPO_PATH/.agent-setup/analyze.json"

mkdir -p "$REPO_PATH/.agent-setup"

if [[ -f "$ANALYZE_JSON" ]]; then
  echo "Using existing analyze.json" >&2
else
  echo "Running analyze-repo.sh first" >&2
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  ANALYZE_TMP="$(mktemp "$REPO_PATH/.agent-setup/analyze.json.XXXXXX")"
  trap 'rm -f -- "$ANALYZE_TMP"' EXIT
  if bash "$SCRIPT_DIR/analyze-repo.sh" "$REPO_PATH" > "$ANALYZE_TMP"; then
    mv "$ANALYZE_TMP" "$ANALYZE_JSON"
    trap - EXIT
  else
    status=$?
    exit "$status"
  fi
fi

python3 - "$ANALYZE_JSON" <<'PY'
import json
import re
import sys
from pathlib import Path

analyze_path = Path(sys.argv[1])
data = json.loads(analyze_path.read_text(encoding="utf-8"))

def classify(cmd: str) -> dict:
    """Classify a repo-defined command by likely side-effect risk."""
    if not cmd:
        return None
    lower = cmd.lower()
    # Commands that are usually local-only and idempotent.
    safe_prefixes = (
        "npm test", "yarn test", "pnpm test", "bun test",
        "cargo test", "go test", "pytest", "python -m pytest",
        "bundle exec rspec", "make test", "make check",
        "npm run lint", "yarn lint", "pnpm lint", "make lint",
        "cargo check", "go vet",
    )
    # Commands that may need review because they can mutate state.
    review_keywords = (
        "sudo", "deploy", "publish", "push", "release",
        "provision", "apply", "destroy", "terraform", "aws ",
        "gcloud", "az ", "kubectl", "docker push", "fly deploy",
        "npm publish", "pip upload", "twine upload",
    )
    # Only include commands with a generic dry-run invocation. AWS, gcloud, and
    # az expose dry-run-like behavior on selected subcommands, so guessing a
    # flag for them would be less safe than asking the user.
    dry_run_actions = {
        "make": ("flag", "--dry-run"),
        "terraform": ("command", "terraform plan"),
        "kubectl": ("flag", "--dry-run=client"),
        "npm publish": ("flag", "--dry-run"),
        "twine upload": ("flag", "--dry-run"),
    }

    category = "review"

    def starts_with_command(command: str, candidate: str) -> bool:
        return re.match(rf"^{re.escape(candidate)}(?:\s|$)", command) is not None

    for prefix in safe_prefixes:
        if starts_with_command(lower, prefix):
            category = "safe"
            break
    for kw in review_keywords:
        if kw in lower:
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

plan = {
    "commands": [],
    "notes": [],
}

for key, label in (("install_command", "install"), ("build_command", "build"),
                   ("test_command", "test"), ("lint_command", "lint")):
    cmd = data.get(key)
    entry = classify(cmd)
    if entry:
        entry["phase"] = label
        plan["commands"].append(entry)

# If the repo has a Makefile, surface the available targets so the agent can
# consider them without parsing the Makefile itself.
makefile_path = analyze_path.parent.parent / "Makefile"
if makefile_path.exists():
    targets = []
    seen_targets = set()
    assignment_pattern = re.compile(
        r"^(?:(?:export|override)\s+)*"
        r"[A-Za-z_][A-Za-z0-9_.-]*\s*(?::=|\?=|\+=|!=|=)"
    )
    for line in makefile_path.read_text(encoding="utf-8", errors="replace").splitlines():
        if assignment_pattern.match(line):
            continue
        if ":" in line and not line.startswith(("\t", "#", " ")):
            for target in line.split(":", 1)[0].split():
                if (
                    target
                    and not target.startswith(".")
                    and "%" not in target
                    and target not in seen_targets
                ):
                    seen_targets.add(target)
                    targets.append(target)
    if targets:
        plan["makefile_targets"] = targets

# Flag credential-sensitive environment templates.
if data.get("env_template"):
    plan["notes"].append("Repository has an env template; verify secrets are handled per the secret policy before running any integration test.")

json.dump(plan, sys.stdout, indent=2, ensure_ascii=False)
print()
PY

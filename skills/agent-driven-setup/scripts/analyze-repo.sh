#!/bin/bash
# analyze-repo.sh — Deterministic repository setup-contract discovery.
#
# Inspects the current working directory (or a provided path) and emits a JSON
# summary of setup-related facts. The output is intended to be consumed by an
# AI coding agent so it can reason about the repository without re-running the
# same discovery commands.
#
# Usage:
#   bash scripts/analyze-repo.sh [repo-path]
#
# Safe defaults: read-only operations only. No destructive actions.

set -euo pipefail

REPO_PATH="${1:-$PWD}"
if ! REPO_PATH="$(cd "$REPO_PATH" 2>/dev/null && pwd)"; then
  echo '{"error":"cannot enter repository path"}' >&2
  exit 1
fi

cd "$REPO_PATH" || {
  echo '{"error":"cannot enter repository path"}' >&2
  exit 1
}

# Emit status messages to stderr, JSON to stdout.
echo "Analyzing repository at $REPO_PATH" >&2

# ── Helpers ──────────────────────────────────────────────────────────────────

file_exists() { [[ -f "$1" ]]; }
dir_exists()  { [[ -d "$1" ]]; }

json_field() {
  local file="$1"
  local key="$2"
  if command -v python3 >/dev/null 2>&1 && file_exists "$file"; then
    python3 - "$file" "$key" 2>/dev/null <<'PY' || true
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as f:
        value = json.load(f)
    for part in sys.argv[2].split("."):
        if not isinstance(value, dict):
            value = ""
            break
        value = value.get(part, "")
except (OSError, json.JSONDecodeError):
    value = ""

print(value if isinstance(value, str) else "")
PY
  fi
}

# Join newline-separated values into a single |-delimited string for Python.
encode_list() {
  local values="$1"
  if [[ -z "$values" ]]; then
    echo ""
  else
    printf '%s' "$values" | sed 's/|/\\|/g' | tr '\n' '|' | sed 's/|$//'
  fi
}

# ── Package manager / runtime detection ──────────────────────────────────────

package_manager=""
install_command=""
test_command=""
build_command=""
lint_command=""
lockfiles=""

if file_exists "package.json"; then
  package_manager="npm"
  install_command="npm install"
  test_command="npm test"
  build_command="$(json_field package.json scripts.build)"
  lint_command="$(json_field package.json scripts.lint)"
  file_exists "package-lock.json" && lockfiles+="package-lock.json"$'\n'
  if file_exists "yarn.lock"; then
    package_manager="yarn"
    install_command="yarn install"
    test_command="yarn test"
    lockfiles+="yarn.lock"$'\n'
  fi
  if file_exists "pnpm-lock.yaml"; then
    package_manager="pnpm"
    install_command="pnpm install"
    test_command="pnpm test"
    lockfiles+="pnpm-lock.yaml"$'\n'
  fi
  if file_exists "bun.lockb"; then
    package_manager="bun"
    install_command="bun install"
    test_command="bun test"
    lockfiles+="bun.lockb"$'\n'
  fi
elif file_exists "pyproject.toml"; then
  package_manager="pip"
  install_command="pip install -e ."
  test_command="python -m pytest"
  build_command="python -m build"
  if file_exists "poetry.lock"; then
    package_manager="poetry"
    install_command="poetry install"
    lockfiles+="poetry.lock"$'\n'
  elif file_exists "Pipfile"; then
    package_manager="pipenv"
    install_command="pipenv install"
    file_exists "Pipfile.lock" && lockfiles+="Pipfile.lock"$'\n'
  fi
elif file_exists "Cargo.toml"; then
  package_manager="cargo"
  install_command="cargo build"
  test_command="cargo test"
  build_command="cargo build --release"
  file_exists "Cargo.lock" && lockfiles+="Cargo.lock"$'\n'
elif file_exists "go.mod"; then
  package_manager="go"
  install_command="go mod download"
  test_command="go test ./..."
  build_command="go build ./..."
  file_exists "go.sum" && lockfiles+="go.sum"$'\n'
elif file_exists "Gemfile"; then
  package_manager="bundler"
  install_command="bundle install"
  test_command="bundle exec rspec"
  build_command=""
  file_exists "Gemfile.lock" && lockfiles+="Gemfile.lock"$'\n'
fi

# Allow explicit task-runner commands to override inferred test/build/lint.
if file_exists "Makefile"; then
  # Match target declarations, not variable assignments or recipe commands.
  makefile_has_target() {
    local wanted="$1"
    local line target_list target
    local -a targets

    while IFS= read -r line; do
      [[ "$line" == $'\t'* ]] && continue
      [[ "$line" =~ ^[[:space:]]*# ]] && continue
      [[ "$line" =~ ^[[:space:]]*((export|override)[[:space:]]+)*[A-Za-z_][A-Za-z0-9_.-]*[[:space:]]*(\?=|\+=|:=|!=|=) ]] && continue
      [[ "$line" == *:* ]] || continue

      target_list="${line%%:*}"
      read -r -a targets <<< "$target_list"
      for target in "${targets[@]}"; do
        [[ "$target" == "$wanted" ]] && return 0
      done
    done < "Makefile"

    return 1
  }

  if [[ -z "$test_command" ]] && makefile_has_target "test"; then
    test_command="make test"
  fi
  if [[ -z "$build_command" ]] && makefile_has_target "build"; then
    build_command="make build"
  fi
  if [[ -z "$lint_command" ]] && makefile_has_target "lint"; then
    lint_command="make lint"
  fi
fi

# ── CI / container / environment templates ───────────────────────────────────

has_github_actions="false"
has_ci_other="false"
has_docker="false"
has_env_example="false"
has_agents_md="false"
has_claude_md="false"
has_opencode="false"

dir_exists ".github/workflows" && has_github_actions="true"
(dir_exists ".circleci" || file_exists ".gitlab-ci.yml" || file_exists "azure-pipelines.yml") && has_ci_other="true"
(file_exists "Dockerfile" || file_exists "docker-compose.yml" || file_exists "compose.yml") && has_docker="true"
(file_exists ".env.example" || file_exists ".env.sample") && has_env_example="true"
file_exists "AGENTS.md" && has_agents_md="true"
file_exists "CLAUDE.md" && has_claude_md="true"
dir_exists ".opencode" && has_opencode="true"

# ── README / install docs ────────────────────────────────────────────────────

readme_path=""
for candidate in "README.md" "README.rst" "README.txt" "README"; do
  if file_exists "$candidate"; then
    readme_path="$candidate"
    break
  fi
done

install_docs=""
for candidate in "docs/install.md" "docs/installation.md" "docs/setup.md" "docs/getting-started.md" "INSTALL.md"; do
  if file_exists "$candidate"; then
    install_docs+="$candidate"$'\n'
  fi
done

# ── VCS / default branch ────────────────────────────────────────────────────

git_remote=""
default_branch=""
if git rev-parse --git-dir >/dev/null 2>&1; then
  git_remote="$(git remote get-url origin 2>/dev/null || true)"
  default_branch="$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's#^refs/remotes/origin/##' || true)"
  [[ -z "$default_branch" ]] && default_branch="$(git config init.defaultBranch 2>/dev/null || true)"
  [[ -z "$default_branch" ]] && default_branch="main"
fi

# ── Complexity triggers (evidence-only) ───────────────────────────────────
# Each trigger records a deterministic, read-only observation; the list never
# mechanically selects a workflow.
complexity_ids=""
complexity_evidence=""
complexity_notes=""

append_trigger() {
  local id="$1" evidence="$2" note="$3"
  complexity_ids+="$id"$'\n'
  complexity_evidence+="$evidence"$'\n'
  complexity_notes+="$note"$'\n'
}

# mcp-runtime: a declared MCP server runtime config exists.
mcp_config=""
for candidate in "mcp.json" ".mcp.json"; do
  if file_exists "$candidate"; then
    mcp_config="$candidate"
    break
  fi
done
if [[ -n "$mcp_config" ]]; then
  append_trigger "mcp-runtime" "$mcp_config" "An MCP server runtime is configured; starting and observing it requires an enhanced workflow."
fi

# multiple-config-writers: two or more distinct config source files exist.
config_writers=""
for candidate in ".env.example" ".env.sample" "config/settings.yaml" "config/settings.yml" "setup.cfg" ".npmrc"; do
  if file_exists "$candidate"; then
    config_writers+="$candidate"$'\n'
  fi
done
config_writer_count="$(printf '%s' "$config_writers" | grep -c '^' 2>/dev/null || true)"
if (( config_writer_count >= 2 )); then
  writer_evidence="$(printf '%s' "$config_writers" | sed '/^$/d' | paste -sd, -)"
  append_trigger "multiple-config-writers" "$writer_evidence" "Multiple distinct config sources exist; keeping them in sync adds setup complexity."
fi

# webhook-url: an existing asset references a webhook delivery endpoint.
webhook_file=""
webhook_files=( README.md AGENTS.md mcp.json .mcp.json *.json *.yaml *.yml *.toml .env.example .env.sample config/settings.yaml config/settings.yml docs/*.md )
for f in "${webhook_files[@]}"; do
  [[ -f "$f" ]] && grep -Eq 'https?://[^[:space:]"]*webhook[^[:space:]"]*' "$f" && webhook_file="$f" && break
done
if [[ -n "$webhook_file" ]]; then
  append_trigger "webhook-url" "$webhook_file" "A webhook delivery endpoint is referenced; setup must account for it."
fi

# ── Assemble JSON ────────────────────────────────────────────────────────────

python3 - "$package_manager" "$install_command" "$test_command" "$build_command" "$lint_command" "$(encode_list "$lockfiles")" "$has_github_actions" "$has_ci_other" "$has_docker" "$has_env_example" "$has_agents_md" "$has_claude_md" "$has_opencode" "$readme_path" "$(encode_list "$install_docs")" "$git_remote" "$default_branch" "$(encode_list "$complexity_ids")" "$(encode_list "$complexity_evidence")" "$(encode_list "$complexity_notes")" <<'PY'
import sys, json

def parse_list(s):
    if not s:
        return []
    items = []
    current = []
    index = 0
    while index < len(s):
        char = s[index]
        if char == '\\' and index + 1 < len(s) and s[index + 1] == '|':
            current.append('|')
            index += 2
        elif char == '|':
            if current:
                items.append(''.join(current))
                current = []
            index += 1
        else:
            current.append(char)
            index += 1
    if current:
        items.append(''.join(current))
    return items

def boolify(s):
    return str(s).lower() == 'true'

(
    package_manager, install_command, test_command, build_command, lint_command,
    lockfiles_enc, has_github_actions, has_ci_other, has_docker, has_env_example,
    has_agents_md, has_claude_md, has_opencode, readme_path, install_docs_enc,
    git_remote, default_branch
) = sys.argv[1:18]

complexity_ids = parse_list(sys.argv[18]) if len(sys.argv) > 18 else []
complexity_evidence = parse_list(sys.argv[19]) if len(sys.argv) > 19 else []
complexity_notes = parse_list(sys.argv[20]) if len(sys.argv) > 20 else []
complexity_triggers = [
    {"id": i, "evidence": e, "note": n}
    for i, e, n in zip(complexity_ids, complexity_evidence, complexity_notes)
]

output = {
    "package_manager": package_manager or None,
    "install_command": install_command or None,
    "test_command": test_command or None,
    "build_command": build_command or None,
    "lint_command": lint_command or None,
    "lockfiles": parse_list(lockfiles_enc),
    "ci": {
        "github_actions": boolify(has_github_actions),
        "other": boolify(has_ci_other),
    },
    "container": boolify(has_docker),
    "env_template": boolify(has_env_example),
    "agent_config": {
        "AGENTS.md": boolify(has_agents_md),
        "CLAUDE.md": boolify(has_claude_md),
        ".opencode/": boolify(has_opencode),
    },
    "readme": readme_path or None,
    "install_docs": parse_list(install_docs_enc),
    "git_remote": git_remote or None,
    "default_branch": default_branch or None,
    "complexity_triggers": complexity_triggers,
}

json.dump(output, sys.stdout, indent=2, ensure_ascii=False)
print()
PY

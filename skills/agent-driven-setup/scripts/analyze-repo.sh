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
REPO_PATH="$(cd "$REPO_PATH" && pwd)"

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
    with open(sys.argv[1]) as f:
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
  test_command="$(json_field package.json scripts.test)"
  [[ -z "$test_command" ]] && test_command="npm test"
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
  lockfiles+="pyproject.toml"$'\n'
  if file_exists "poetry.lock"; then
    package_manager="poetry"
    install_command="poetry install"
    lockfiles+="poetry.lock"$'\n'
  elif file_exists "Pipfile"; then
    package_manager="pipenv"
    install_command="pipenv install"
    lockfiles+="Pipfile.lock"$'\n'
  fi
elif file_exists "Cargo.toml"; then
  package_manager="cargo"
  install_command="cargo build"
  test_command="cargo test"
  build_command="cargo build --release"
  lockfiles+="Cargo.lock"$'\n'
elif file_exists "go.mod"; then
  package_manager="go"
  install_command="go mod download"
  test_command="go test ./..."
  build_command="go build ./..."
  lockfiles+="go.sum"$'\n'
elif file_exists "Gemfile"; then
  package_manager="bundler"
  install_command="bundle install"
  test_command="bundle exec rspec"
  build_command=""
  lockfiles+="Gemfile.lock"$'\n'
fi

# Allow explicit task-runner commands to override inferred test/build/lint.
if file_exists "Makefile"; then
  [[ -z "$test_command" ]] && grep -qE "^[[:space:]]*test:" "Makefile" 2>/dev/null && test_command="make test"
  [[ -z "$build_command" ]] && grep -qE "^[[:space:]]*build:" "Makefile" 2>/dev/null && build_command="make build"
  [[ -z "$lint_command" ]] && grep -qE "^[[:space:]]*lint:" "Makefile" 2>/dev/null && lint_command="make lint"
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
if dir_exists ".git"; then
  git_remote="$(git remote get-url origin 2>/dev/null || true)"
  default_branch="$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's#^refs/remotes/origin/##' || true)"
  [[ -z "$default_branch" ]] && default_branch="$(git config init.defaultBranch 2>/dev/null || true)"
  [[ -z "$default_branch" ]] && default_branch="main"
fi

# ── Assemble JSON ────────────────────────────────────────────────────────────

python3 - "$package_manager" "$install_command" "$test_command" "$build_command" "$lint_command" "$(encode_list "$lockfiles")" "$has_github_actions" "$has_ci_other" "$has_docker" "$has_env_example" "$has_agents_md" "$has_claude_md" "$has_opencode" "$readme_path" "$(encode_list "$install_docs")" "$git_remote" "$default_branch" <<'PY'
import sys, json

def parse_list(s):
    if not s:
        return []
    return [item for item in s.split('|') if item]

def boolify(s):
    return str(s).lower() == 'true'

(
    package_manager, install_command, test_command, build_command, lint_command,
    lockfiles_enc, has_github_actions, has_ci_other, has_docker, has_env_example,
    has_agents_md, has_claude_md, has_opencode, readme_path, install_docs_enc,
    git_remote, default_branch
) = sys.argv[1:18]

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
}

json.dump(output, sys.stdout, indent=2, ensure_ascii=False)
print()
PY

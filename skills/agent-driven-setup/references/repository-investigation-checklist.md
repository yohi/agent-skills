# Repository Investigation Checklist

Use this list before changing anything in the target repository. The goal is to
derive the repository's actual setup contract from implementation evidence, not
from the README alone.

## 1. Human-facing entry points

- [ ] `README.md` — install / getting-started / quickstart sections
- [ ] `docs/install.md`, `docs/installation.md`, `docs/setup.md`, `docs/getting-started.md`
- [ ] `INSTALL.md` at repository root
- [ ] `CONTRIBUTING.md` — developer setup section

## 2. Package metadata and dependency files

- [ ] `package.json`, `yarn.lock`, `pnpm-lock.yaml`, `bun.lockb`
- [ ] `pyproject.toml`, `setup.py`, `setup.cfg`, `requirements*.txt`, `poetry.lock`, `Pipfile`
- [ ] `Cargo.toml`, `Cargo.lock`
- [ ] `go.mod`, `go.sum`
- [ ] `Gemfile`, `Gemfile.lock`
- [ ] `pom.xml`, `build.gradle`, `settings.gradle`

## 3. Task runners and build tools

- [ ] `Makefile`
- [ ] `justfile`
- [ ] `package.json` scripts
- [ ] `pyproject.toml` scripts / task sections
- [ ] Gradle / Maven tasks

## 4. Bootstrap / setup scripts

- [ ] `setup.sh`, `setup.py`, `setup.rb`, `bootstrap.sh`
- [ ] `install.sh`, `configure.sh`
- [ ] `scripts/` directory contents

## 5. Environment configuration

- [ ] `.env.example`, `.env.sample`
- [ ] Equivalent templates (e.g., `config.env.example`)
- [ ] `.gitignore` entries for env files
- [ ] Existing `.env` files (read only presence, never values)

## 6. CI / CD

- [ ] `.github/workflows/`
- [ ] `.circleci/`, `.gitlab-ci.yml`, `azure-pipelines.yml`, `Jenkinsfile`
- [ ] CI install / build / test steps (these often reveal the canonical setup contract)

## 7. Container configuration

- [ ] `Dockerfile`, `Dockerfile.*`
- [ ] `docker-compose.yml`, `compose.yml`
- [ ] `.devcontainer/`

## 8. Existing Agent configuration

- [ ] `AGENTS.md`
- [ ] `CLAUDE.md`
- [ ] `.opencode/`
- [ ] `.cursor/rules/`
- [ ] Other agent-specific settings

## 9. Supported environment

- [ ] `engines` in `package.json`
- [ ] `classifiers` / `requires-python` in `pyproject.toml`
- [ ] CI runner OS / architecture
- [ ] Docker base image
- [ ] Release artifact platforms

## 10. Credential and authentication requirements

- [ ] `.env.example` entries that look like secrets
- [ ] CLI auth requirements (`aws configure`, `gh auth login`, etc.)
- [ ] API key / token mentions in docs
- [ ] OAuth / browser login flows

## How to use this checklist

1. Run `bash scripts/analyze-repo.sh [repo-path]` first. It surfaces the most
   common facts automatically.
2. Use this checklist to fill gaps that `analyze-repo.sh` cannot detect (for
   example, secret requirements, unsupported platforms, or hidden scripts).
3. When another independent source exists, cross-check it before deciding the
   canonical setup source. If no second source exists, use the single available
   source and record its path, scope, and constraints before selecting it. CI,
   lockfiles, and task runners are usually more reliable than prose docs.
4. If `analyze-repo.sh` emits complexity triggers, switch to the enhanced
   workflow and inspect the Setup Contract v1 surface.

## 11. Enhanced workflow checks (when complexity triggers exist)

When the repository reports complexity triggers, add these checks before any
setup change. The goal is to validate the explicit Contract instead of guessing
the setup contract from README prose.

- [ ] **Trigger evidence** — Record each trigger's `id`, `evidence`, and `note`
  from `analyze-repo.sh`. Triggers such as `mcp-runtime`,
  `multiple-config-writers`, and `webhook-url` indicate that the repository has
  more than one configuration surface.
- [ ] **Contract placement** — Decide whether the Contract lives at
  `SETUP-CONTRACT.md` or under `docs/` and confirm it is a Markdown file with
  YAML frontmatter.
- [ ] **Discovery marker** — If the Contract is not at the root, add exactly one
  standalone marker in `AGENTS.md` or `README.md`:
  `<!-- agent-setup-contract: path/to/contract.md -->`. Confirm the path is
  normalized and repository-relative.
- [ ] **Target type** — Confirm each `setup_target.<id>` has a `target_type` of
  `skill`, `mcp`, `plugin`, `hook`, `cli`, `service`, or `other/custom`, plus a
  canonical source with `kind`, `value`, `ref_mode`, and (where required) `ref`.
- [ ] **Configuration branches** — Verify `configuration_branches` is non-empty,
  that branch and layer IDs are unique within scope, and that every layer `kind`
  is one of the closed v1 enum values. Unknown kinds are schema errors.
- [ ] **Mutation surfaces** — Inspect `external_effects.mutation_surfaces`. For
  each surface record `id`, `scope`, `kind`, `value`, `snapshot`, and
  `cleanup_required`. External temporary-fixture surfaces must be
  `scope: external`, `kind: external_resource`, `snapshot: required`, and
  `cleanup_required: true` before they can be referenced by a probe.
- [ ] **Process runtime safety** — For `runtime.mode: process` targets confirm
  both `runtime.command` and `runtime.safety` are present. `runtime.safety` must
  be `read_only`, `mutating`, or `unknown`; other modes must not declare
  `command` or `safety`.
- [ ] **Probe Safety Policy v1 boundary** — Confirm that safety declarations in
  the Contract are shape checks only. Effective classification and execution
  authority belong to `run-target-probes.sh`.
- [ ] **`--classify-only` reuse** — When a dry-run view of probe safety is needed,
  use `run-target-probes.sh --classify-only` instead of reimplementing the
  classifier.
- [ ] **P1 Skill discovery / activation handoff** — For `agent_action` probes with
  `action: discovery` or `action: activation`, plan a handoff to Skill discovery
  / activation rather than executing them inside this workflow.
- [ ] **P1 `temporary_fixture` handoff / `safety_blocked`** — For temporary-fixture
  surfaces declared in the Contract, plan to hand off creation and cleanup or
  report the item as `safety_blocked` instead of running it automatically.
- [ ] **Safety declaration vs execution authority** — Remind the team that a
  declared `read_only`, `mutating`, or `unknown` safety value does not authorize
  execution; it only records intent for the executor's policy.
- [ ] **Simple-path preservation** — If `audit-contract.sh` returns `not_found` or
  no complexity triggers exist, continue with the standard repository
  investigation and choose a setup approach from the decision guide instead of
  forcing a Contract.

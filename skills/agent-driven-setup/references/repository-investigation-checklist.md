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

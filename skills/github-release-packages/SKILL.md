---
name: github-release-packages
description: |
  Automates GitHub release and package publishing workflows using googleapis/release-please-action.
  Covers npm (Node.js), Docker (ghcr.io), Python, Go, and Rust projects.
  Make sure to use this skill whenever the user asks to set up automated releases, GitHub Packages publishing,
  release-please configuration, CI/CD for library distribution, or versioning automation.
  Triggers for: 'release to GitHub Packages', 'setup release please', 'automated versioning',
  'publish npm package to GitHub Packages', 'docker image CI/CD', 'library release automation', 'semantic release'.
---

# github-release-packages

Automate GitHub releases and package publishing using `googleapis/release-please-action`.

## Agent Guidelines (CRITICAL)

The agent **MUST** autonomously scan and analyze the repository files (e.g., `package.json`, `pyproject.toml`, `go.mod`, `Cargo.toml`, `Dockerfile`, `.github/workflows/`, etc.) to determine the language, package manager, and publish targets.

1. **Complete Self-Determination**: Do NOT ask the user for confirmation, choices, or information (such as language, package manager, registry, or existing workflows) if they can be inferred or detected from the repository. Immediately proceed to generating/updating the workflow files.
2. **Runner and Branch Detection**: Always configure the workflow runner to use `ubuntu-slim` (`runs-on: ubuntu-slim`). For the default target branch, do not hardcode `main` or `master` blindly; detect it dynamically using Git command diagnostics (e.g. checking `git remote show origin` or fallback symbolic refs).
3. **Handle Multiple Targets and Sync Autonomously**: If multiple targets are detected (e.g., both a Node.js project and a Dockerfile), configure the workflow to support both/all of them. If the project contains multiple language config files that require version synchronization (e.g., Python as primary and Node.js `package.json` secondary), configure Manifest Mode using `release-please-config.json` and `.release-please-manifest.json` as detailed in `references/manifest-mode.md`. Implement these configurations directly without blocking to ask the user.
4. **Handle Ambiguity with Sensible Defaults**: If the project structure is ambiguous or lacks clear indicator files, make a logical assumption based on any existing files (e.g., defaulting to generic release-please if no specific language matches) and proceed with that choice.
5. **No Questions or Confirmation Loops**: Never ask the user open-ended questions (e.g., "What language is this?") or verification questions (e.g., "I detected Node.js, should I proceed?"). Simply state the detected environment in your execution summary, and directly generate/modify the files.

## What This Skill Does

This skill generates CI/CD workflows that:

1. Create release PRs automatically using [release-please](https://github.com/googleapis/release-please)
2. Build and publish artifacts to GitHub Packages (npm or Docker/ghcr.io)
3. Upload release assets to GitHub Releases
4. Support multiple languages: Node.js, Python, Go, Rust

## Prerequisites

Before using this skill, ensure:

- The repository is on GitHub
- GitHub Actions is enabled
- For npm publishing: `package.json` exists and the package name is scoped (e.g., `@owner/name`)
- For Docker publishing: A `Dockerfile` exists at the repository root
- For GitHub Packages: The repository has `packages: write` permission in workflow settings (or you use the provided workflow which requests it)

## How It Works

1. Relies on [Conventional Commits](https://www.conventionalcommits.org/) to determine version bumps
2. `release-please-action` opens a release PR on each merge to the default branch
3. When the PR is merged, it creates a GitHub Release and a git tag
4. Subsequent workflow steps build and publish artifacts using the new tag

## Usage

### 1. Determine the Language and Package Type

The agent will automatically scan the project files to detect the language and target registry. Use the following table as a reference for mappings:

| Language  | Package Type         | File to Check     |
|-----------|----------------------|-------------------|
| Node.js   | npm (GitHub Packages)| `package.json`    |
| Python    | PyPI / GH Packages   | `pyproject.toml`  |
| Go        | Module               | `go.mod`          |
| Rust      | Crate                | `Cargo.toml`      |
| Any       | Docker (ghcr.io)     | `Dockerfile`      |

### 2. Generate the Workflow

Use the provided script to generate the workflow:

```bash
bash /path/to/skill/scripts/generate-workflow.sh [language] [package-type]
```

**Arguments:**
- `language`: `node`, `python`, `go`, `rust`, or `generic`
- `package-type`: `npm`, `docker`, or `both`

**Example:**
```bash
bash /path/to/skill/scripts/generate-workflow.sh node npm
```

This creates `.github/workflows/release.yml`.

### 3. Manual Workflow Structure

If you prefer to write the workflow manually, see the patterns below.

#### Core Workflow Skeleton

All workflows share this structure:

```yaml
name: Release

on:
  push:
    branches:
      - <default-branch>  # Dynamically detected from remote config (e.g., main or master)

permissions:
  contents: write
  pull-requests: write
  # packages: write only needed when publishing to package registries

jobs:
  release-please:
    runs-on: ubuntu-slim
    steps:
      - uses: googleapis/release-please-action@... # See references for pinned SHA
        id: release
        with:
          release-type: <language>
          target-branch: <default-branch>

      # Checkout and setup steps (if release was created)
      - uses: actions/checkout@v4
        if: ${{ steps.release.outputs.release_created }}
        with:
          ref: ${{ steps.release.outputs.tag_name }}

      # Build and publish steps follow...
```

### 4. Language-Specific Configuration

Read the relevant reference file for detailed setup:

- **Node.js / npm**: See `references/nodejs.md`
- **Docker**: See `references/docker.md`
- **Python**: See `references/python.md`
- **Go**: See `references/go.md`
- **Rust**: See `references/rust.md`
- **Manifest Mode (Multi-Package/Sync)**: See `references/manifest-mode.md`

## Reference Files

- `references/nodejs.md` - Node.js npm publishing to GitHub Packages
- `references/docker.md` - Docker image publishing to ghcr.io
- `references/python.md` - Python package publishing (using twine or pypi/gh actions)
- `references/go.md` - Go module releasing
- `references/rust.md` - Rust crate publishing
- `references/manifest-mode.md` - Manifest Mode config files and setup (Multi-package version sync)

## Important Considerations

### Conventional Commits Are Mandatory

`release-please` parses commit messages to calculate the next version. Ensure your commits follow the Conventional Commits specification:

- `feat:` -> minor version bump
- `fix:` -> patch version bump
- `feat!:` or `BREAKING CHANGE:` -> major version bump

### GitHub Packages Authentication

For npm and Docker workflows, ensure `packages: write` is added to permissions when publishing to registries. Not needed for Go release-only workflows.

For Docker, log in using the builtin `docker/login-action` with `GITHUB_TOKEN`.

### Version Pinning

Always pin actions to a specific SHA for security. The references provide pinned versions.

## Troubleshooting

### Release PR Not Created

- Check that commits follow Conventional Commits
- Ensure the workflow triggered on the correct branch (`main` or `master`)
- Check the workflow logs for parsing errors

### Publishing Fails

- Verify `packages: write` permission is granted
- For npm: Verify the package name matches the repository scope (`@owner/name`)
- For Docker: Verify the image tag matches the repository (`ghcr.io/owner/name`)

### Multiple Package Types

To publish both npm and Docker, combine the steps in a single job or use separate jobs that depend on the `release-please` job. See `references/docker.md` and `references/nodejs.md` for examples.

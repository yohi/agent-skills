# Manifest Mode (Monorepo & Multi-Package Version Sync)

This reference details how to configure `release-please` using Manifest Mode to manage multiple packages or synchronize versions between different files (e.g., synchronizing a Python project version with `package.json`).

## When to Use

Use Manifest Mode when:
- You have a monorepo containing multiple packages that should be released independently or together.
- You have a single-package project where you want to synchronize the version across multiple language configuration files (e.g., Python `pyproject.toml` as primary and Node.js `package.json` as a secondary file).

## Configuration Files

Manifest Mode requires two configuration files in the root of your repository:

### 1. `release-please-config.json`
Defines the release configurations for each package directory.

Example: Primary Python release with version synchronization to `package.json`
```json
{
  "packages": {
    ".": {
      "release-type": "python",
      "extra-files": [
        "package.json"
      ]
    }
  }
}
```

Example: Monorepo with independent Python and Node.js packages
```json
{
  "packages": {
    "packages/python-app": {
      "release-type": "python",
      "package-name": "python-app"
    },
    "packages/node-app": {
      "release-type": "node",
      "package-name": "node-app"
    }
  }
}
```

### 2. `.release-please-manifest.json`
Tracks the current version of each package.

Example:
```json
{
  ".": "1.0.0"
}
```

Example (Monorepo):
```json
{
  "packages/python-app": "1.0.0",
  "packages/node-app": "2.1.0"
}
```

## Workflow Configuration

In your GitHub Actions workflow, configure `release-please-action` to point to these files:

```yaml
      - uses: googleapis/release-please-action@c3fc4de07084f75a2b61a5b933069bda6edf3d5c # v4
        id: release
        with:
          target-branch: main # Replace with your default branch if different
          manifest-file: .release-please-manifest.json
          config-file: release-please-config.json
```

## Runner Note
Always use standard runners like `runs-on: ubuntu-latest` for workflows that include compiling code (e.g., Rust, Go) or building Docker containers, to prevent resource exhaustion (OOM) during build phases.

# Python Publishing Reference

This reference details how to publish Python packages using release-please.

## release-please Configuration

For Python projects, `release-type: python` is used.

```yaml
- uses: googleapis/release-please-action@c3fc4de07084f75a2b61a5b933069bda6edf3d5c # v4
  id: release
  with:
    release-type: python
    target-branch: main
```

## Complete Workflow Example

```yaml
name: Release

on:
  push:
    branches:
      - main

permissions:
  contents: write
  pull-requests: write
  packages: write

jobs:
  release-please:
    runs-on: ubuntu-latest
    steps:
      - uses: googleapis/release-please-action@c3fc4de07084f75a2b61a5b933069bda6edf3d5c # v4
        id: release
        with:
          release-type: python
          target-branch: main

      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4
        if: ${{ steps.release.outputs.release_created }}
        with:
          ref: ${{ steps.release.outputs.tag_name }}

      - uses: actions/setup-python@0a5c61591373683505ea898e09a3ea4f392ef373 # v5
        if: ${{ steps.release.outputs.release_created }}
        with:
          python-version: '3.11'

      - name: Install build tools
        if: ${{ steps.release.outputs.release_created }}
        run: |
          python -m pip install --upgrade pip
          pip install build twine

      - name: Build package
        if: ${{ steps.release.outputs.release_created }}
        run: python -m build

      - name: Publish to GitHub Packages
        if: ${{ steps.release.outputs.release_created }}
        run: twine upload --repository-url https://pypi.pkg.github.com/${{ github.repository_owner }} dist/*
        env:
          TWINE_USERNAME: ${{ github.actor }}
          TWINE_PASSWORD: ${{ secrets.GITHUB_TOKEN }}
```

## pyproject.toml Requirements

Ensure your `pyproject.toml` has:

```toml
[project]
name = "mypackage"
version = "1.0.0"

[project.urls]
Repository = "https://github.com/myorg/myrepo"
```

## Notes

1. GitHub Packages for Python (PyPI-compatible) is available but less common than npm or Docker. Ensure your organization has it enabled.
2. Alternatively, you can publish to the public PyPI using `twine upload dist/*` with a `PYPI_API_TOKEN` secret.

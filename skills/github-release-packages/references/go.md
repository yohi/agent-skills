# Go Publishing Reference

This reference details how to release Go modules using release-please.

## release-please Configuration

For Go projects, `release-type: go` is used.

```yaml
- uses: googleapis/release-please-action@c3fc4de07084f75a2b61a5b933069bda6edf3d5c # v4
  id: release
  with:
    release-type: go
    target-branch: main
```

## Complete Workflow Example

Go modules are typically not "published" to a registry in the same way as npm or Python. Instead, the release is the git tag itself. However, you can build binaries and attach them to the release.

```yaml
name: Release

on:
  push:
    branches:
      - main

permissions:
  contents: write
  pull-requests: write

jobs:
  release-please:
    runs-on: ubuntu-latest
    steps:
      - uses: googleapis/release-please-action@c3fc4de07084f75a2b61a5b933069bda6edf3d5c # v4
        id: release
        with:
          release-type: go
          target-branch: main

      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4
        if: ${{ steps.release.outputs.release_created }}
        with:
          ref: ${{ steps.release.outputs.tag_name }}

      - uses: actions/setup-go@0c52d547c9bc32b1aa3301fd7a9cb496313a4491 # v5
        if: ${{ steps.release.outputs.release_created }}
        with:
          go-version: '1.21'

      - name: Build binaries
        if: ${{ steps.release.outputs.release_created }}
        run: |
          mkdir -p dist
          GOOS=linux GOARCH=amd64 go build -o dist/myapp-linux-amd64 ./cmd/myapp
          GOOS=darwin GOARCH=amd64 go build -o dist/myapp-darwin-amd64 ./cmd/myapp
          GOOS=windows GOARCH=amd64 go build -o dist/myapp-windows-amd64.exe ./cmd/myapp

      - name: Upload binaries to release
        if: ${{ steps.release.outputs.release_created }}
        run: |
          gh release upload ${{ steps.release.outputs.tag_name }} dist/*
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

## Notes

1. Go releases are primarily about tagging. Once a tag is pushed, users can `go get` the module by version.
2. Building and attaching binaries is optional but recommended for CLI tools.
3. Use `goreleaser` for more sophisticated Go release automation (cross-compilation, Homebrew taps, etc.).

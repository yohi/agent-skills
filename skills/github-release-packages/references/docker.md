# Docker / ghcr.io Publishing Reference

This reference details how to publish Docker images to GitHub Container Registry (ghcr.io) using release-please.

## release-please Configuration

For Docker projects, `release-type: simple` is often used, or you can use the language-specific type if the repo contains both.

```yaml
- uses: googleapis/release-please-action@c3fc4de07084f75a2b61a5b933069bda6edf3d5c # v4
  id: release
  with:
    release-type: simple
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
          release-type: simple
          target-branch: main

      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4
        if: ${{ steps.release.outputs.release_created }}
        with:
          ref: ${{ steps.release.outputs.tag_name }}

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@f95db51fddba0c2d1ec667646a06c2ce06100226 # v3
        if: ${{ steps.release.outputs.release_created }}

      - name: Login to GitHub Container Registry
        uses: docker/login-action@343f7c4344506bcbf9b4de18042ae51996e5d3d6 # v3
        if: ${{ steps.release.outputs.release_created }}
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract metadata
        id: meta
        uses: docker/metadata-action@96383f45573cb7f253c731d3b3ab81c87ef81969 # v5
        if: ${{ steps.release.outputs.release_created }}
        with:
          images: ghcr.io/${{ github.repository }}
          tags: |
            type=semver,pattern={{version}},value=${{ steps.release.outputs.tag_name }}
            type=semver,pattern={{major}}.{{minor}},value=${{ steps.release.outputs.tag_name }}
            type=semver,pattern={{major}},value=${{ steps.release.outputs.tag_name }}

      - name: Build and push
        uses: docker/build-push-action@0565240e2d4ab88bba5387d719585280857ece09 # v5
        if: ${{ steps.release.outputs.release_created }}
        with:
          context: .
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

## Image Tagging Strategy

The example above creates three tags:
- `v1.2.3` (full version)
- `v1.2` (minor version - mutable, points to latest patch)
- `v1` (major version - mutable, points to latest minor)

This allows users to pin to different levels of stability.

## Multi-platform Builds

To build for multiple architectures (e.g., AMD64 and ARM64), add the `platforms` input to `docker/build-push-action`:

```yaml
      - name: Build and push
        uses: docker/build-push-action@0565240e2d4ab88bba5387d719585280857ece09 # v5
        if: ${{ steps.release.outputs.release_created }}
        with:
          context: .
          push: true
          platforms: linux/amd64,linux/arm64
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
```

Ensure `docker/setup-buildx-action` is used before building multi-platform images.

## Dockerfile Requirements

The workflow assumes a `Dockerfile` exists at the repository root. If it's located elsewhere, adjust the `context` and `file` inputs in `docker/build-push-action`.

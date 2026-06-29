#!/bin/bash
set -euo pipefail

# Generate workflow file for github-release-packages skill
# Usage: generate-workflow.sh [language] [package-type]
#   language: node, python, go, rust, generic
#   package-type: npm, docker, both

LANGUAGE="${1:-node}"
PACKAGE_TYPE="${2:-npm}"

# Validate arguments
case "$LANGUAGE" in
  node|python|go|rust|generic) ;;
  *) echo "Error: Invalid language '$LANGUAGE'. Valid: node, python, go, rust, generic" >&2; exit 1 ;;
esac

case "$PACKAGE_TYPE" in
  npm|docker|both) ;;
  *) echo "Error: Invalid package-type '$PACKAGE_TYPE'. Valid: npm, docker, both" >&2; exit 1 ;;
esac
# Detect default branch from remote git config or local refs
DEFAULT_BRANCH=""
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  # Try to get default branch from origin remote
  DEFAULT_BRANCH=$(git remote show origin 2>/dev/null | sed -n '/HEAD branch/s/.*: //p' || true)
  if [ -z "$DEFAULT_BRANCH" ]; then
    # Fallback to symbolic ref
    DEFAULT_BRANCH=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@' || true)
  fi
fi

# Fallback to main if not detected
if [ -z "$DEFAULT_BRANCH" ]; then
  DEFAULT_BRANCH="main"
fi

echo "Detected default branch: $DEFAULT_BRANCH" >&2

mkdir -p .github/workflows

echo "Generating workflow for language: $LANGUAGE, package-type: $PACKAGE_TYPE" >&2

# Base workflow
cat > .github/workflows/release.yml << EOF
name: Release

on:
  push:
    branches:
      - $DEFAULT_BRANCH

permissions:
  contents: write
  pull-requests: write
EOF

# Add packages: write if publishing packages
if [ "$PACKAGE_TYPE" = "npm" ] || [ "$PACKAGE_TYPE" = "docker" ] || [ "$PACKAGE_TYPE" = "both" ]; then
  echo "  packages: write" >> .github/workflows/release.yml
fi

cat >> .github/workflows/release.yml << 'EOF'

jobs:
  release-please:
    runs-on: ubuntu-latest
    steps:
      - uses: googleapis/release-please-action@c3fc4de07084f75a2b61a5b933069bda6edf3d5c # v4
        id: release
        with:
EOF

# Set release-type based on language
RELEASE_TYPE="simple"
case "$LANGUAGE" in
  node) RELEASE_TYPE="node" ;;
  python) RELEASE_TYPE="python" ;;
  go) RELEASE_TYPE="go" ;;
  rust) RELEASE_TYPE="rust" ;;
  *) RELEASE_TYPE="simple" ;;
esac

echo "          release-type: $RELEASE_TYPE" >> .github/workflows/release.yml
echo "          target-branch: $DEFAULT_BRANCH" >> .github/workflows/release.yml


# Common checkout step
cat >> .github/workflows/release.yml << 'EOF'

      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4
        if: ${{ steps.release.outputs.release_created }}
        with:
          ref: ${{ steps.release.outputs.tag_name }}
EOF

# Language-specific setup and build
if [ "$LANGUAGE" = "node" ]; then
  cat >> .github/workflows/release.yml << 'EOF'

      - uses: actions/setup-node@49933ea5288caeca8642d1e84afbd3f7d6820020 # v4
        if: ${{ steps.release.outputs.release_created }}
        with:
          node-version: '20'
          cache: 'npm'
EOF
  if [ "$PACKAGE_TYPE" = "npm" ] || [ "$PACKAGE_TYPE" = "both" ]; then
    cat >> .github/workflows/release.yml << 'EOF'
          registry-url: 'https://npm.pkg.github.com'
          scope: '@${{ github.repository_owner }}'
EOF
  fi
  cat >> .github/workflows/release.yml << 'EOF'

      - name: Install dependencies
        run: npm ci
        if: ${{ steps.release.outputs.release_created }}

      - name: Build
        run: npm run build
        if: ${{ steps.release.outputs.release_created }}
EOF
elif [ "$LANGUAGE" = "python" ]; then
  cat >> .github/workflows/release.yml << 'EOF'

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
EOF
elif [ "$LANGUAGE" = "go" ]; then
  cat >> .github/workflows/release.yml << 'EOF'

      - uses: actions/setup-go@0c52d547c9bc32b1aa3301fd7a9cb496313a4491 # v5
        if: ${{ steps.release.outputs.release_created }}
        with:
          go-version: '1.21'

      - name: Build binaries
        if: ${{ steps.release.outputs.release_created }}
        run: |
          mkdir -p dist
          GOOS=linux GOARCH=amd64 go build -o dist/myapp-linux-amd64 ./cmd/myapp
EOF
elif [ "$LANGUAGE" = "rust" ]; then
  cat >> .github/workflows/release.yml << 'EOF'

      - uses: actions-rs/toolchain@63ebf9c793f77243d78ba2e3811fc2af901075ef # v1
        if: ${{ steps.release.outputs.release_created }}
        with:
          toolchain: stable
          override: true

      - name: Build release
        if: ${{ steps.release.outputs.release_created }}
        run: cargo build --release
EOF
fi

# Package publishing steps
if [ "$PACKAGE_TYPE" = "npm" ] || [ "$PACKAGE_TYPE" = "both" ]; then
  case "$LANGUAGE" in
    node)
      cat >> .github/workflows/release.yml << 'EOF'

      - name: Publish to GitHub Packages
        run: npm publish --ignore-scripts
        env:
          NODE_AUTH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        if: ${{ steps.release.outputs.release_created }}
EOF
      ;;
    python)
      cat >> .github/workflows/release.yml << 'EOF'

      - name: Publish to GitHub Packages
        run: twine upload --repository-url https://pypi.pkg.github.com/${{ github.repository_owner }} dist/*
        env:
          TWINE_USERNAME: ${{ github.actor }}
          TWINE_PASSWORD: ${{ secrets.GITHUB_TOKEN }}
        if: ${{ steps.release.outputs.release_created }}
EOF
      ;;
    rust)
      cat >> .github/workflows/release.yml << 'EOF'

      - name: Publish to crates.io
        run: cargo publish --token ${{ secrets.CARGO_REGISTRY_TOKEN }}
        env:
          CARGO_REGISTRY_TOKEN: ${{ secrets.CARGO_REGISTRY_TOKEN }}
        if: ${{ steps.release.outputs.release_created }}
EOF
      ;;
    *)
      # generic, go: no package publish step
      ;;
  esac
fi

if [ "$PACKAGE_TYPE" = "docker" ] || [ "$PACKAGE_TYPE" = "both" ]; then
  cat >> .github/workflows/release.yml << 'EOF'

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

      - name: Build and push Docker image
        uses: docker/build-push-action@0565240e2d4ab88bba5387d719585280857ece09 # v5
        if: ${{ steps.release.outputs.release_created }}
        with:
          context: .
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
EOF
fi

# Release asset upload (common for all)
if [ "$LANGUAGE" = "node" ]; then
  cat >> .github/workflows/release.yml << 'EOF'

      - name: Pack and upload release asset
        run: |
          PACKAGE_FILE=$(npm pack)
          gh release upload ${{ steps.release.outputs.tag_name }} $PACKAGE_FILE
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        if: ${{ steps.release.outputs.release_created }}
EOF
elif [ "$LANGUAGE" = "python" ]; then
  cat >> .github/workflows/release.yml << 'EOF'

      - name: Upload release assets
        run: |
          gh release upload ${{ steps.release.outputs.tag_name }} dist/*
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        if: ${{ steps.release.outputs.release_created }}
EOF
elif [ "$LANGUAGE" = "go" ]; then
  cat >> .github/workflows/release.yml << 'EOF'

      - name: Upload binaries to release
        run: |
          gh release upload ${{ steps.release.outputs.tag_name }} dist/*
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        if: ${{ steps.release.outputs.release_created }}
EOF
fi

echo "Workflow generated at .github/workflows/release.yml" >&2

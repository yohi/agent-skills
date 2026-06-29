# Node.js / npm Publishing Reference

This reference details how to publish npm packages to GitHub Packages using release-please.

## release-please Configuration

For Node.js projects, `release-type: node` is used.

```yaml
- uses: googleapis/release-please-action@c3fc4de07084f75a2b61a5b933069bda6edf3d5c # v4
  id: release
  with:
    release-type: node
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
          release-type: node
          target-branch: main

      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4
        if: ${{ steps.release.outputs.release_created }}
        with:
          ref: ${{ steps.release.outputs.tag_name }}

      - uses: actions/setup-node@49933ea5288caeca8642d1e84afbd3f7d6820020 # v4
        if: ${{ steps.release.outputs.release_created }}
        with:
          node-version: '20'
          registry-url: 'https://npm.pkg.github.com'
          scope: '@${{ github.repository_owner }}'

      - name: Install dependencies
        run: npm ci
        if: ${{ steps.release.outputs.release_created }}

      - name: Build
        run: npm run build
        if: ${{ steps.release.outputs.release_created }}

      - name: Publish to GitHub Packages
        run: npm publish --ignore-scripts
        env:
          NODE_AUTH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        if: ${{ steps.release.outputs.release_created }}

      - name: Pack and Upload Release Asset
        run: |
          PACKAGE_FILE=$(npm pack)
          gh release upload ${{ steps.release.outputs.tag_name }} $PACKAGE_FILE
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        if: ${{ steps.release.outputs.release_created }}
```

## Important Notes

1. **Package Name**: Must be scoped to the repository owner. E.g., if the repo is `myorg/myrepo`, the package name in `package.json` should be `@myorg/myrepo` or `@myorg/something-else`. The scope (`@myorg`) must match.
2. **Registry URL**: Must be set to `https://npm.pkg.github.com`.
3. **NODE_AUTH_TOKEN**: Uses `secrets.GITHUB_TOKEN` automatically provided by GitHub Actions.
4. **npm pack**: This creates a tarball that can be attached to the GitHub Release as an asset.

## package.json Requirements

Ensure your `package.json` has:

```json
{
  "name": "@myorg/mypackage",
  "version": "1.0.0",
  "publishConfig": {
    "registry": "https://npm.pkg.github.com"
  }
}
```

## Private Packages

If the repository is private, the published package will also be private by default. Users need a PAT with `read:packages` scope to install it.

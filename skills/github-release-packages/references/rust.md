# Rust Publishing Reference

This reference details how to publish Rust crates using release-please.

## release-please Configuration

For Rust projects, `release-type: rust` is used.

```yaml
- uses: googleapis/release-please-action@c3fc4de07084f75a2b61a5b933069bda6edf3d5c # v4
  id: release
  with:
    release-type: rust
    target-branch: main
```

## Complete Workflow Example

Rust crates can be published to crates.io. If you want to publish to a private registry or GitHub Packages (if supported), adjust the `cargo publish` command.

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
          release-type: rust
          target-branch: main

      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4
        if: ${{ steps.release.outputs.release_created }}
        with:
          ref: ${{ steps.release.outputs.tag_name }}

      - uses: actions-rs/toolchain@63ebf9c793f77243d78ba2e3811fc2af901075ef # v1
        if: ${{ steps.release.outputs.release_created }}
        with:
          toolchain: stable
          override: true

      - name: Publish to crates.io
        if: ${{ steps.release.outputs.release_created }}
        run: cargo publish --token ${{ secrets.CARGO_REGISTRY_TOKEN }}
        env:
          CARGO_REGISTRY_TOKEN: ${{ secrets.CARGO_REGISTRY_TOKEN }}
```

## Cargo.toml Requirements

Ensure your `Cargo.toml` has:

```toml
[package]
name = "my-crate"
version = "1.0.0"
edition = "2021"
```

## Notes

1. Publishing to crates.io requires an API token. Store it as `CARGO_REGISTRY_TOKEN` in repository secrets.
2. GitHub Packages does not natively support Rust crates. Use crates.io or a private registry.
3. Ensure the crate name is unique on crates.io before publishing.

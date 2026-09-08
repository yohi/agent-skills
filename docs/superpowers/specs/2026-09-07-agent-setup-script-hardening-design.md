# Agent Setup Script Hardening Design

## Scope

Correct three defects in the agent-driven setup helper scripts and add focused
regression coverage. Do not change the scripts' public inputs or JSON schema.

## Changes

1. Append a real newline to `install_docs` in `analyze-repo.sh` so that the
   existing list encoder emits each discovered document as a separate JSON item.
2. Make `verify-setup.sh` classify commands as `review` by default. Only a
   command matching `safe_prefixes` is classified as `safe`; a review keyword
   continues to take precedence.
3. Make Makefile target discovery ignore variable assignments and split a
   rule's left-hand side into individual targets. Preserve the existing
   exclusion of dot-prefixed pseudo-targets.

## Regression Coverage

`test-scripts.sh` will verify:

- Multiple install documentation files produce separate `install_docs` items.
- A command not on the safe allowlist is classified as `review`.
- `:=` and `?=` variable assignments are not emitted as targets.
- A rule with multiple targets emits each target separately.

## Verification

Run the focused script tests and Bash syntax validation for both modified
scripts. Commit and push only the specification and the three intended script
files; do not stage pre-existing untracked files.

# Verification Patterns

The skill must verify the actual setup path, not just edit documentation. Use
the repository's own commands whenever possible, and add minimal smoke tests
only when existing verification does not cover setup.

## Preferred verification order

1. **Repository-defined test / build / lint commands**
   - Run the command identified by `analyze-repo.sh` / `verify-setup.sh`.
   - Prefer commands classified as `safe`. For `review` commands, use
     `--dry-run` when available or ask the user before running.
2. **Status / connection checks**
   - Verify an environment variable is set (name only, not value).
   - Run a CLI status command: `gh auth status`, `aws sts get-caller-identity`
     (only if the credential scope is read-only and pre-approved).
3. **Smoke tests**
   - Add a minimal CI job or local script only when setup is not already
     exercised by existing tests.
4. **Rerun verification**
   - Run setup-related commands a second time to detect duplicate
     installation, repeated append, or destructive overwrite.

## What to avoid

- Do not create paid production resources just to verify setup.
- Do not write production data or make irreversible account changes.
- Do not create broad credentials or unnecessary cloud infrastructure.
- Do not treat "I updated the docs" as verification.

## Side-effect classification

| Command type | Typical side effect | Recommended action |
|---|---|---|
| `npm test`, `cargo test`, `go test` | Local file writes only | Run directly |
| `npm install`, `pip install` | Downloads dependencies, writes to `node_modules` / `.venv` | Run directly on the repo copy |
| `terraform apply`, `aws deploy` | Mutates external infrastructure | Ask before running; prefer dry-run |
| Database migration scripts | Mutates database schema or data | Ask before running; prefer `--dry-run` or local fixture |

## Dry-run and local-mode options

When a tool supports a safe verification mode, prefer it:

- `terraform plan`
- `aws --dryrun` (where supported)
- `npm publish --dry-run`
- Local fixture databases instead of production databases
- `docker-compose up` with test-only services

## Failure reporting

If verification fails, report:

- The failed command and its non-secret output
- The current state of the repository
- Whether the failure blocks setup or is recoverable
- The next safe action the user can take
- Any partial modifications that were made

Do not include secret values or raw credential-bearing output.

# Verification Patterns

The skill must verify the actual setup path, not just edit documentation. Use
the repository's own commands whenever possible, and add minimal smoke tests
only when existing verification does not cover setup.

## Setup Contract v1 capability verification

Resolve each `required_capabilities` entry against
[`setup-capability-matrix.md`](setup-capability-matrix.md). The only capability
statuses are `available`, `unavailable`, and `unknown`; a missing matrix
definition is `unknown`, and its dependent item is `not_verified`.

Keep capability availability separate from the target-operation result. A
declared safety value is metadata, not execution authority: apply the shared
Policy v1 classifier and use effective safety. Only `read_only` command probes,
supported MCP stdio runtimes, fixed read-only MCP protocol operations, and a
representative MCP tool call whose Contract declares `safety: read_only` may
execute in P1. Mutating or unknown representative calls are `not_verified`
with `error_category: safety_blocked`. Safety-blocked items are `not_verified`
with `error_category: safety_blocked`.

P1 uses these probe boundaries: `mcp_runtime_probe` for MCP process startup and
fixed protocol discovery conforming to the MCP 2025-06-18 lifecycle (sending `initialize` with `protocolVersion: "2025-06-18"`, validating response, and sending outbound-only `notifications/initialized` without expecting a response line), `agent_discovery_probe` for Contract-defined
discovery, and `representative_activation_probe` for a Contract-defined
representative read-only operation. Skill `agent_action` discovery/activation,
MCP `temporary_fixture`, Plugin, Hook, and `other/custom` remain handoffs; no
invented probe is permitted. The Skill classifier can return `read_only`, but
normal verification still returns `not_verified` / `safety_blocked`, while
dry-run returns `not_executed`; no Skill `agent_action` is automatically
executed in P1. target-operation separation is required: target operation and capability assessment are
separate, and dry-run/classification must not execute or write to the target.

## MCP protocol verification

Every MCP stdio session supported by P1 uses the MCP 2025-06-18 lifecycle and
JSON-RPC 2.0 over the JSONL stdin/stdout protocol. Send an `initialize` request
with request ID `1`,
`protocolVersion: "2025-06-18"`, `capabilities: {}`, and deterministic
`clientInfo`. Validate the response, including its request ID, before sending
the outbound-only `notifications/initialized` notification. Do not wait for a
notification response or count it as an expected response.

Use `tools/list` with request ID `2` for discovery and `tools/call` with request
ID `3` for a representative tool call. Apply the applicable sequence to each
probe mode because each mode starts a new process:

```text
initialize (id 1) -> initialize response -> notifications/initialized
  -> tools/list (id 2) -> tools/list response
  -> tools/call (id 3) -> tools/call response
```

The standalone initialize probe stops after the notification, and the
standalone discovery probe stops after `tools/list`. Wait only for
response-bearing requests, match every response ID to its originating request,
and derive the expected response count from those requests. A missing response,
malformed JSON, JSON-RPC error, timeout, process failure, or response-count
mismatch is a runtime failure; a successfully written notification creates no
response requirement. Fixtures and assertions must verify the initialize
parameters, notification ordering, distinct request IDs, response-ID matching,
notification non-response behavior, and all three probe modes.

## Verification and audit status

Each verification item reports exactly one of `verified`, `not_verified`, or
`not_applicable`. Items declare `required_for_e2e: true` or `false`. Derive each
target's E2E status as follows:

- `not_applicable`: no required item remains that is not `not_applicable`.
- `verified`: every required, applicable item is `verified`.
- `not_verified`: any other result.

When `blocked_by` references an item that is not verified, do not start the
dependent probe. Record the dependent item as `not_verified` with
`reason: blocked_by_unverified_dependency` and
`error_category: dependency_blocked`. This value is recorded by the
orchestrator, not returned by the probe process. A blocked required item makes
the target E2E status `not_verified`; a blocked non-required item does not
change the target E2E status.

Audit findings use `finding_state: confirmed | candidate | unresolved` and must
include `affected_target_ids`. A `confirmed` finding blocks the affected
target's probes with `audit_blocked`. An unresolved finding affecting a target
prevents E2E sign-off until it is resolved or explicitly reviewed. Findings
must remain associated with their affected targets; unrelated targets are not
blocked.

Handoffs are defined in the Setup Contract and recorded separately in the
Verification Report. A definition includes `handoff_id`, `actor`, `action`,
`prerequisites`, `expected_outcome`, and `required_evidence`. An execution
record includes the `handoff_id`, verification item, actor, status
(`pending | completed | failed`), evidence references, and evaluation result
(`pending | success | failure | needs_review`). Evaluate handoffs in this
order:

```text
handoff completed -> evidence acquired -> required evidence evaluated
  -> evaluation result -> verification item status
```

Keep evidence as a type, summary, or external reference. Do not embed secret or
credential-bearing content in Contract frontmatter or reports.

## Dry-run invariants

Dry-run and classification must not write to the target repository, including
its `.agent-setup/` cache. Store analysis caches, snapshots, probe evidence, and
temporary fixtures only in a target-external temporary directory. Capture the
before snapshot after read-only Contract discovery and before any target write;
the declared snapshot surfaces and the target working tree must be unchanged at
the end. A `--report` output path must also be outside the target repository.

Dry-run must suppress temporary-fixture creation, MCP runtime startup,
mutating operations, and unknown operations before process start. It must not
install missing dependencies into the target, user-local environment, or a
production environment. Failure to clean temporary storage or to verify the
read-only snapshot is a `dry_run_invariant_violation` and fails the dry-run with
exit code `1`; it is not a successful `not_executed` result.

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
| `npm install`, `pip install` | Downloads dependencies, writes to `node_modules` / `.venv` | Ask the user before running; prefer a dry-run when available |
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

# Setup Capability Matrix

This is the canonical vocabulary for setup-specific capabilities in Setup
Contract v1. A capability status is exactly `available`, `unavailable`, or
`unknown`. A definition contains a description and
`generic_prerequisites.candidates`; candidates are evidence to inspect, not
availability decisions. prerequisites do not derive availability.

## Capability definitions

| Capability ID | Description | `generic_prerequisites.candidates` |
|---|---|---|
| `mcp_runtime_probe` | Start a supported MCP stdio runtime and perform the fixed read-only `initialize` and `tool_discovery` protocol operations. | `command_execution`, `repository_inspection` |
| `agent_discovery_probe` | Verify that the declared agent integration can be discovered through its Contract-defined, non-mutating discovery path. | `repository_inspection`, `command_execution` |
| `representative_activation_probe` | Verify a Contract-defined representative activation or operation without inventing a probe or mutating an unapproved surface. | `command_execution`, `structured_ask` |

The generic prerequisites are routed through
[`agent-capability-matrix.md`](agent-capability-matrix.md). They do not turn a
capability `available`; the probe result and its safety gate do that.

## P1 Target default profiles

P1 automatically verifies only read-only CLI/Service commands whose effective
safety is `read_only`, and MCP stdio runtimes when `runtime.command` and
`runtime.safety` pass Policy v1. MCP `initialize` and `tool_discovery` are fixed
read-only protocol operations. The shared classifier in
`run-target-probes.sh` owns argv normalization, exact matching, and fallback.

| Target type | P1 profile | Result when unsupported |
|---|---|---|
| `cli`, `service` | Execute a read-only command probe after the final safety gate. | `not_verified` with a Contract-defined handoff. |
| `mcp` | Start only a Policy-v1-approved stdio runtime; run protocol discovery and a representative tool call only when the Contract declares `safety: read_only`. Mutating or unknown representative calls are `not_verified` with `error_category: safety_blocked`. | `not_verified` with a Contract-defined handoff. |
| `skill` | The classifier may return `read_only`, but P1 does not automatically execute Skill `agent_action` discovery or activation; it remains a Contract-defined handoff boundary. Normal verification is `not_verified` with `error_category: safety_blocked`, and dry-run is `not_executed`. | `not_verified`; safety-blocked items use `error_category: safety_blocked`. |
| `plugin`, `hook`, `other/custom` | No invented probe. Emit only the Contract-defined handoff. | `not_verified`. |

`temporary_fixture` is accepted by the Contract shape but unsupported for
automatic P1 execution. P1 never runs mutating external operations, adapter
processes, cleanup, or temporary-fixture runtimes.

## Verification result rules

Capability availability and target verification are separate report fields. A
missing capability definition resolves to `unknown`; every dependent item is
then `not_verified` (`unknown -> not_verified`). A safety-blocked item is `not_verified` and carries
`error_category: safety_blocked`. Dry-run performs classification and reports
what would happen, but does not write to the target repository or execute a
probe. Reports and handoffs remain outside the target repository in dry-run.

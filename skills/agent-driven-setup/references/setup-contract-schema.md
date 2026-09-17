# Setup Contract v1 schema

This document is the sole schema authority for Setup Contract v1. A Contract is
the YAML frontmatter of one Markdown file; the Markdown body is explanatory
only and is never parsed as Contract data. The exact discovery declaration is:

```text
<!-- agent-setup-contract: path -->
<!-- agent-setup-contract: path/to/contract.md -->
```

The declaration must be one standalone line in the repository root `AGENTS.md`
or `README.md`. Paths are normalized repository-relative paths. Absolute paths,
`..` components, and symlink escapes are schema errors. A `null` value is the
same as an absent field; required fields may not be `null`.

## Top-level fields

| Field | Required | Shape and meaning |
| --- | --- | --- |
| `setup_contract_schema_version` | yes | Integer `1`; no other version is valid. |
| `setup_intent` | yes | Non-empty string describing intent; not a mechanical discriminator. |
| `setup_target` | yes | Non-empty map keyed by unique target IDs matching `[a-z][a-z0-9_-]*`. |
| `complexity_triggers` | yes | List, possibly empty, of unique `{id, evidence, note}` records. |
| `configuration_branches` | yes | Non-empty list of `{id, layers}` records; branch IDs and layer IDs are stable and unique in scope. |
| `installation`, `registration`, `discovery`, `activation` | yes | Maps keyed by target ID; each value is a list of static references. |
| `verification` | yes | Map containing `targets`; target keys and target types must match `setup_target`. |
| `handoffs` | yes | Map keyed by handoff ID; may be empty. |
| `external_effects` | yes | Map containing `mutation_surfaces`, a list of declared persistent effects. |

## Targets and references

| Field | Required | Shape and meaning |
| --- | --- | --- |
| `target_type` | yes | One of `skill`, `mcp`, `plugin`, `hook`, `cli`, `service`, `other/custom`. |
| `canonical_source` | yes | `{kind, value, ref_mode, ref}`; kind is `repository_path`, `url`, `registry`, or `external_resource`. |
| `canonical_source.ref_mode` | yes | `immutable`, `mutable`, or `not_applicable`; `ref` is required except for `not_applicable`, where it is forbidden. |
| `runtime` | yes | `{mode, command?, safety?}`. Mode is `process`, `in_process`, `agent_discovery`, `external_service`, or `not_applicable`. |
| `runtime.command` | process only | Non-empty argv list. Forbidden for every other runtime mode. |
| `runtime.safety` | process only | `read_only`, `mutating`, or `unknown`. It is a declaration, never execution permission; forbidden for other modes. |

All target and verification references use the target ID as their key. A phase
reference is `{id, reference, verification_item_id?, handoff_id?}`. Its
`reference` is either `{kind: path, path, symbol?}` or
`{kind: external_resource, value}`. Optional references must resolve to an item
of the same target or to a Contract handoff.

## Configuration layers

`configuration_branches[*].layers[*].kind` is a closed v1 enum:
`choice`, `installer`, `cli`, `env`, `settings`, `generated_config`,
`registration`, `discovery`, `runtime_consumer`, `activation`,
`representative_operation`, `verification`. Unknown kinds are schema errors.

The locator fields are exact: `env` requires `key` and may use `path`; `cli`
requires `option` and may use `path`; `generated_config` requires `path` and
`key`; `runtime_consumer` requires `path` and `symbol`; all other kinds require
only optional `path`, `key`, and `symbol`. No undeclared locator field is
allowed. `path` is repository-relative; `key`, `symbol`, and `option` are
non-empty strings.

## Verification items and probes

`verification.targets[*].items` is non-empty. Each item has unique `id`,
`phase`, `target_type`, and `required_for_e2e`; `phase` is one of
`installation`, `registration`, `discovery`, `activation`, `runtime_start`,
`initialize`, `tool_discovery`, or `representative_operation`. `blocked_by`
contains same-target item IDs only and must be acyclic. `required_capabilities`
is optional, non-null, and contains unique item-local IDs matching
`[a-z][a-z0-9_-]*`. Spec 1 does not resolve these IDs through a capability
matrix or assess availability.

Required items have a probe. A `command` probe has a non-empty argv list and
required `safety` in `read_only|mutating|unknown`; an `agent_action` adapter
has the same required safety enum. These declarations do not authorize
execution. An `mcp_request` is `initialize`, `tool_discovery`, or
`representative_tool_call`. The first two have no safety fields. A
`representative_tool_call` requires `tool`, object `arguments`, and
`safety: read_only|mutating|unknown`; a temporary-fixture mode additionally
requires `mutation_surface_id` referring to an external, snapshot-required,
cleanup-required surface. P1 does not automatically execute temporary fixtures.

## Mutation surfaces

Each `external_effects.mutation_surfaces[*]` has unique `id`, `scope`, `kind`,
`value`, `snapshot`, and boolean `cleanup_required`. Scope is `repository`,
`user_local`, `global`, or `external`; kind is `path`, `glob`, or
`external_resource`; snapshot is `required` or `not_supported`. Repository
paths are root-relative, user-local values are `$HOME`-relative, global values
are generic identifiers, and external values are resource identifiers.

The effective Probe Safety Policy v1 and argv classifier are owned by
`run-target-probes.sh`; Spec 1 only validates Contract shape and enums. Its
`--classify-only` interface is the sole dry-run reuse mechanism. PyYAML is a
runtime dependency (`PyYAML>=6.0,<7`); callers preflight it and report
`dependency_unavailable` with exit 3 rather than installing it.

## Normative nested field tables

The following tables are the parser-facing expansion of the summaries above.
They are normative; omitted optional fields are absent, and `null` is invalid
for every required field and is equivalent to absence for optional fields.

### Target and canonical-source fields

| Field | Required | Discriminator / shape | Path and reference semantics |
| --- | --- | --- | --- |
| `setup_target.<id>` | yes | Map key `<id>` matches `[a-z][a-z0-9_-]*` | Stable target ID used by every target reference. |
| `target_type` | yes | `skill`, `mcp`, `plugin`, `hook`, `cli`, `service`, `other/custom` | Selects the target probe profile. |
| `canonical_source.kind` | yes | `repository_path`, `url`, `registry`, `external_resource` | Selects the meaning of `value`. |
| `canonical_source.value` | yes | Non-empty string | For `kind: repository_path`, a normalized path relative to the repository root; absolute paths, `..` components, symlink escapes outside the repository, and empty values are forbidden. Other kinds use a non-empty kind-specific canonical identifier. |
| `canonical_source.ref_mode` | yes | `immutable`, `mutable`, `not_applicable` | Declares reference mutability. |
| `canonical_source.ref` | conditional | Required for immutable/mutable; forbidden for not_applicable | `null` is never a valid substitute. |
| `runtime.mode` | yes | `process`, `in_process`, `agent_discovery`, `external_service`, `not_applicable` | Selects runtime handling. |
| `runtime.command` | process only | Non-empty string argv list; forbidden otherwise | Declaration only; no execution permission. |
| `runtime.safety` | process only | `read_only`, `mutating`, `unknown`; forbidden otherwise | Declaration only; effective policy belongs to the executor. |

### Configuration-layer fields

| `kind` discriminator | Required fields | Optional fields | Exact path/reference rule |
| --- | --- | --- | --- |
| `env` | `id`, `kind`, `key` | `path` | `path` is repository-relative; `key` is non-empty. |
| `cli` | `id`, `kind`, `option` | `path` | `option` is non-empty. |
| `generated_config` | `id`, `kind`, `path`, `key` | none | `path` is repository-relative. |
| `runtime_consumer` | `id`, `kind`, `path`, `symbol` | none | `path` is repository-relative; `symbol` is non-empty. |
| `choice`, `installer`, `settings`, `registration`, `discovery`, `activation`, `representative_operation`, `verification` | `id`, `kind` | `path`, `key`, `symbol` | Any present strings are non-empty; any present `path` is repository-relative. |

Layer `kind` is a closed v1 discriminator. Unknown kinds and undeclared fields
are schema errors; the parser must not invent a locator shape for them.

### Phase-reference fields

| Field | Required | Shape and semantics |
| --- | --- | --- |
| `<phase>.<target_id>[]` | yes | List keyed by an existing target ID. |
| `id` | yes | Non-empty and unique within the phase list. |
| `reference` | yes | Exactly `{kind: path, path, symbol?}` or `{kind: external_resource, value}`. |
| `reference.path` | for `kind: path` | Normalized repository-relative path; no absolute path, `..`, or symlink escape. |
| `reference.value` | for `kind: external_resource` | Non-empty external resource identifier. |
| `verification_item_id` | no | If present, resolves to an item of the same target. |
| `handoff_id` | no | If present, resolves to a key in `handoffs`. |

### Verification and probe fields

| Field | Required | Shape / discriminator |
| --- | --- | --- |
| `verification.targets.<target_id>` | yes | Key and `target_type` must match `setup_target`. |
| `items` | yes | Non-empty list; item IDs are unique within the target. |
| `item.phase` | yes | `installation`, `registration`, `discovery`, `activation`, `runtime_start`, `initialize`, `tool_discovery`, or `representative_operation`. |
| `blocked_by` | no | Same-target item ID list; unknown IDs, self references, and cycles are errors. |
| `required_capabilities` | no | Non-null list of unique IDs matching `[a-z][a-z0-9_-]*`; no matrix lookup in Spec 1. |
| `probe.kind` | required for required item | `command`, `mcp_request`, or `agent_action`. |
| `command` | command probe | Non-empty string `argv`; required `safety` is `read_only`, `mutating`, or `unknown`. |
| `agent_action` | agent-action probe | `action` is `discovery` or `activation`; `adapter` is required. Adapter is `{kind: command}` with a non-empty string list `argv`, `stdin` set to `prompt` or `empty`, and `safety` set to `read_only`, `mutating`, or `unknown`. `prompt` is required only for `stdin: prompt` and forbidden for `empty`. |
| `mcp_request` | MCP probe | `request` is `initialize`, `tool_discovery`, or `representative_tool_call`; any declared `safety` uses `read_only`, `mutating`, or `unknown`. |
| initialize/tool discovery fields | fixed operations | `tool`, `arguments`, `safety`, and `mutation_surface_id` are forbidden. |
| representative call fields | representative call | `tool` and object `arguments` are required; `safety` is `read_only`, `mutating`, or `unknown`. A read-only call has no `mutation_surface_id`; a temporary-fixture mode is distinguished by its required `mutation_surface_id`. |

Safety declarations never authorize execution. The classifier and effective
policy remain owned by `run-target-probes.sh`.

### Mutation-surface fields

| Field | Required | Discriminator / scope semantics |
| --- | --- | --- |
| `id` | yes | Unique non-empty surface ID. |
| `scope` | yes | `repository`, `user_local`, `global`, or `external`. |
| `kind` | yes | `path`, `glob`, or `external_resource`; must match the scope value domain. |
| `value` | yes | Repository path is root-relative; user-local value is `$HOME`-relative; global value is a generic identifier; external value is a resource identifier. |
| `snapshot` | yes | `required` or `not_supported`. |
| `cleanup_required` | yes | Boolean declaration; it is not a cleanup command or permission. |

An eligible temporary-fixture surface is specifically
`scope: external`, `kind: external_resource`, `snapshot: required`, and
`cleanup_required: true`. P1 accepts its declaration but does not execute it.

### Handoff fields

| Field | Required | Shape and semantics |
| --- | --- | --- |
| `handoffs.<id>` | yes when referenced | Map keyed by stable handoff ID. |
| `actor` | yes | `agent`, `user`, or `external`. |
| `action` | yes | Non-empty action description. |
| `prerequisites` | yes | List of prerequisite IDs or references. |
| `expected_outcome` | yes | Non-empty observable outcome. |
| `required_evidence` | yes | List of `{type, summary}`; evidence content and secrets are not embedded. |
| phase/item `handoff_id` | conditional | Must resolve to a defined handoff; no handoff is invented during parsing. |

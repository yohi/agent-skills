---
name: temporary-credential-agent
description: Use when an AI agent must investigate or change registered AWS, Cloudflare, Grafana, or HCP Terraform resources using temporary credentials without exposing parent credentials, Bitwarden Secrets Manager access tokens, or temporary secret values.
---

# Temporary Credential Agent

## Overview

Use this skill to request and consume temporary cloud credentials through a
registered credential broker. The broker, not the AI agent, reads Bitwarden
Secrets Manager, issues and revokes credentials, and runs an allow-listed
service operation. Secret values never cross the broker boundary.

This skill is a policy and invocation contract. It does not set up Bitwarden,
roles, service accounts, target registration, or the human approval channel.

## Applicability and hard boundaries

Use only registered environments for AWS, Cloudflare, Grafana Cloud,
self-hosted Grafana, and HCP Terraform on Linux or macOS. Do not use `bw`.
Use `bws` only inside the broker's isolated issuance boundary.

Do not request, print, persist, inspect, or return any of the following:

- `BWS_ACCESS_TOKEN`, parent credentials, or temporary credential values
- arbitrary shell commands, environment dumps, process listings, or debug logs
- secret, password, private-key, or authorization-header values
- account, organization, project, billing, IAM/RBAC, user, role, or service
  account changes
- security or audit disablement, credential-broker changes, or credential and
  privilege-principal creation

If an operation needs any prohibited action, stop before credential issuance
and report the blocked operation. Do not suggest an alternate credential or a
broader permission.

## Request contract

Collect these fields before asking the broker to issue anything:

| Field | Requirement |
|---|---|
| Service | One supported service |
| Environment | A registered environment name |
| Work | A concrete, allow-listed operation |
| Resource | Exact account, zone, stack, organization, or workspace scope |
| Access mode | `readonly` or `writable`; absent or ambiguous means `readonly` |
| TTL | Requested duration; absent means 1 hour |
| Approval | Required only for `writable`; binds one session |

Ask for missing service, environment, work, or resource details. Do not issue a
credential while any are ambiguous. Reject an unregistered target before the
broker reads Bitwarden.

## Authorization decision

1. Normalize an omitted or unclear access mode to `readonly`, and an omitted
   TTL to one hour.
2. Classify the requested operation with the service profile in
   [service-profiles.md](references/service-profiles.md). A profile must map it
   to exact allowed operations and a resource scope; otherwise reject it.
3. For `readonly`, issue only the smallest profile-supported read permission.
   Readonly work is autonomous and must not require human approval.
4. For `writable`, require a verifiable human approval bound to the current
   work ID, service, resources, allowed operations, and expiry. A missing,
   expired, reused, or mismatched approval rejects the request.
5. If a read operation needs a write permission, stop and request a new
   writable approval. Never upgrade, retry, or fall back automatically.
6. If the exact scope cannot be represented, reject the request. If the exact
   TTL cannot be represented, reject it unless the service profile explicitly
   declares a safe exception. A `shorter_ttl_allowed` exception requires the
   service to report a shorter value that still permits the work; record that
   server-applied value in `ttl_effective`. A `no_server_ttl` profile must use
   the pending-record cleanup and recovery path and record
   `ttl_effective=not_applicable`. Never silently issue a broader scope or a
   credential valid longer than requested.

## Broker-only credential lifecycle

The AI-visible caller sends a structured request and receives only sanitized
results. The broker performs this sequence:

1. Recover outstanding issuance-intent, pending-revocation, and residue
   records before handling new work.
2. Validate registration, authorization, approval, operation allow-list, and
   requested TTL. Fail closed on any validation, Bitwarden, or service API
   error. For every rejection before issuance, write a `request_rejected`
   audit event before returning. Include only sanitized request fields,
   authorization context, and the failure category and reason; never include
   secret values or raw approval/error payloads. Set issuance and revocation
   status to `not_issued`.
3. Persist a secret-free issuance-intent record with `state=pre_issuance`
   before reading the parent credential or calling a credential-issuance API.
   The record must contain the request and authorization context, `work_id`,
   and its requested TTL, but no credential value.
4. In the isolated issuer, use `bws` read operations only to obtain the parent
   credential for `<service>-<environment>`. Do not pass the BWS token or
   parent credential to the worker.
5. Issue a service-native temporary or revocable credential with the exact
   operation and resource scope. Set a server-side expiry when supported. Mark
   the intent `issued_unconfirmed`, reconcile the service state, and associate
   `credential_identifier` before persisting the pending-revocation record.
   The pending record must use the exact fields from `audit-schema.md`:
   `work_id`, `service`, `environment`, `resource`, `credential_identifier`,
   `created_at`, `expires_at`, `last_revocation_attempt_at`,
   `last_revocation_result`, and `recovery_status`. Transition to
   `credential_tracked` only after that record is durable. If issuance or
   reconciliation is uncertain, transition to `recovery_pending`, do not start
   the worker, and retain the intent for recovery. Never persist a secret value.
6. Inject the temporary credential into one short-lived, allow-listed service
   CLI/API worker. The worker must not launch arbitrary commands or expose its
   environment. Use the credential only for the approved operation.
7. Sanitize result, stdout, stderr, errors, service responses, environment
   dumps, command arguments, authorization headers, and credential JSON fields
   before returning or persisting them. If sanitization cannot be confirmed,
   discard the affected content, fail closed with `redaction_failure`, and
   continue directly to cleanup without returning raw output. Do not retry a
   write whose result is uncertain; return `outcome_unknown` instead.
8. In a `finally`-equivalent cleanup path, transition to `cleanup_pending`,
   revoke or delete the credential, update the pending record, and write an
   audit event. A revocation failure is a `credential_residue` error, never
   success. Cleanup is required even when sanitization fails.

The lifecycle states are `pre_issuance`, `issued_unconfirmed`,
`credential_tracked`, `worker_running`, `cleanup_pending`, `revoked`, `expired`,
`rejected`, `recovery_pending`, and `credential_residue`. The allowed ordering
is defined in [audit-schema.md](references/audit-schema.md); `revoked` and
`expired` are the recoverable terminal outcomes.

For a crash or forced termination, server-side TTL is the last safety layer.
At the next broker start, inspect every `issued_unconfirmed`,
`recovery_pending`, and pending-revocation record, confirm its state at the
service, associate a credential identifier when possible, and use the profile's
dedicated recovery `revoke_operation`. Retry only the transient conditions
declared by that operation's `revoke_retry_policy`; never reuse a user-requested
writable operation retry. Retain unresolved records for further recovery.

## Result contract

Return this shape to the AI agent:

```text
work_id, service, environment, resource, access_mode, status,
sanitized_result_or_error, revocation_status, credential_residue
```

`status` is one of `completed`, `rejected`, `failed`, `timed_out`, or
`outcome_unknown`. `revocation_status` is `revoked`, `expired`, `not_issued`,
or `failed`. Report a residue by identifier and expiry only, never its value.

## Audit and retention

Write structured, append-only audit events to a broker-owned location that the
AI worker cannot alter. Retain them for at least 90 days, then allow automated
deletion. Use [audit-schema.md](references/audit-schema.md) for required fields
and redaction rules.

## Verification checklist

Before considering a workflow safe, verify:

- readonly defaults to one hour and does not receive write permissions;
- writable issuance requires a scope-bound, unexpired human approval;
- every pre-issuance rejection creates a secret-free `request_rejected` audit
  event with `not_issued` statuses;
- issuance intent is durable before issuance, and pending-revocation tracking
  uses the canonical schema before worker start;
- requested TTL is exact unless an explicit profile exception records the
  effective value in `ttl_effective`;
- no credential value appears in model-visible output, worker output, audit
  data, pending records, or normal process environments;
- cleanup runs after success, failure, timeout, interruption, and sanitization
  failure, using the dedicated recovery revoke policy; and
- failed cleanup remains visible as a tracked residue until confirmed revoked
  or expired.

Use [evaluation-matrix.md](references/evaluation-matrix.md) to exercise the
acceptance scenarios before operating against a production environment.

## Common mistakes

| Mistake | Required response |
|---|---|
| Treating vague access as writable | Default to readonly. |
| Asking approval for readonly work | Do not; require only complete scope. |
| Broadening a token when fine scope fails | Reject the request. |
| Returning a token so the agent can run a command | Keep it in the broker worker. |
| Retrying an uncertain write | Return `outcome_unknown`; obtain human direction. |
| Calling cleanup failure a normal work failure | Return `credential_residue` and retain recovery state. |

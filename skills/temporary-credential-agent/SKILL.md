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
6. If the exact scope or TTL cannot be represented, reject the request. Never
   silently issue a broader scope or a credential valid longer than requested.

## Broker-only credential lifecycle

The AI-visible caller sends a structured request and receives only sanitized
results. The broker performs this sequence:

1. Recover outstanding credential records before handling new work.
2. Validate registration, authorization, approval, operation allow-list, and
   requested TTL. Fail closed on any validation, Bitwarden, or service API
   error.
3. In the isolated issuer, use `bws` read operations only to obtain the parent
   credential for `<service>-<environment>`. Do not pass the BWS token or
   parent credential to the worker.
4. Issue a service-native temporary or revocable credential with the exact
   operation and resource scope. Set a server-side expiry when supported.
5. Persist a pending-revocation record containing only work ID, service,
   credential identifier, target, creation time, expiry, and last revocation
   result. Never persist a secret value.
6. Inject the temporary credential into one short-lived, allow-listed service
   CLI/API worker. The worker must not launch arbitrary commands or expose its
   environment. Use the credential only for the approved operation.
7. Sanitize result, stdout, stderr, and errors before returning them. Do not
   retry a write whose result is uncertain; return `outcome_unknown` instead.
8. In a `finally`-equivalent cleanup path, revoke or delete the credential,
   update the pending record, and write an audit event. A revocation failure is
   a `credential_residue` error, never success.

For a crash or forced termination, server-side TTL is the last safety layer.
At the next broker start, inspect every pending record, confirm its state at
the service, retry revocation when valid, and retain unresolved records for
further recovery.

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
- no credential value appears in model-visible output, worker output, audit
  data, pending records, or normal process environments;
- cleanup runs after success, failure, timeout, and interruption; and
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

# Acceptance Evaluation Matrix

Use this matrix before operating against a production environment. Run every
scenario against registered fixture environments with synthetic parent
credentials and disposable service resources. Record identifiers, statuses, and
event order only; never record credential values or secret-bearing output.

The broker must pass every applicable scenario. A scenario is not applicable
only when the registered service profile cannot support the capability under
test; document that profile limitation rather than marking the scenario passed.
See [service-profiles.md](service-profiles.md) for service boundaries and
[audit-schema.md](audit-schema.md) for record and redaction requirements.

## Test harness requirements

- A registered fixture exists for each service profile under test.
- The fixture service can perform one safe read, one scoped write, and a
  credential state check without using production resources.
- The broker can inject failures after issuance, during execution, and during
  revocation.
- Test observers can inspect sanitized request decisions, permission actions,
  pending-record state, audit events, and event order without reading secrets.
- Approval fixtures cover valid, missing, expired, reused, and mismatched
  approvals.

## Acceptance scenarios

| ID | Scenario and setup | Expected broker behavior | Evidence for pass |
|---|---|---|---|
| EVAL-01 | Submit a complete read request without `access_mode` or `TTL`. | Normalize the request to `readonly` with a one-hour TTL. Do not request approval or grant write permissions. | The decision record contains the normalized mode and TTL; the effective permission set contains read actions only. |
| EVAL-02 | Omit `service`, `environment`, `work`, or `resource`, or use an unregistered target. | Reject before the broker reads Bitwarden or issues a credential. | No issuance or Bitwarden-read event exists, and the sanitized error identifies the missing or unregistered input. |
| EVAL-03 | Request a profile-supported readonly operation with an exact resource scope. | Issue only the smallest profile-supported read permission. Readonly work proceeds without human approval. | The service action and resource scope match the operation map; no write action or approval check is required. |
| EVAL-04 | Request a profile-supported writable operation with a valid approval bound to the current work ID, service, resource, operations, and expiry. | Issue a credential with exactly the approved operation and resource scope. | Approval binding, effective scope, and expiry match the request; the worker completes only the approved operation. |
| EVAL-05 | Repeat EVAL-04 with a missing, expired, reused, or mismatched approval. | Reject before issuance. Do not retry, broaden permissions, or use an earlier approval. | No credential identifier is issued; the rejection reason identifies the failed approval condition without exposing approval secrets. |
| EVAL-06 | Request a resource scope or TTL that the service profile cannot represent exactly. | Reject instead of issuing a broader scope or a credential valid longer than requested. | The decision records the unsupported scope or TTL; no broader permission, longer expiry, or fallback credential exists. |
| EVAL-07 | Use synthetic markers in the parent credential and temporary credential while executing an approved operation. | Keep both credential values inside the isolated issuer and short-lived worker boundary. | The markers are absent from AI-visible results, worker output, audit data, pending records, and normal process environments. |
| EVAL-08 | Start a worker after credential issuance and force a crash before execution begins. | Persist the pending-revocation record before worker execution; do not start work without that record. | Event order shows record persistence before worker start, and the record contains only the fields permitted by `audit-schema.md`. |
| EVAL-09 | Return normal output, stderr, an error, and a service response containing credential-like values or authorization headers. | Sanitize every AI-visible and persistent output. If sanitization cannot be confirmed, fail closed. | No secret-bearing value remains; an unconfirmed sanitization path produces only a redaction-failure category and an audit event. |
| EVAL-10 | Run successful readonly work, failed work, a timeout, and a failed writable operation. | Revoke or delete the temporary credential in every cleanup path and update the pending record. A revocation failure is `credential_residue`, not success. | Each terminal path has a cleanup attempt and audit event; failed cleanup remains tracked by identifier and expiry. |
| EVAL-11 | Terminate the broker after issuance and before cleanup, then restart it. | Recover every pending record, check credential state at the service, retry valid revocation, and retain unresolved records. | Recovery event order and final record state show confirmation, successful revocation, expiry, or retained residue. |
| EVAL-12 | Cause a writable operation to time out or lose its connection after the service may have applied the change. | Do not retry the write. Return `outcome_unknown` and use the profile state check only for observation. | No second write action occurs; the result status is `outcome_unknown` and includes no credential value. |
| EVAL-13 | Complete, reject, fail, time out, and produce an unknown-outcome request. | Return the documented result fields and only the allowed status and revocation-status values. | The response contains `work_id`, service, environment, resource, access mode, status, sanitized result or error, revocation status, and residue; residue contains only its identifier and expiry. |
| EVAL-14 | Generate audit events for issuance, execution, failure, revocation, and recovery. | Write append-only records to the broker-owned location and retain them for at least 90 days. | Events contain the required schema fields, exclude secrets and reversible encodings, and cannot be altered by the AI worker. |

## Test record

For each scenario, retain the following secret-free evidence:

```text
scenario_id, fixture, work_id, observed_status, observed_revocation_status,
event_order, effective_scope, failure_category, residue_identifier,
residue_expiry, pass_or_fail, reviewer, observed_at
```

Do not attach raw worker output, environment dumps, command arguments, approval
payloads, credential material, or unredacted service errors to the test record.

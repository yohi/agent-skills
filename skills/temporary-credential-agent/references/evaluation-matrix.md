# Acceptance Evaluation Matrix

Run the scenarios against mocks first and isolated, registered fixture
environments second. Never use production secrets as test fixtures. Use
synthetic parent credentials and disposable service resources. Record
identifiers, statuses, and event order only; never record credential values or
secret-bearing output.

The broker must pass every applicable scenario. A scenario is not applicable
only when the registered service profile cannot support the capability under
test; document that profile limitation rather than marking the scenario passed.
See [service-profiles.md](service-profiles.md) for service boundaries and
[audit-schema.md](audit-schema.md) for record and redaction requirements.

## Test harness requirements

- A registered fixture exists for each service profile under test.
- The fixture service can perform one safe read, one scoped write, and a
  credential state check without using production resources.
- The broker can inject failures after issuance, during execution, during
  sanitization, and during revocation, and can interrupt issuance reconciliation
  before credential tracking is durable.
- Test observers can inspect sanitized request decisions, permission actions,
  pending-record state, audit events, and event order without reading secrets.
- Approval fixtures cover valid, missing, expired, reused, and mismatched
  approvals.

## Acceptance scenarios

| ID | Scenario and setup | Expected broker behavior | Evidence for pass |
|---|---|---|---|
| EVAL-01 | Submit a complete read request without `access_mode` or `TTL`. | Normalize the request to `readonly` with a one-hour TTL. Do not request approval or grant write permissions. | The decision record contains the normalized mode and TTL; the effective permission set contains read actions only. |
| EVAL-02 | Omit `service`, `environment`, `work`, or `resource`, or use an unregistered target. | Reject before the broker reads Bitwarden or issues a credential, and write a `request_rejected` audit event. | No issuance or Bitwarden-read event exists. The rejection event has `issuance_status=not_issued`, `revocation_status=not_issued`, sanitized request and authorization context, and the missing-input or unregistered-target category and reason. |
| EVAL-03 | Request a profile-supported readonly operation with an exact resource scope. | Issue only the smallest profile-supported read permission. Readonly work proceeds without human approval. | The service action and resource scope match the operation map; no write action or approval check is required. |
| EVAL-04 | Request a profile-supported writable operation with a valid approval bound to the current work ID, service, resource, operations, and expiry. | Issue a credential with exactly the approved operation and resource scope. | Approval binding, effective scope, and expiry match the request; the worker completes only the approved operation. |
| EVAL-05 | Repeat EVAL-04 with a missing, expired, reused, or mismatched approval. | Reject before issuance, write a `request_rejected` audit event, and do not retry, broaden permissions, or use an earlier approval. | No credential identifier is issued. The event identifies the failed approval condition with sanitized authorization context and no approval secret. |
| EVAL-06 | Request a resource scope or TTL that the service profile cannot represent exactly. | Reject instead of issuing a broader scope or a credential valid longer than requested. An explicitly declared `shorter_ttl_allowed` exception may proceed only when the service reports a shorter value that still permits the work; a `no_server_ttl` profile must use pending-record cleanup and recovery. | For rejection, the decision records the unsupported scope or TTL and no broader permission, longer expiry, or fallback credential exists. For an allowed exception, `ttl_requested` and the server-applied `ttl_effective` are recorded and `ttl_effective` is no longer than requested. |
| EVAL-07 | Use synthetic markers in the parent credential and temporary credential while executing an approved operation. | Keep both credential values inside the isolated issuer and short-lived worker boundary. | The markers are absent from AI-visible results, worker output, audit data, pending records, normal process environments, the AI caller, and unrelated child processes. |
| EVAL-08 | Persist issuance intent, then force a crash before issuance, after a possible issuance response but before credential-identifier association, and after tracking but before worker execution. | Persist intent before issuance. Reconcile `issued_unconfirmed`, associate `credential_identifier`, and persist the complete pending-revocation record before worker execution; do not start work without that record. | Event order shows `pre_issuance` before issuance, `issued_unconfirmed` before `credential_tracked`, and the canonical `audit-schema.md` fields before worker start. An uncertain path remains recoverable and contains no secret. |
| EVAL-09 | Return normal output, stderr, an error, and a service response containing credential-like values or authorization headers; then make sanitization unconfirmable after worker execution. | Sanitize every AI-visible and persistent output. If sanitization cannot be confirmed, discard the affected content, fail closed with `redaction_failure`, revoke or delete the credential, update the pending record, and complete cleanup before returning the error. | No secret-bearing value remains. The terminal event records only `failure_category=redaction_failure` plus secret-free metadata; a cleanup failure records `credential_residue` with identifier and expiry and emits the cleanup audit event. |
| EVAL-10 | Run successful readonly work, failed work, a timeout, a failed writable operation, and a sanitization failure after worker execution. | Revoke or delete the temporary credential in every cleanup path, including the redaction-failure path, and update the pending record. A revocation failure is `credential_residue`, not success. | Each terminal path has a cleanup attempt and audit event; failed cleanup remains tracked by identifier and expiry. |
| EVAL-11 | Terminate the broker after issuance and before cleanup, then restart it. | Recover every `issued_unconfirmed`, `recovery_pending`, and pending record, check credential state at the service, and invoke the distinct recovery `revoke_operation`. Retry only conditions declared by `revoke_retry_policy`; retain unresolved records and never replay a user write. | Recovery event order identifies the recovery revoke operation and its allowed retry condition. Final record state shows confirmation, successful revocation, expiry, or retained residue. |
| EVAL-12 | Cause a writable operation to time out or lose its connection after the service may have applied the change. | Do not retry the write. Return `outcome_unknown` and use the profile state check only for observation. | No second write action occurs; the result status is `outcome_unknown` and includes no credential value. |
| EVAL-13 | Complete, reject, fail, time out, and produce an unknown-outcome request. | Return the documented result fields and only the allowed status and revocation-status values. | The response contains `work_id`, service, environment, resource, access mode, status, sanitized result or error, revocation status, and residue; residue contains only its identifier and expiry. |
| EVAL-14 | Generate audit events for pre-issuance rejection, issuance, execution, failure, revocation, and recovery. | Write append-only records to the broker-owned location and retain them for at least 90 days. | Rejection events use `request_rejected`, `issuance_status=not_issued`, and `revocation_status=not_issued`; all events contain the required schema fields, exclude secrets and reversible encodings, and cannot be altered by the AI worker. |
| EVAL-15 | Request an operation not present in the registered operation map or a prohibited account, IAM/RBAC, credential, or security-control change. | Reject before any target-service API invocation or credential issuance. Do not suggest a broader permission or alternate credential. | No target-service call, Bitwarden read, or credential identifier exists; the rejection audit event is secret-free and marked `not_issued`. |
| EVAL-16 | Exercise one safe read, one scoped write, revocation, and audit recording for every supported service profile. | Enforce the profile's exact resource boundary, operation map, credential kind, and cleanup behavior. | Each applicable profile completes its read, approved write, revocation, and audit paths; unsupported capabilities are documented as profile limitations. |
| EVAL-17 | Run the supported-service happy and cleanup paths on Linux and macOS. | Complete the same authorization, worker isolation, cleanup, and recovery behavior on both supported platforms. | Platform-specific runs have matching secret-free outcomes and cleanup evidence. |
| EVAL-18 | Request a readonly operation whose implementation would require a write permission. | Reject or require a new writable request and approval; never escalate, retry, or fall back automatically. | No write call, issuance, or automatic escalation occurs for the readonly request. |

## Test record

For each scenario, retain the following secret-free evidence:

```text
scenario_id, fixture, work_id, observed_status, observed_revocation_status,
intent_state, event_order, effective_scope, ttl_requested, ttl_effective,
failure_category, residue_identifier, residue_expiry, pass_or_fail, reviewer,
observed_at
```

Do not attach raw worker output, environment dumps, command arguments, approval
payloads, credential material, or unredacted service errors to the test record.

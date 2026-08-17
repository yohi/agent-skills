# Audit and Recovery Records

Store records in a broker-owned, structured append-only location. Do not store
`BWS_ACCESS_TOKEN`, credential values, authorization headers, environment dumps,
service responses, command strings that embed secrets, or reversible secret
encodings.

## Audit event

Record the following fields when applicable:

```text
timestamp, work_id, event_type, service, environment, resource,
access_mode, requested_operations, effective_operations, ttl_requested,
ttl_effective, approval_id, approver_id, credential_identifier,
issuance_status, intent_state, execution_status, failure_category,
failure_reason, revocation_status
```

Use `credential_residue` as a distinct failure category when revocation cannot
be confirmed. Use `request_rejected` with `issuance_status=not_issued` and
`revocation_status=not_issued` for every rejection before issuance. Record the
applicable request and authorization context, plus a short secret-free failure
category and reason. This includes missing input, unregistered targets, invalid
approvals, validation failures, Bitwarden errors, and service API errors. Never
record raw request payloads, approval payloads, or external error text that may
contain secrets. Audit records are retained for at least 90 days.

## Pending-revocation record

Persist before worker execution:

```text
work_id, service, environment, resource, credential_identifier,
created_at, expires_at, last_revocation_attempt_at,
last_revocation_result, recovery_status
```

Delete this operational record only after service-side revocation or expiry is
confirmed. Keep its secret-free audit trail according to the retention policy.

## Issuance intent and state transitions

Persist a secret-free issuance-intent record before reading a parent credential
or calling a credential-issuance API. It contains the request and authorization
context, `work_id`, and `intent_state`, but never a credential value. Use these
states so an interruption between issuance and tracking remains recoverable:

```text
pre_issuance -> rejected
pre_issuance -> issued_unconfirmed -> credential_tracked
credential_tracked -> worker_running -> cleanup_pending
cleanup_pending -> revoked | expired | credential_residue
issued_unconfirmed -> recovery_pending
```

After an issuance response, reconcile the service state and associate
`credential_identifier` before persisting the complete pending-revocation
record. Do not start the worker until that record is durable. Keep
`issued_unconfirmed`, `recovery_pending`, and `credential_residue` records for
recovery; `revoked` and `expired` are the recoverable terminal outcomes.

## Sanitization

Before any AI-visible or persistent output, remove known `BWS_ACCESS_TOKEN`,
parent, and temporary secret values. Sanitize results, stdout, stderr, errors,
service responses, `Authorization` headers, environment-variable dumps,
credential JSON fields, and command arguments. If sanitization cannot be
confirmed, discard the affected content, fail closed, and record only
`failure_category=redaction_failure` with secret-free audit metadata. Never
persist the unsanitized content.

# Audit and Recovery Records

Store records in a broker-owned, structured append-only location. Do not store
credential values, authorization headers, environment dumps, command strings
that embed secrets, or reversible secret encodings.

## Audit event

Record the following fields when applicable:

```text
timestamp, work_id, event_type, service, environment, resource,
access_mode, requested_operations, effective_operations, ttl_requested,
ttl_effective, approval_id, approver_id, credential_identifier,
issuance_status, execution_status, failure_category, revocation_status
```

Use `credential_residue` as a distinct failure category when revocation cannot
be confirmed. Audit records are retained for at least 90 days.

## Pending-revocation record

Persist before worker execution:

```text
work_id, service, environment, resource, credential_identifier,
created_at, expires_at, last_revocation_attempt_at,
last_revocation_result, recovery_status
```

Delete this operational record only after service-side revocation or expiry is
confirmed. Keep its secret-free audit trail according to the retention policy.

## Sanitization

Before any AI-visible or persistent output, remove known parent and temporary
secret values. Also suppress `Authorization` headers, environment-variable
dumps, credential JSON fields, command arguments, and service errors that
contain them. If sanitization cannot be confirmed, fail closed and record only
the redaction failure category.

# Evaluation Matrix

Run these scenarios against mocks first and isolated, registered test
environments second. Never use production secrets as test fixtures.

| Priority | Scenario | Expected evidence |
|---|---|---|
| P0 | Missing resource information | Rejected before Bitwarden access or credential issuance. |
| P0 | Unregistered environment | Rejected before parent credential use. |
| P0 | Omitted access mode and TTL | Readonly request with a one-hour effective TTL. |
| P0 | Readonly operation needs write | No write call, issuance, or automatic escalation. |
| P0 | Writable request lacks approval | No credential issuance or target-service write. |
| P0 | Approval scope mismatch | New approval required; no out-of-scope operation. |
| P0 | Secret-bearing output fixture | Model-visible result and audit event contain no fixture value. |
| P0 | Success, failure, and timeout | Revocation is attempted in every case. |
| P0 | Revocation API failure | `credential_residue` and secret-free pending record remain. |
| P0 | Broker restart after forced stop | Recovery checks and revokes the pending credential. |
| P0 | Prohibited operation | Rejected before target-service API invocation. |
| P1 | Each supported service | Issue, allowed operation, revocation, and audit complete. |
| P1 | Write connection loss | Exactly one write attempt and `outcome_unknown`. |
| P1 | Audit retention | Records younger than 90 days remain available. |
| P1 | Linux and macOS | The supported-service happy and cleanup paths complete. |

Inspect the broker worker's process boundary as part of the secret tests: the
AI caller and unrelated child processes must not receive credential values or
the Bitwarden access token.

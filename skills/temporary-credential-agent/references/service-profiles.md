# Service Profiles

Use a profile only after the administrator has registered the environment,
parent credential metadata, exact resources, and allow-listed operations. A
profile missing any required mapping rejects the request.

| Service | Resource boundary | Temporary credential principle | Readonly / writable rule |
|---|---|---|---|
| AWS | Account, role, and resource ARN | Use STS credentials with a session policy that can only reduce the registered role. | Map individual AWS API actions; never add write actions to readonly. |
| Cloudflare | Account and zone | Use a scoped, revocable API token limited to permission groups and target zone. | Map each API route to read or edit; do not widen to account scope. |
| Grafana Cloud | Stack and organization | Use a revocable, expiry-capable access-policy credential where the service supports it. | Restrict API scopes to the stack and operation. |
| self-hosted Grafana | Instance and organization | Use a revocable service-account token with server-side expiry when available. | Check the deployed version's RBAC and expiry support before issue. |
| HCP Terraform | Organization, team, and workspace | Use a revocable, scope-limited token compatible with the preconfigured team boundary. | Treat apply and any state mutation as writable. |

For every profile, maintain an administrator-owned operation map with these
fields: `operation_id`, `access_mode`, `resource_matcher`, `service_actions`,
`credential_kind`, `ttl_capability`, `revoke_operation`, and
`state_check_operation`. Do not infer a map from natural-language intent.

## TTL and cleanup

Request the supplied TTL exactly when supported. A shorter server-side TTL may
be used only if it still permits the requested work and is recorded. If the
service has no server-side TTL, the broker must create the pending-revocation
record before handing the credential to its worker, then delete or revoke it in
cleanup and recovery.

## Write uncertainty and retries

Retry only read or status-check requests that are explicitly marked safe in the
operation map. Do not retry credential issuance unless the service provides an
idempotency key and the profile declares it safe. Do not retry a writable
operation after a timeout or connection loss; report `outcome_unknown` and use
the profile's state check only for observation.

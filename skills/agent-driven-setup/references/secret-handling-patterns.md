# Secret Handling Patterns

Apply these patterns when the repository setup requires API keys, tokens,
passwords, private keys, client secrets, database credentials, or any other
authentication value.

## Core rules

1. **Never ask for a secret value in normal chat.** Even a structured Ask tool
   is not automatically secret-safe. Accept a secret through an agent channel
   only when the platform contract explicitly guarantees that the value is
   hidden from conversation history, logs, and transcripts.
2. **Use secrets without observing them whenever possible.** Verify capability
   (env var presence, auth status, a minimal authenticated request) rather than
   the secret value itself.
3. **Redact before ingestion.** If a command output may contain a secret,
   redact it before it enters the agent context. If safe redaction is
   impossible, do not ingest the output.
4. **Never persist real secrets in generated files or reports.** Use safe
   placeholders in templates. Confirm `.gitignore` excludes real env files
   before creating or modifying them.

## Safe input methods (preferred order)

1. **Official login / authentication flow**
   - `gh auth login`
   - `aws sso login`
   - `gcloud auth login`
   - `login` command provided by the tool
2. **Existing credential store / secret manager**
   - OS keychain (`security`, `secret-tool`, `keyctl`)
   - Cloud secret managers (AWS Secrets Manager, GCP Secret Manager, Azure Key Vault)
   - Password managers with CLI access
3. **Terminal non-echo interactive input**
   - `read -s` in a shell the user runs directly
   - The tool's own password prompt
4. **Repository-official local env file outside Git tracking**
   - `.env` (only after confirming `.gitignore`)
   - Framework-specific config file outside the repo
5. **Temporary environment variable in the current shell session**
   - `export API_KEY=$(secret-tool lookup service example)` in the user's own terminal

## What to avoid as the primary method

Do **not** present a command-line literal such as
`export API_KEY='<your-local-key>'` as the main secret input instruction.
It trains users to paste secrets into shell history and command transcripts.
If you mention it at all, frame it only as a last-resort fallback and pair it
with a warning about shell history.

## Anti-patterns

- `echo $TOKEN`
- `printenv`
- Passing secrets on the command line: `curl -H "Authorization: Bearer $TOKEN"`
- Storing secrets in a generated file that is not explicitly ignored by Git
- Embedding a real or synthetic secret in the final report, even as an example

## Verification without observation

Instead of checking the secret value, verify:

- The required environment variable is set (name only).
- The credential file exists (path only).
- A status / connection command returns success without exposing the secret.
- A minimal authenticated request succeeds.
- A local build/test passes after the credential is configured.

## When the secret is not yet set

If the secret is required but not present:

1. Do not ask for the value in chat.
2. State that the credential is missing and give the user a trusted local
   mechanism to provide it (official login, credential store, or terminal
   non-echo input).
3. Pause setup until the user confirms the credential is available.
4. Resume verification by checking the variable name or running a capability
   test, without re-reading or re-displaying the value.

## Synthetic secret canary for evaluation

When evaluating credential handling, use a synthetic value such as
`canary-sk-eval-<random>`. The canary must never appear in:

- conversation output
- generated files
- logs or transcripts
- final reports
- model-visible context

If the canary leaks, the setup flow is unsafe.

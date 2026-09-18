# MCP Probe Handshake Design

## Goal

Make every MCP stdio probe session conform to the MCP 2025-06-18 lifecycle
without changing the existing safety boundary or evidence format.

## Scope

- Update `initialize` requests with `protocolVersion: "2025-06-18"`, empty
  `capabilities`, and deterministic `clientInfo`.
- Send `notifications/initialized` only after the initialize response has been
  validated.
- Give initialize, `tools/list`, and `tools/call` distinct JSON-RPC request IDs.
- Treat notifications as outbound-only messages. Do not wait for a response or
  count them as expected responses.
- Apply the handshake to standalone initialize, tool discovery, and
  representative tool-call probes because each probe starts a new process.
- Update MCP test fixtures and assertions to validate the actual message flow.

## Approach

Keep the existing sequential process loop and represent each outbound message
with whether it expects a response. The loop writes every message, waits only
for request responses, and validates response IDs against the originating
request. Expected response counts are derived from response-bearing messages.

Each probe session uses this sequence as applicable:

```text
initialize request (id 1)
initialize response
initialized notification
tools/list request (id 2)
tools/list response
tools/call request (id 3)
tools/call response
```

The standalone initialize probe stops after the notification, and the
standalone discovery probe continues through `tools/list`.

## Error Handling

Existing malformed JSON, JSON-RPC error, timeout, process, and response-count
failures remain runtime failures. A missing response for a request still fails
the probe. A notification written successfully does not create a response
requirement.

## Tests

- Assert initialize parameters and the initialized notification ordering.
- Assert distinct request IDs and response ID matching.
- Assert notifications do not produce fixture responses or inflate the expected
  response count.
- Exercise all three probe request modes with protocol-aware fixtures.

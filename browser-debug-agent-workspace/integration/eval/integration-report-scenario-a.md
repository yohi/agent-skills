# Integration Report — Scenario A: save-failure

## Run metadata

- Baseline: `d75d376d17c8558b90f18f1d037fd548455853b3`
- Scenario branch: `scenario-a-save-failure`
- Target: `http://127.0.0.1:3000/settings.html`
- Browser: Google Chrome 155 (`navigator.userAgent`: `Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/155.0.0.0 Safari/537.36`)
- Browser MCP: `chrome-devtools-mcp@1.10.1`
- Result: `FIX_VERIFIED`

## PRECHECK and fixture

- Chrome DevTools MCP `list_pages` returned the connected Chrome pages; the target page opened successfully.
- `npm run fixture:save-failure` completed and printed `{ settingsSaveFails: true, dashboardThrows: true }`.
- Chrome runtime inspection of `/api/config` returned `{"settingsSaveFails":true,"dashboardThrows":true}` before reproduction and after the source fix. The fixture remained enabled throughout the verification.
- Before fixture preparation, Git was at the baseline commit on `feature/browser-debug-agent`, with no staged or unstaged changes.

## REPRODUCE — before fix

The Settings page was open at the target URL with `Setting name=theme` and `Setting value=dark`. Save was clicked twice using Chrome DevTools MCP.

| Evidence | Observed |
|---|---|
| Network | Both `POST /api/settings` requests returned HTTP 500. |
| Request payload | `{"name":"theme","value":"dark"}` |
| Response body | `{"error":"Internal Server Error"}` |
| DOM/UI | `Save failed: Internal Server Error`; status text color was red. |
| Console | One `favicon.ico` 404 and one `/api/settings` HTTP 500 console error shown twice. The favicon failure was unrelated to the Save request. |
| Screenshot | Failure message rendered beneath the Save button. |

**EXPECTED:** Saving the setting should return success and show `Saved successfully`.

**ACTUAL:** The API returned HTTP 500 and the page displayed a red failure message.

## DIAGNOSE

**FACT:** With `settingsSaveFails=true`, the observed POST returned 500 with the JSON error above. The baseline `server.js` handler loaded the bug config and returned that 500 when `settingsSaveFails` was true. The client displayed the returned error in the status element.

**Root cause:** The controlled server endpoint deliberately forced a 500 response whenever the save-failure fixture was enabled. This server-side fixture branch—not the favicon 404—caused the reproduced failure.

## FIX

`browser-debug-agent-workspace/integration/buggy-app/server.js` no longer checks `settingsSaveFails` in `POST /api/settings`; it returns the normal success response. `bug-config.json` was not modified. The app was restarted to load the source change.

A regression test was added at `browser-debug-agent-workspace/integration/buggy-app/test/settings-save.test.js` to assert that the real endpoint returns HTTP 200 and the expected saved data while `settingsSaveFails=true`.

### Git diff summary

```diff
 app.post('/api/settings', (req, res) => {
-  const config = loadBugConfig();
-  if (config.settingsSaveFails) {
-    console.log('[BUG] /api/settings returning 500');
-    return res.status(500).json({ error: 'Internal Server Error' });
-  }
-  console.log('[FIXED] /api/settings returning 200');
   res.json({ success: true, saved: req.body });
 });
```

Files in the Scenario A commit:

- Modified: `browser-debug-agent-workspace/integration/buggy-app/server.js`
- Added: `browser-debug-agent-workspace/integration/buggy-app/test/settings-save.test.js`
- Added: `browser-debug-agent-workspace/integration/eval/integration-report-scenario-a.md`
- Added: `browser-debug-agent-workspace/integration/eval/evidence/scenario-a-save-success.png`

## TEST

- RED before the server fix: `node --test test/settings-save.test.js` failed at the expected assertion with `500 !== 200`.
- GREEN after the fix: `node --test` reported **1 pass, 0 failures**.
- Final `git diff --check` completed without errors.

## VERIFY — same real-browser scenario after fix

After restarting the app, the same Chrome tab was reloaded at the same URL and Save was clicked with the same values while `/api/config` still reported `settingsSaveFails=true`.

| Evidence | Observed |
|---|---|
| Network | `POST /api/settings` returned HTTP 200. |
| Request payload | `{"name":"theme","value":"dark"}` |
| Response body | `{"success":true,"saved":{"name":"theme","value":"dark"}}` |
| DOM/UI | `Saved successfully`; status text color was green. |
| Console | No console messages after reload and the successful Save. |
| Screenshot | `evidence/scenario-a-save-success.png` shows the success message in the real Chrome page. |
| Runtime | URL remained `http://127.0.0.1:3000/settings.html`; title was `Settings`; form values remained `theme` / `dark`. |

Because the same failing browser scenario succeeded after the code fix with the fixture still enabled, the result is `FIX_VERIFIED`.

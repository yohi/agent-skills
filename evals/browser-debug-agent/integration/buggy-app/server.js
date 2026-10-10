const express = require('express');
const fs = require('fs');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3000;
const BUG_CONFIG_PATH = path.join(__dirname, 'bug-config.json');

app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(express.static(path.join(__dirname, 'public')));

function loadBugConfig() {
  try {
    const raw = fs.readFileSync(BUG_CONFIG_PATH, 'utf8');
    return JSON.parse(raw);
  } catch (err) {
    console.error('Failed to load bug-config.json:', err.message);
    return { settingsSaveFails: true, dashboardThrows: true };
  }
}

// Contract for FIX -> VERIFY:
//   * bug-config.json is re-read on every request, so fixture scripts take
//     effect immediately.
//   * Backend source fixes to server.js require restarting the server.
//   * Frontend source fixes to public/app.js require reloading the browser page.
//     Restart the server only if backend source or configuration changed.

app.get('/api/config', (req, res) => {
  res.json(loadBugConfig());
});

app.post('/api/login', (req, res) => {
  // Fake login: accept any credentials for integration testing.
  res.json({ success: true, user: req.body.username || 'test-user' });
});

app.post('/api/settings', (req, res) => {
  const config = loadBugConfig();
  if (config.settingsSaveFails) {
    console.log('[BUG] /api/settings returning 500');
    return res.status(500).json({ error: 'Internal Server Error' });
  }
  res.json({ success: true, saved: req.body });
});

app.listen(PORT, '127.0.0.1', () => {
  console.log(`Buggy app listening on http://127.0.0.1:${PORT}`);
  console.log('Bug config:', loadBugConfig());
});

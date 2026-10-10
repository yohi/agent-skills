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
//   * Source-code fixes to server.js or public/app.js require a server restart
//     before VERIFY. The agent must run `npm start` again (or use a process
//     manager) after editing source files.

app.get('/api/config', (req, res) => {
  res.json(loadBugConfig());
});

app.post('/api/login', (req, res) => {
  // Fake login: accept any credentials for integration testing.
  res.json({ success: true, user: req.body.username || 'test-user' });
});

app.post('/api/settings', (req, res) => {
  res.json({ success: true, saved: req.body });
});

app.listen(PORT, '127.0.0.1', () => {
  console.log(`Buggy app listening on http://127.0.0.1:${PORT}`);
  console.log('Bug config:', loadBugConfig());
});

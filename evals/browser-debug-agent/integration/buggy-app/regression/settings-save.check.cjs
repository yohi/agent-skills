const assert = require('node:assert/strict');
const { spawn } = require('node:child_process');
const net = require('node:net');
const path = require('node:path');
const { after, before, test } = require('node:test');

const appDirectory = path.join(__dirname, '..');
let appProcess;
let appUrl;

before(async () => {
  const port = await new Promise((resolve, reject) => {
    const server = net.createServer();
    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => {
      const { port: availablePort } = server.address();
      server.close((error) => error ? reject(error) : resolve(availablePort));
    });
  });

  appUrl = `http://127.0.0.1:${port}`;
  appProcess = spawn(process.execPath, ['server.js'], {
    cwd: appDirectory,
    env: { ...process.env, PORT: String(port) },
    stdio: 'ignore'
  });

  for (let attempt = 0; attempt < 50; attempt += 1) {
    if (appProcess.exitCode !== null) {
      throw new Error(`App exited before becoming ready (code ${appProcess.exitCode})`);
    }

    try {
      const response = await fetch(`${appUrl}/api/config`);
      if (response.ok) return;
    } catch {
    }

    await new Promise((resolve) => setTimeout(resolve, 20));
  }

  throw new Error('App did not become ready within 1 second');
});

after(() => {
  appProcess?.kill();
});

test('POST /api/settings saves settings when the failure fixture is enabled', async () => {
  const config = await fetch(`${appUrl}/api/config`).then((response) => response.json());
  assert.equal(config.settingsSaveFails, true, 'the save-failure fixture must be active');

  const response = await fetch(`${appUrl}/api/settings`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ name: 'theme', value: 'dark' })
  });

  assert.equal(response.status, 200, 'saving must succeed even with the failure fixture enabled');
  assert.deepEqual(await response.json(), {
    success: true,
    saved: { name: 'theme', value: 'dark' }
  });
});

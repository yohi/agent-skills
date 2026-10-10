const assert = require('node:assert/strict');
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const net = require('node:net');
const path = require('node:path');
const vm = require('node:vm');
const { before, after, test } = require('node:test');

const appDirectory = path.join(__dirname, '..');
const configPath = path.join(appDirectory, 'bug-config.json');
const frontendPath = path.join(appDirectory, 'public', 'app.js');
let appProcess;
let appUrl;

async function unusedPort() {
  return new Promise((resolve, reject) => {
    const listener = net.createServer();
    listener.once('error', reject);
    listener.listen(0, '127.0.0.1', () => {
      const { port } = listener.address();
      listener.close((error) => error ? reject(error) : resolve(port));
    });
  });
}

before(async () => {
  const port = await unusedPort();
  appUrl = `http://127.0.0.1:${port}`;
  appProcess = spawn(process.execPath, ['server.js'], {
    cwd: appDirectory,
    env: { ...process.env, PORT: String(port) },
    stdio: 'ignore'
  });

  for (let attempt = 0; attempt < 50; attempt += 1) {
    if (appProcess.exitCode !== null) {
      throw new Error(`Fixture app exited (code ${appProcess.exitCode})`);
    }
    try {
      const response = await fetch(`${appUrl}/api/config`);
      if (response.ok) return;
    } catch {
      // App startup can take a moment.
    }
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  throw new Error('Fixture app did not become ready within 2.5 seconds');
});

after(() => { appProcess?.kill(); });

test('baseline fixture has both intentional bugs enabled', async () => {
  const expected = { settingsSaveFails: true, dashboardThrows: true };
  assert.deepEqual(JSON.parse(fs.readFileSync(configPath, 'utf8')), expected);
  assert.deepEqual(await fetch(`${appUrl}/api/config`).then((r) => r.json()), expected);
});

test('Scenario A reproduces POST /api/settings HTTP 500', async () => {
  const response = await fetch(`${appUrl}/api/settings`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ name: 'theme', value: 'dark' })
  });
  assert.equal(response.status, 500);
  assert.deepEqual(await response.json(), { error: 'Internal Server Error' });
});

test('Scenario B reproduces dashboard exception and empty content', async () => {
  const source = fs.readFileSync(frontendPath, 'utf8');
  const container = { textContent: 'Loading...' };
  const context = {
    document: { getElementById: () => container },
    fetch: async () => ({ json: async () => ({ dashboardThrows: true }) })
  };
  const result = vm.runInNewContext(`${source}\nrenderDashboard()`, context);
  await assert.rejects(result, /Dashboard render failed: authState is undefined/);
  assert.equal(container.textContent, '');
});

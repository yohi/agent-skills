const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');

const appSource = fs.readFileSync(path.join(__dirname, '../public/app.js'), 'utf8');

test('renderDashboard displays dashboard content when the blank-screen fixture is enabled', async () => {
  const container = { innerHTML: '', textContent: '' };
  const context = {
    document: { getElementById: () => container },
    fetch: async () => ({ json: async () => ({ dashboardThrows: true, user: 'integration-user' }) })
  };

  await vm.runInNewContext(`${appSource}\nrenderDashboard()`, context);

  assert.match(container.innerHTML, /Welcome, <strong>integration-user<\/strong>!/);
  assert.match(container.innerHTML, /Dashboard loaded successfully\./);
});

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');

const appSource = fs.readFileSync(path.join(__dirname, '../public/app.js'), 'utf8');

test('renderDashboard displays dashboard content when the blank-screen fixture is enabled', async () => {
  const container = {
    children: [],
    replaceChildren(...children) { this.children = children; }
  };
  const document = {
    getElementById: () => container,
    createElement: (tagName) => ({ tagName, children: [], textContent: '', appendChild(child) { this.children.push(child); } }),
    createTextNode: (text) => ({ textContent: text })
  };
  const context = {
    document,
    fetch: async () => ({ json: async () => ({ dashboardThrows: true, user: '<img src=x onerror=alert(1)>' }) })
  };

  await vm.runInNewContext(`${appSource}\nrenderDashboard()`, context);

  assert.equal(container.children[0].children[0].textContent, 'Welcome, ');
  assert.equal(container.children[0].children[1].textContent, '<img src=x onerror=alert(1)>');
  assert.equal(container.children[0].children[2].textContent, '!');
  assert.equal(container.children[1].textContent, 'Dashboard loaded successfully.');
});

test('renderDashboard uses the default username when config.user is missing', async () => {
  const container = { children: [], replaceChildren(...children) { this.children = children; } };
  const document = {
    getElementById: () => container,
    createElement: (tagName) => ({ tagName, children: [], textContent: '', appendChild(child) { this.children.push(child); } }),
    createTextNode: (text) => ({ textContent: text })
  };
  const context = {
    document,
    fetch: async () => ({ json: async () => ({}) })
  };

  await vm.runInNewContext(`${appSource}\nrenderDashboard()`, context);

  assert.equal(container.children[0].children[1].textContent, 'user');
  assert.equal(container.children[1].textContent, 'Dashboard loaded successfully.');
});

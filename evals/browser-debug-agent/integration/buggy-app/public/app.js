async function fakeLogin() {
  const username = document.getElementById('username').value;
  const password = document.getElementById('password').value;
  const res = await fetch('/api/login', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username, password })
  });
  const data = await res.json();
  if (data.success) {
    window.location.href = '/dashboard.html';
  } else {
    alert('Login failed');
  }
}

async function saveSettings() {
  const name = document.getElementById('setting-name').value;
  const value = document.getElementById('setting-value').value;
  const status = document.getElementById('status');
  status.textContent = 'Saving...';
  try {
    const res = await fetch('/api/settings', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name, value })
    });
    const data = await res.json();
    if (res.ok) {
      status.textContent = 'Saved successfully';
      status.style.color = 'green';
    } else {
      status.textContent = 'Save failed: ' + (data.error || res.statusText);
      status.style.color = 'red';
    }
  } catch (err) {
    status.textContent = 'Save failed: ' + err.message;
    status.style.color = 'red';
  }
}

async function renderDashboard() {
  const config = await fetch('/api/config').then(r => r.json());
  const container = document.getElementById('dashboard-content');

  container.innerHTML = `
    <p>Welcome, <strong>${config.user || 'user'}</strong>!</p>
    <p>Dashboard loaded successfully.</p>
  `;
}

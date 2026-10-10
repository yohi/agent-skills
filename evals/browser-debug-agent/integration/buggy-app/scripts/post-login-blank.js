const fs = require('fs');
const path = require('path');

const BUG_CONFIG_PATH = path.join(__dirname, '..', 'bug-config.json');
const config = { settingsSaveFails: false, dashboardThrows: true };
fs.writeFileSync(BUG_CONFIG_PATH, JSON.stringify(config, null, 2) + '\n');
console.log('[fixture:post-login-blank] isolated dashboard failure:', config);

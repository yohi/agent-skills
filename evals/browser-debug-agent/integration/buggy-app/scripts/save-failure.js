const fs = require('fs');
const path = require('path');

const BUG_CONFIG_PATH = path.join(__dirname, '..', 'bug-config.json');
const config = { settingsSaveFails: true, dashboardThrows: false };
fs.writeFileSync(BUG_CONFIG_PATH, JSON.stringify(config, null, 2) + '\n');
console.log('[fixture:save-failure] isolated settings failure:', config);

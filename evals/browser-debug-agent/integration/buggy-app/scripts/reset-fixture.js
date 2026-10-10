const fs = require('fs');
const path = require('path');

const BUG_CONFIG_PATH = path.join(__dirname, '..', 'bug-config.json');

const DEFAULT_BUGGY_STATE = {
  settingsSaveFails: true,
  dashboardThrows: true
};

fs.writeFileSync(BUG_CONFIG_PATH, JSON.stringify(DEFAULT_BUGGY_STATE, null, 2) + '\n');
console.log('[fixture:reset] restored default buggy state:', DEFAULT_BUGGY_STATE);
console.log('[fixture:reset] note: bug-config.json is reloaded dynamically; source-code fixes require server restart');

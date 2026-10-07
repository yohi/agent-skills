const fs = require('fs');
const path = require('path');

const BUG_CONFIG_PATH = path.join(__dirname, '..', 'bug-config.json');

function loadConfig() {
  try {
    return JSON.parse(fs.readFileSync(BUG_CONFIG_PATH, 'utf8'));
  } catch {
    return {};
  }
}

const config = loadConfig();
config.settingsSaveFails = true;
fs.writeFileSync(BUG_CONFIG_PATH, JSON.stringify(config, null, 2) + '\n');
console.log('[fixture:save-failure] settingsSaveFails=true:', config);
console.log('[fixture:save-failure] note: bug-config.json is reloaded dynamically; source-code fixes require server restart');

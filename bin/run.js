#!/usr/bin/env node

const { execFileSync } = require('child_process');
const path = require('path');

const setupScript = path.join(__dirname, '..', 'setup.sh');

try {
  execFileSync('bash', [setupScript], {
    cwd: process.cwd(),
    stdio: 'inherit',
  });
} catch (error) {
  process.exit(error.status || 1);
}

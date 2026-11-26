'use strict';

/**
 * Runs Security Audit 1 local validation suites (no production deploy).
 */
const { spawnSync } = require('child_process');
const path = require('path');

const root = path.join(__dirname, '..', '..');

function run(cmd, args, cwd = root, extraEnv = {}) {
  const label = `${cmd} ${args.join(' ')}`;
  process.stdout.write(`\n=== ${label} ===\n`);
  const res = spawnSync(cmd, args, {
    cwd,
    env: { ...process.env, ...extraEnv },
    stdio: 'inherit',
    shell: process.platform === 'win32',
  });
  if (res.status !== 0) {
    process.stderr.write(`FAILED: ${label}\n`);
    process.exit(res.status || 1);
  }
}

run('npm', ['test'], path.join(root, 'services', 'api-gateway'));
run('npm', ['run', 'test:redis-integration'], path.join(root, 'services', 'api-gateway'));
run('npm', ['test'], path.join(root, 'backend', 'functions'));
run(process.execPath, [
  '--test',
  'test/hosting_csp.test.js',
  'test/hosting_csp_connect_src.test.js',
], path.join(root, 'backend', 'functions'));

if (String(process.env.RUN_CSP_BROWSER_SMOKE || '') === '1') {
  run(process.execPath, ['--test', 'test/hosting_csp_browser_smoke.test.js'], path.join(root, 'backend', 'functions'), {
    RUN_CSP_BROWSER_SMOKE: '1',
  });
} else {
  process.stdout.write('\n=== CSP HTTP smoke: SKIP (RUN_CSP_BROWSER_SMOKE=1 + csp_local_smoke_server.js) ===\n');
}

run(process.execPath, [
  '--test',
  'scripts/test/trusted_client_ip.test.js',
  'scripts/test/demo_routing.test.js',
]);

process.stdout.write('\nAll requested local validation suites completed.\n');
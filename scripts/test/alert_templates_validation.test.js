'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

describe('alert_templates.yaml validation', () => {
  it('declares required alert ids and runbook references', () => {
    const yamlPath = path.join(
      __dirname,
      '../../docs/audit/audit7/alerting/alert_templates.yaml',
    );
    const text = fs.readFileSync(yamlPath, 'utf8');
    assert.match(text, /OPS-ALERT-GW-5XX/);
    assert.match(text, /OPS-ALERT-GW-READYZ/);
    assert.match(text, /OPS-ALERT-SYNC-DLQ/);
    assert.match(text, /RUNBOOK_/);
    assert.doesNotMatch(text, /pagerduty.*api_key/i);
    assert.doesNotMatch(text, /password:\s*['"][^'"]+['"]/i);
  });
});
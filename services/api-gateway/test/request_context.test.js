'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const { resolveRequestId, REQUEST_ID_HEADER } = require('../src/request_context');

describe('request_context (REL-10)', () => {
  it('reuses valid inbound request id', () => {
    const id = resolveRequestId({ headers: { [REQUEST_ID_HEADER]: 'abc-12345678' } });
    assert.equal(id, 'abc-12345678');
  });

  it('mints request id when header missing', () => {
    const id = resolveRequestId({ headers: {} });
    assert.match(id, /^[a-f0-9]{24}$/);
  });

  it('rejects unsafe inbound ids', () => {
    const id = resolveRequestId({ headers: { [REQUEST_ID_HEADER]: 'bad id!' } });
    assert.match(id, /^[a-f0-9]{24}$/);
  });
});
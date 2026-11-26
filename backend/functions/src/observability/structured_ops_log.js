'use strict';

const {
  operationalLogEnvelope,
  writeOperationalLog,
  redactString,
} = require('../../../../scripts/lib/log_redaction');

const SERVICE = 'doctornect-functions';

function emitOpsEvent(fields) {
  const entry = operationalLogEnvelope({
    service: SERVICE,
    ...fields,
  });
  writeOperationalLog(entry);
  return entry;
}

function emitSyncDlqEvent({
  direction,
  entityType,
  entityId,
  retryCount,
  errorMessage,
  requestId = null,
}) {
  return emitOpsEvent({
    event: 'cross_role_sync_dlq',
    severity: 'CRITICAL',
    outcome: 'failure',
    operation: 'sync_bridge',
    requestId,
    errorClassification: 'sync_exhausted',
    detail: {
      direction,
      entity_type: entityType,
      entity_id: entityId,
      retry_count: retryCount,
      error_message: redactString(errorMessage),
    },
  });
}

module.exports = {
  emitOpsEvent,
  emitSyncDlqEvent,
};
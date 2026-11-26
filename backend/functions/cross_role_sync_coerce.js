'use strict';

function optionalFiniteNumber(value) {
  if (value === undefined || value === null || value === '') return undefined;
  const n = typeof value === 'number' ? value : Number(String(value).trim());
  if (!Number.isFinite(n)) return undefined;
  return n;
}

function firestoreTimestampMs(value) {
  if (value == null || value === '') return null;
  if (typeof value.toDate === 'function') {
    const ms = value.toDate().getTime();
    return Number.isNaN(ms) ? null : ms;
  }
  if (value instanceof Date) {
    const ms = value.getTime();
    return Number.isNaN(ms) ? null : ms;
  }
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value === 'string') {
    const ms = Date.parse(value);
    return Number.isNaN(ms) ? null : ms;
  }
  if (typeof value === 'object' && Number.isFinite(value._seconds)) {
    return value._seconds * 1000 + Math.floor((value._nanoseconds || 0) / 1e6);
  }
  return null;
}

function toStringArray(val, defaultArr = []) {
  if (Array.isArray(val)) {
    const cleaned = val.map(x => String(x || '').trim()).filter(Boolean);
    return cleaned.length > 0 ? cleaned : defaultArr;
  }
  if (typeof val === 'string' && val.trim().length > 0) {
    return [val.trim()];
  }
  return defaultArr;
}

function toIsoTimestamp(val) {
  if (!val) return null;
  if (typeof val.toDate === 'function') {
    return val.toDate().toISOString();
  }
  if (val instanceof Date) {
    return isNaN(val.getTime()) ? null : val.toISOString();
  }
  if (typeof val === 'string' || typeof val === 'number') {
    const d = new Date(val);
    return isNaN(d.getTime()) ? null : d.toISOString();
  }
  return null;
}

function toDateString(val) {
  if (!val) return null;
  let d;
  if (typeof val.toDate === 'function') {
    d = val.toDate();
  } else if (typeof val === 'string') {
    const trimmed = val.trim();
    if (/^\d{4}-\d{2}-\d{2}$/.test(trimmed)) return trimmed;
    d = new Date(trimmed);
  } else if (val instanceof Date) {
    d = val;
  } else if (typeof val === 'number') {
    d = new Date(val);
  }
  if (!d || isNaN(d.getTime())) return null;
  const year = d.getUTCFullYear();
  const month = String(d.getUTCMonth() + 1).padStart(2, '0');
  const day = String(d.getUTCDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function toValidUuid(val) {
  if (typeof val !== 'string') return null;
  const trimmed = val.trim();
  const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  return uuidRegex.test(trimmed) ? trimmed : null;
}

module.exports = {
  optionalFiniteNumber,
  firestoreTimestampMs,
  toStringArray,
  toIsoTimestamp,
  toDateString,
  toValidUuid,
};
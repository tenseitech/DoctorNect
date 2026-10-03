'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { buildPublicReviewData, maskReviewPatientName } = require('../review_public_sync');

test('buildPublicReviewData excludes patient identifiers', () => {
  const payload = buildPublicReviewData({
    patientId: 'p1234567890',
    doctorId: 'd9876543210',
    appointmentId: 'appt-1',
    patientName: 'Jane Doe',
    rating: 4,
    comment: 'Helpful visit',
    helpfulCount: 2,
    doctorReply: 'Thank you',
  });

  assert.equal(payload.doctorId, 'd9876543210');
  assert.equal(payload.rating, 4);
  assert.equal(payload.comment, 'Helpful visit');
  assert.equal(payload.maskedName, 'J. D.');
  assert.equal(payload.helpfulCount, 2);
  assert.equal(payload.doctorReply, 'Thank you');
  assert.equal(Object.prototype.hasOwnProperty.call(payload, 'patientId'), false);
  assert.equal(Object.prototype.hasOwnProperty.call(payload, 'appointmentId'), false);
  assert.equal(Object.prototype.hasOwnProperty.call(payload, 'patientName'), false);
});

test('maskReviewPatientName masks multi-part names', () => {
  assert.equal(maskReviewPatientName('Jane Doe'), 'J. D.');
  assert.equal(maskReviewPatientName('Prince'), 'P.');
});

'use strict';

const { describe, it, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const { resolveCallerIdentity, setSupabaseClientForTesting } = require('../caller_identity');

describe('caller_identity helper', () => {
  afterEach(() => {
    setSupabaseClientForTesting(null);
  });

  describe('Firestore path (cutover flag OFF)', () => {
    it('resolves user profile when document exists in Firestore', async () => {
      const mockDb = {
        collection: (name) => {
          assert.equal(name, 'users');
          return {
            doc: (docId) => ({
              get: async () => ({
                exists: true,
                id: docId,
                data: () => ({
                  role: 'doctor',
                  profileId: 'doc_123',
                  verified: true,
                  mobile: '9876543210',
                }),
              }),
            }),
          };
        },
      };

      const user = await resolveCallerIdentity({
        db: mockDb,
        uid: 'user_abc',
        forceSupabase: false,
      });

      assert.equal(user.id, 'user_abc');
      assert.equal(user.role, 'doctor');
      assert.equal(user.profileId, 'doc_123');
      assert.equal(user.verified, true);
    });

    it('throws unauthenticated HttpsError when Firestore document is missing', async () => {
      const mockDb = {
        collection: () => ({
          doc: () => ({
            get: async () => ({
              exists: false,
              data: () => null,
            }),
          }),
        }),
      };

      await assert.rejects(
        () => resolveCallerIdentity({
          db: mockDb,
          uid: 'missing_user',
          forceSupabase: false,
        }),
        (err) => {
          assert.equal(err.code, 'unauthenticated');
          assert.match(err.message, /User profile document not found/);
          return true;
        }
      );
    });
  });

  describe('Supabase path (cutover flag ON / forceSupabase)', () => {
    it('resolves caller from Supabase users table via service role client', async () => {
      const mockSupabase = {
        from: (table) => {
          assert.equal(table, 'users');
          return {
            select: () => ({
              or: (filter) => {
                assert.ok(filter.includes('user_sb_123'));
                return {
                  maybeSingle: async () => ({
                    data: {
                      id: 'user_sb_123',
                      firebase_uid: 'user_sb_123',
                      role: 'patient',
                      profile_id: 'pat_456',
                      display_name: 'Test Patient',
                      email: 'test@example.com',
                      mobile: '9123456780',
                      verified: true,
                      profile_completed: true,
                      status: 'approved',
                    },
                    error: null,
                  }),
                };
              },
            }),
          };
        },
      };

      const user = await resolveCallerIdentity({
        uid: 'user_sb_123',
        supabaseClient: mockSupabase,
        forceSupabase: true,
      });

      assert.equal(user.id, 'user_sb_123');
      assert.equal(user.role, 'patient');
      assert.equal(user.profileId, 'pat_456');
      assert.equal(user.profile_id, 'pat_456');
      assert.equal(user.phone, '9123456780');
      assert.equal(user.profileCompleted, true);
      assert.equal(user.verified, true);
    });

    it('throws unauthenticated when Supabase returns no user row', async () => {
      const mockSupabase = {
        from: () => ({
          select: () => ({
            or: () => ({
              maybeSingle: async () => ({ data: null, error: null }),
            }),
          }),
        }),
      };

      await assert.rejects(
        () => resolveCallerIdentity({
          uid: 'nonexistent_uid',
          supabaseClient: mockSupabase,
          forceSupabase: true,
        }),
        (err) => {
          assert.equal(err.code, 'unauthenticated');
          return true;
        }
      );
    });

    it('throws unauthenticated when uid is missing or invalid', async () => {
      await assert.rejects(
        () => resolveCallerIdentity({ uid: null }),
        (err) => {
          assert.equal(err.code, 'unauthenticated');
          return true;
        }
      );
    });
  });
});

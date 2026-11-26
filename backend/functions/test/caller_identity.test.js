'use strict';

const { describe, it, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const { resolveCallerIdentity, setSupabaseClientForTesting } = require('../caller_identity');

describe('caller_identity helper', () => {
  afterEach(() => {
    setSupabaseClientForTesting(null);
  });

  describe('Postgres-only (Firestore removed)', () => {
    it('ignores any injected Firestore db and reads public.users', async () => {
      const { createMemoryPostgrest } = require('./helpers/memory_postgrest');
      const sb = createMemoryPostgrest({ users: [{ id: 'user_abc', firebase_uid: 'user_abc', role: 'doctor', profile_id: 'doc_123', verified: true }] });
      const firestoreLike = { collection: () => { throw new Error('Firestore must never be touched'); } };
      const user = await resolveCallerIdentity({ db: firestoreLike, uid: 'user_abc', supabaseClient: sb });
      assert.equal(user.role, 'doctor');
      assert.equal(user.profileId, 'doc_123');
    });

    it('rejects uids that could inject PostgREST filter syntax', async () => {
      const { createMemoryPostgrest } = require('./helpers/memory_postgrest');
      const sb = createMemoryPostgrest({ users: [] });
      for (const uid of ['a,role.eq.superAdmin', 'x)or(', 'a b']) {
        await assert.rejects(() => resolveCallerIdentity({ uid, supabaseClient: sb }), (err) => err.code === 'unauthenticated');
      }
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

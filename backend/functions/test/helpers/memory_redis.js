'use strict';

/**
 * In-memory Redis double for unit tests. Implements the subset the backend uses:
 * get / set (EX, PX, NX) / del / incr / pexpire / pttl / getdel / scan / quit, plus eval for
 * the three Lua scripts in the codebase (fixed-window INCR+PEXPIRE, OTP attempt slot,
 * atomic GET+DEL). Keys honour TTLs so expiry paths are exercised.
 */
function createMemoryRedis() {
  const store = new Map(); // key -> { val: string, expireAt: number|null }

  const live = (key) => {
    const e = store.get(key);
    if (!e) return null;
    if (e.expireAt != null && Date.now() > e.expireAt) {
      store.delete(key);
      return null;
    }
    return e;
  };

  const redis = {
    store,
    clearStore() { store.clear(); },
    async get(key) { return live(key)?.val ?? null; },
    async set(key, val, ...args) {
      let expireAt = null;
      let nx = false;
      for (let i = 0; i < args.length; i++) {
        const a = String(args[i]).toUpperCase();
        if (a === 'EX') { expireAt = Date.now() + Number(args[++i]) * 1000; }
        else if (a === 'PX') { expireAt = Date.now() + Number(args[++i]); }
        else if (a === 'NX') { nx = true; }
      }
      if (nx && live(key)) return null;
      store.set(key, { val: String(val), expireAt });
      return 'OK';
    },
    async del(...keys) {
      let n = 0;
      for (const k of keys.flat()) if (store.delete(k)) n++;
      return n;
    },
    async getdel(key) {
      const v = live(key)?.val ?? null;
      store.delete(key);
      return v;
    },
    async incr(key) {
      const e = live(key);
      const next = (e ? Number(e.val) || 0 : 0) + 1;
      store.set(key, { val: String(next), expireAt: e?.expireAt ?? null });
      return next;
    },
    async pexpire(key, ms) {
      const e = live(key);
      if (!e) return 0;
      e.expireAt = Date.now() + Number(ms);
      return 1;
    },
    async pttl(key) {
      const e = live(key);
      if (!e) return -2;
      return e.expireAt == null ? -1 : Math.max(0, e.expireAt - Date.now());
    },
    async scan(_cursor, _match, pattern) {
      const prefix = String(pattern || '').replace(/\*$/, '');
      return ['0', [...store.keys()].filter((k) => k.startsWith(prefix) && live(k))];
    },
    async eval(script, _numKeys, key, ...argv) {
      const s = String(script);
      if (/'GET'/.test(s) && /'DEL'/.test(s)) {
        return redis.getdel(key);
      }
      if (/tonumber\(ARGV\[2\]\)/.test(s)) {
        // OTP attempt slot: INCR, PEXPIRE on first, -1 when over max.
        const n = await redis.incr(key);
        if (n === 1) await redis.pexpire(key, Number(argv[0]));
        return n > Number(argv[1]) ? -1 : n;
      }
      // Fixed-window counter: INCR, PEXPIRE when new or TTL missing.
      const n = await redis.incr(key);
      const e = live(key);
      if (n === 1 || (e && e.expireAt == null)) await redis.pexpire(key, Number(argv[0]));
      return n;
    },
    async quit() {},
    disconnect() {},
    on() { return redis; },
  };
  return redis;
}

module.exports = { createMemoryRedis };

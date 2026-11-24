'use strict';

/**
 * In-memory supabase-js / PostgREST double for unit tests.
 *
 * createMemoryPostgrest({ users: [{...}], ambulances: [...] , ... }, { rpc: { name: fn } })
 *
 * Supports: from(t).select(cols?).eq/neq/in/is/lte/gte/lt/gt/ilike/or(...).order().limit()
 *   .maybeSingle()/.single()/await;  insert(rows), upsert(rows, {onConflict}), update(patch)
 *   [+filters, + .select()], delete() [+filters];  rpc(name, args).
 * `or()` understands PostgREST `a.eq.x,b.eq.y` lists. Every mutation is recorded in `calls`.
 */
function createMemoryPostgrest(initial = {}, { rpc = {}, primaryKeys = {} } = {}) {
  const tables = new Map();
  for (const [name, rows] of Object.entries(initial)) {
    tables.set(name, (rows || []).map((r) => ({ ...r })));
  }
  const calls = [];
  const table = (name) => {
    if (!tables.has(name)) tables.set(name, []);
    return tables.get(name);
  };

  const parseOr = (expr) => String(expr || '').split(',').map((part) => {
    const m = part.match(/^([a-zA-Z0-9_]+)\.(eq|neq|is)\.(.*)$/);
    if (!m) return () => false;
    const [, col, op, raw] = m;
    const val = raw === 'null' ? null : raw;
    if (op === 'eq') return (r) => String(r[col]) === String(val);
    if (op === 'neq') return (r) => String(r[col]) !== String(val);
    return (r) => (val === null ? r[col] == null : r[col] === val);
  });

  function builder(name) {
    const filters = [];
    let mode = 'select';
    let payload = null;
    let upsertOpts = null;
    let wantRows = false;
    let limitN = null;
    let single = null; // 'maybe' | 'one'

    const api = {
      select() { if (mode !== 'select') wantRows = true; return api; },
      eq(c, v) { filters.push((r) => r[c] === v || String(r[c]) === String(v)); return api; },
      neq(c, v) { filters.push((r) => String(r[c]) !== String(v)); return api; },
      in(c, vs) { const set = new Set((vs || []).map(String)); filters.push((r) => set.has(String(r[c]))); return api; },
      is(c, v) { filters.push((r) => (v === null ? r[c] == null : r[c] === v)); return api; },
      lte(c, v) { filters.push((r) => r[c] != null && r[c] <= v); return api; },
      gte(c, v) { filters.push((r) => r[c] != null && r[c] >= v); return api; },
      lt(c, v) { filters.push((r) => r[c] != null && r[c] < v); return api; },
      gt(c, v) { filters.push((r) => r[c] != null && r[c] > v); return api; },
      ilike(c, v) { filters.push((r) => String(r[c] || '').toLowerCase() === String(v).toLowerCase()); return api; },
      or(expr) { const preds = parseOr(expr); filters.push((r) => preds.some((p) => p(r))); return api; },
      order() { return api; },
      limit(n) { limitN = n; return api; },
      maybeSingle() { single = 'maybe'; return api; },
      single() { single = 'one'; return api; },
      insert(rows) { mode = 'insert'; payload = rows; return api; },
      upsert(rows, opts = {}) { mode = 'upsert'; payload = rows; upsertOpts = opts; return api; },
      update(patch) { mode = 'update'; payload = patch; return api; },
      delete() { mode = 'delete'; return api; },
      then(resolve, reject) {
        try { resolve(run()); } catch (e) { if (reject) reject(e); else throw e; }
      },
    };

    const match = (r) => filters.every((f) => f(r));

    function shape(rows) {
      if (single === 'maybe') {
        if (rows.length > 1) return { data: null, error: { message: 'multiple rows', code: 'PGRST116' } };
        return { data: rows[0] ? { ...rows[0] } : null, error: null };
      }
      if (single === 'one') {
        if (rows.length !== 1) return { data: null, error: { message: 'not one row', code: 'PGRST116' } };
        return { data: { ...rows[0] }, error: null };
      }
      return { data: rows.map((r) => ({ ...r })), error: null };
    }

    function run() {
      const t = table(name);
      if (mode === 'select') {
        let rows = t.filter(match);
        if (limitN != null) rows = rows.slice(0, limitN);
        return shape(rows);
      }
      calls.push({ table: name, mode, payload, filters: filters.length });
      if (mode === 'insert') {
        const rows = (Array.isArray(payload) ? payload : [payload]).map((r) => ({ ...r }));
        t.push(...rows);
        return wantRows ? shape(rows) : { data: null, error: null };
      }
      if (mode === 'upsert') {
        const key = String(upsertOpts?.onConflict || primaryKeys[name] || 'id').split(',')[0].trim();
        const out = [];
        for (const r of (Array.isArray(payload) ? payload : [payload])) {
          const idx = t.findIndex((x) => x[key] != null && String(x[key]) === String(r[key]));
          if (idx >= 0) {
            if (!upsertOpts?.ignoreDuplicates) t[idx] = { ...t[idx], ...r };
            out.push(t[idx]);
          } else {
            t.push({ ...r });
            out.push(r);
          }
        }
        return wantRows ? shape(out) : { data: null, error: null };
      }
      if (mode === 'update') {
        const changed = [];
        for (let i = 0; i < t.length; i++) {
          if (match(t[i])) { t[i] = { ...t[i], ...payload }; changed.push(t[i]); }
        }
        return wantRows ? shape(changed) : { data: null, error: null };
      }
      if (mode === 'delete') {
        const kept = [];
        const removed = [];
        for (const r of t) (match(r) ? removed : kept).push(r);
        tables.set(name, kept);
        return wantRows ? shape(removed) : { data: null, error: null };
      }
      return { data: null, error: { message: `unsupported mode ${mode}` } };
    }

    return api;
  }

  return {
    tables,
    calls,
    rows(name) { return table(name); },
    from(name) { return builder(name); },
    async rpc(name, args) {
      calls.push({ rpc: name, args });
      const fn = rpc[name];
      if (!fn) return { data: null, error: { message: `rpc ${name} not mocked` } };
      try {
        return { data: await fn(args, { tables, table }), error: null };
      } catch (err) {
        return { data: null, error: { message: err.message } };
      }
    },
  };
}

module.exports = { createMemoryPostgrest };

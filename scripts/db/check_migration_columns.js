'use strict';

const fs = require('fs');
const path = require('path');
const { parse } = require('libpg-query');

async function parseSqlStatements(sql, tables) {
  let parsed;
  try {
    parsed = await parse(sql);
  } catch (err) {
    return;
  }

  if (!parsed || !Array.isArray(parsed.stmts)) return;

  function getTableColumns(tableName) {
    const norm = tableName.toLowerCase();
    if (!tables.has(norm)) {
      tables.set(norm, new Set());
    }
    return tables.get(norm);
  }

  for (const stmtObj of parsed.stmts) {
    const stmt = stmtObj.stmt;
    if (!stmt) continue;

    // 1. CREATE TABLE
    if (stmt.CreateStmt) {
      const createStmt = stmt.CreateStmt;
      const rel = createStmt.relation;
      const tableName = rel.relname;
      const colSet = getTableColumns(tableName);

      if (Array.isArray(createStmt.tableElts)) {
        for (const elt of createStmt.tableElts) {
          if (elt.ColumnDef && elt.ColumnDef.colname) {
            colSet.add(elt.ColumnDef.colname.toLowerCase());
          }
        }
      }
    }

    // 2. ALTER TABLE
    if (stmt.AlterTableStmt) {
      const alterStmt = stmt.AlterTableStmt;
      const rel = alterStmt.relation;
      const tableName = rel.relname;
      const colSet = getTableColumns(tableName);

      if (Array.isArray(alterStmt.cmds)) {
        for (const cmdObj of alterStmt.cmds) {
          const cmd = cmdObj.AlterTableCmd;
          if (!cmd) continue;
          if (cmd.subtype === 'AT_AddColumn' || cmd.subtype === 0) {
            if (cmd.def && cmd.def.ColumnDef && cmd.def.ColumnDef.colname) {
              colSet.add(cmd.def.ColumnDef.colname.toLowerCase());
            }
          }
          if (cmd.subtype === 'AT_DropColumn' || cmd.subtype === 12) {
            if (cmd.name) {
              colSet.delete(cmd.name.toLowerCase());
            }
          }
        }
      }
    }

    // 3. DO block containing nested DDL statements
    if (stmt.DoStmt) {
      if (Array.isArray(stmt.DoStmt.args)) {
        for (const arg of stmt.DoStmt.args) {
          if (arg.DefElem && arg.DefElem.arg && arg.DefElem.arg.String && arg.DefElem.arg.String.sval) {
            const body = arg.DefElem.arg.String.sval;
            const alterRegex = /ALTER\s+TABLE(?:\s+IF\s+EXISTS)?\s+(?:public\.)?([a-zA-Z0-9_]+)\s+ADD\s+COLUMN(?:\s+IF\s+NOT\s+EXISTS)?\s+([a-zA-Z0-9_]+)/gi;
            let m;
            while ((m = alterRegex.exec(body)) !== null) {
              const tbl = m[1].toLowerCase();
              const col = m[2].toLowerCase();
              getTableColumns(tbl).add(col);
            }
          }
        }
      }
    }
  }
}

async function buildSchemaCatalog(migrationsDir) {
  const files = fs
    .readdirSync(migrationsDir)
    .filter((f) => f.endsWith('.sql'))
    .sort();

  const tables = new Map();

  for (const file of files) {
    const fullPath = path.join(migrationsDir, file);
    const sql = fs.readFileSync(fullPath, 'utf8');
    await parseSqlStatements(sql, tables);
  }

  return tables;
}

function extractAllReferencedColumns(sql, tables) {
  const refs = new Map(); // "table.column" -> { table, column }

  function addRef(tbl, col) {
    if (!tbl || !col) return;
    const table = tbl.toLowerCase().trim();
    const column = col.toLowerCase().trim();
    if (!tables.has(table)) return;
    const key = `${table}.${column}`;
    refs.set(key, { table, column });
  }

  // 1. Record variable field references: <record_var>.<col>
  const recordMap = {
    'v_appt': 'appointments',
    'v_appointment': 'appointments',
    'v_broadcast': 'ambulance_broadcasts',
    'v_contact': 'ambulance_trip_contacts',
    'v_contacts': 'ambulance_trip_contacts',
    'v_driver': 'ambulances',
    'v_booking': 'lab_bookings',
    'v_order': 'lab_orders',
    'v_delivery': 'pharmacy_deliveries',
    'v_doc': 'doctors',
    'p': 'patients',
    'fm': 'family_members',
    'l': 'labs',
    'd': 'doctors',
    'ms': 'medical_stores',
    'pdl': 'patient_doctor_links',
    'ar': 'ambulance_requests',
    'sc': 'system_config',
  };

  const dotRegex = /\b(v_appt|v_appointment|v_broadcast|v_contact|v_contacts|v_driver|v_booking|v_order|v_delivery|v_doc|p|fm|l|d|ms|pdl|ar|sc)\.([a-zA-Z0-9_]+)\b/g;
  let m;
  while ((m = dotRegex.exec(sql)) !== null) {
    const targetTable = recordMap[m[1]];
    if (targetTable) {
      addRef(targetTable, m[2]);
    }
  }

  // 2. Query alias 'a':
  // In ambulance queries: public.ambulances a -> a.ambulance_id, a.auth_uid
  // In appointment queries: public.appointments a -> a.doctor_id, a.patient_id
  const ambQueryRegex = /FROM\s+public\.ambulances\s+a\s+WHERE\s+([^;]+)/gi;
  while ((m = ambQueryRegex.exec(sql)) !== null) {
    const whereClause = m[1];
    const aRegex = /\ba\.([a-zA-Z0-9_]+)\b/g;
    let am;
    while ((am = aRegex.exec(whereClause)) !== null) {
      addRef('ambulances', am[1]);
    }
  }

  const apptQueryRegex = /FROM\s+public\.appointments\s+a\s+WHERE\s+([^;]+)/gi;
  while ((m = apptQueryRegex.exec(sql)) !== null) {
    const whereClause = m[1];
    const aRegex = /\ba\.([a-zA-Z0-9_]+)\b/g;
    let am;
    while ((am = aRegex.exec(whereClause)) !== null) {
      addRef('appointments', am[1]);
    }
  }

  // 3. Trigger references: OLD.<col> and NEW.<col>
  // trg_lock_ambulance_broadcast_status -> operates on ambulance_broadcasts
  const ambTrigIdx = sql.indexOf('private.trg_lock_ambulance_broadcast_status');
  if (ambTrigIdx !== -1) {
    const block = sql.substring(ambTrigIdx, sql.indexOf('CREATE TRIGGER trg_lock_ambulance_broadcast_status', ambTrigIdx));
    const triggerDot = /\b(OLD|NEW)\.([a-zA-Z0-9_]+)\b/g;
    let tm;
    while ((tm = triggerDot.exec(block)) !== null) {
      addRef('ambulance_broadcasts', tm[2]);
    }
  }

  // trg_users_guard_insert -> operates on users
  const usersTrigIdx = sql.indexOf('private.trg_users_guard_insert');
  if (usersTrigIdx !== -1) {
    const block = sql.substring(usersTrigIdx, sql.indexOf('CREATE TRIGGER trg_users_guard_insert', usersTrigIdx));
    const triggerDot = /\b(OLD|NEW)\.([a-zA-Z0-9_]+)\b/g;
    let tm;
    while ((tm = triggerDot.exec(block)) !== null) {
      addRef('users', tm[2]);
    }
  }

  // trg_users_lock_role -> lock_columns('role', 'profile_id', 'firebase_uid', 'email', 'mobile')
  const lockMatch = sql.match(/private\.lock_columns\(([^)]+)\)/);
  if (lockMatch) {
    const cols = lockMatch[1].split(',').map((c) => c.replace(/['"\s]/g, ''));
    for (const c of cols) {
      addRef('users', c);
    }
  }

  // 4. Direct Table References: appointments.<col>, prescriptions.<col>, etc.
  const tblDotRegex = /\b(appointments|prescriptions|prescription_medicines|prescription_investigations|prescription_referrals|pharmacy_deliveries|pharmacy_delivery_medicines|ambulance_broadcasts|ambulance_requests|ambulance_trip_contacts|ambulance_locations|ambulance_location_updates|lab_bookings|lab_orders|doctors|patients|users)\.([a-zA-Z0-9_]+)\b/g;
  while ((m = tblDotRegex.exec(sql)) !== null) {
    addRef(m[1], m[2]);
  }

  // 5. INSERT INTO public.<table> (col1, col2, ...)
  const insertRegex = /INSERT\s+INTO\s+public\.([a-zA-Z0-9_]+)\s*\(([^)]+)\)/gi;
  while ((m = insertRegex.exec(sql)) !== null) {
    const tbl = m[1];
    const colList = m[2].split(',').map((c) => c.trim());
    for (const c of colList) {
      if (c && /^[a-zA-Z0-9_]+$/.test(c)) {
        addRef(tbl, c);
      }
    }
  }

  // 6. UPDATE public.<table> SET col1 = expr1, col2 = expr2 ...
  const updateRegex = /UPDATE\s+public\.([a-zA-Z0-9_]+)\s+SET\s+([^;]+?)(?:WHERE|RETURNING|;)/gis;
  while ((m = updateRegex.exec(sql)) !== null) {
    const tbl = m[1];
    const setBlock = m[2];
    // Match line-level or comma-separated assignments: col = expr
    const lines = setBlock.split(/\r?\n|,/);
    for (const line of lines) {
      const eqIdx = line.indexOf('=');
      if (eqIdx !== -1) {
        const lhs = line.substring(0, eqIdx).trim().split(/\s+/).pop();
        if (lhs && /^[a-zA-Z0-9_]+$/.test(lhs)) {
          addRef(tbl, lhs);
        }
      }
    }
  }

  // 7. Statements with single table: WHERE, ORDER BY, SELECT list, ON CONFLICT, RETURNING
  // SELECT ... FROM public.<table> [alias] [WHERE ...] [ORDER BY ...]
  const selectStmtRegex = /SELECT\s+([^;]+?)\s+FROM\s+public\.([a-zA-Z0-9_]+)(?:\s+([a-zA-Z0-9_]+))?\s*(?:WHERE\s+([^;]+?))?(?:ORDER\s+BY\s+([^;]+?))?(?:LIMIT\s+[^;]+?)?;/gis;
  while ((m = selectStmtRegex.exec(sql)) !== null) {
    const tbl = m[2].toLowerCase();
    const alias = m[3] ? m[3].toLowerCase() : null;
    if (alias && !['where', 'left', 'right', 'inner', 'outer', 'join', 'on', 'limit', 'group', 'order'].includes(alias)) {
      recordMap[alias] = tbl;
    }
    const colSet = tables.get(tbl);
    if (colSet) {
      const combinedClauses = `${m[1]} ${m[4] || ''} ${m[5] || ''}`;
      const tokens = combinedClauses.match(/\b[a-zA-Z0-9_]+\b/g) || [];
      for (const tok of tokens) {
        if (colSet.has(tok.toLowerCase())) {
          addRef(tbl, tok);
        }
      }
    }
  }

  // UPDATE public.<table> SET ... WHERE ...
  const updateWhereRegex = /UPDATE\s+public\.([a-zA-Z0-9_]+)\s+SET\s+([^;]+?)(?:\s+WHERE\s+([^;]+?))?(?:\s+RETURNING\s+([^;]+?))?;/gis;
  while ((m = updateWhereRegex.exec(sql)) !== null) {
    const tbl = m[1].toLowerCase();
    const colSet = tables.get(tbl);
    if (colSet) {
      const combined = `${m[2]} ${m[3] || ''} ${m[4] || ''}`;
      const tokens = combined.match(/\b[a-zA-Z0-9_]+\b/g) || [];
      for (const tok of tokens) {
        if (colSet.has(tok.toLowerCase())) {
          addRef(tbl, tok);
        }
      }
    }
  }

  // DELETE FROM public.<table> WHERE ...
  const deleteWhereRegex = /DELETE\s+FROM\s+public\.([a-zA-Z0-9_]+)(?:\s+WHERE\s+([^;]+?))?;/gis;
  while ((m = deleteWhereRegex.exec(sql)) !== null) {
    const tbl = m[1].toLowerCase();
    const colSet = tables.get(tbl);
    if (colSet && m[2]) {
      const tokens = m[2].match(/\b[a-zA-Z0-9_]+\b/g) || [];
      for (const tok of tokens) {
        if (colSet.has(tok.toLowerCase())) {
          addRef(tbl, tok);
        }
      }
    }
  }

  // ON CONFLICT (...) DO UPDATE ...
  const onConflictRegex = /ON\s+CONFLICT\s*\(([^)]+)\)/gi;
  while ((m = onConflictRegex.exec(sql)) !== null) {
    const cols = m[1].split(',').map((c) => c.trim().toLowerCase());
    const beforeText = sql.substring(Math.max(0, m.index - 300), m.index);
    const tblMatch = beforeText.match(/INSERT\s+INTO\s+public\.([a-zA-Z0-9_]+)/i);
    if (tblMatch) {
      const tbl = tblMatch[1].toLowerCase();
      for (const c of cols) {
        addRef(tbl, c);
      }
    }
  }

  return Array.from(refs.values()).sort((a, b) => `${a.table}.${a.column}`.localeCompare(`${b.table}.${b.column}`));
}

async function main() {
  const migrationsDir = path.resolve(__dirname, '../../db/migrations');
  console.log(`Analyzing migrations in ${migrationsDir}...`);
  const tables = await buildSchemaCatalog(migrationsDir);

  console.log(`\nCatalog collected ${tables.size} tables across all migrations.\n`);

  const newSqlPath = path.join(migrationsDir, '20261026000001_rpc_null_safe_authz.sql');
  const newSql = fs.readFileSync(newSqlPath, 'utf8');

  console.log('=== AUTOMATIC EXTRACTION & VERIFICATION OF FUNCTION/TRIGGER COLUMN REFERENCES ===');
  const extractedRefs = extractAllReferencedColumns(newSql, tables);
  console.log(`Extracted ${extractedRefs.length} distinct column/field references from 20261026000001_rpc_null_safe_authz.sql:\n`);

  let autoFailures = 0;
  for (const ref of extractedRefs) {
    const colSet = tables.get(ref.table);
    if (!colSet) {
      console.log(`[FAIL] Table missing from schema: ${ref.table}`);
      autoFailures++;
    } else if (colSet.has(ref.column)) {
      console.log(`[PASS] ${ref.table}.${ref.column}`);
    } else {
      console.log(`[FAIL] Column missing from schema: ${ref.table}.${ref.column}`);
      autoFailures++;
    }
  }

  // Auditing Phantom Columns
  const purgedChecks = [
    { table: 'appointments', column: 'payment_status' },
    { table: 'appointments', column: 'consultation_fee' },
    { table: 'pharmacy_delivery_medicines', column: 'dispensed_quantity' },
    { table: 'pharmacy_delivery_medicines', column: 'substituted_medicine_name' },
    { table: 'pharmacy_delivery_medicines', column: 'substituted_dosage' },
    { table: 'pharmacy_delivery_medicines', column: 'status' }
  ];

  console.log('\n=== AUDITING PHANTOM COLUMNS (MUST NOT EXIST IN FUNCTION BODIES) ===');
  let phantomFailures = 0;
  for (const p of purgedChecks) {
    const inSchema = tables.get(p.table.toLowerCase())?.has(p.column.toLowerCase());
    let inNewFunctionBodies = false;
    if (p.table === 'pharmacy_delivery_medicines') {
      const idx = newSql.indexOf('UPDATE public.pharmacy_delivery_medicines');
      const pharmacyBlock = idx !== -1 ? newSql.substring(idx, newSql.indexOf(';', idx)) : '';
      inNewFunctionBodies = pharmacyBlock.includes(p.column);
    } else {
      inNewFunctionBodies = newSql.includes(p.column);
    }
    console.log(`Column ${p.table}.${p.column}: inSchema=${Boolean(inSchema)}, inNewFunctionBodies=${inNewFunctionBodies}`);
    if (inNewFunctionBodies) {
      console.log(`  [ALERT] Phantom column "${p.column}" still referenced in 20261026000001!`);
      phantomFailures++;
    } else {
      console.log(`  [CLEAN] Phantom column "${p.column}" is not in new function bodies.`);
    }
  }

  console.log(`\n======================================================`);
  console.log(`Summary:`);
  console.log(`  Total Extracted Column References: ${extractedRefs.length}`);
  console.log(`  Reference Schema Verification Failures: ${autoFailures}`);
  console.log(`  Phantom Column References in New SQL: ${phantomFailures}`);
  console.log(`======================================================\n`);

  if (autoFailures > 0 || phantomFailures > 0) {
    process.exit(1);
  }
  return { tables, extractedRefs };
}

if (require.main === module) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}

module.exports = { buildSchemaCatalog, extractAllReferencedColumns };

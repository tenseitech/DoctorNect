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

async function main() {
  const migrationsDir = path.resolve(__dirname, '../../db/migrations');
  console.log(`Analyzing migrations in ${migrationsDir}...`);
  const tables = await buildSchemaCatalog(migrationsDir);

  console.log(`\nCatalog collected ${tables.size} tables across all migrations.\n`);

  // Verification checklist per Requirement 2:
  // 1. Verify existence of valid schema columns referenced in the new definitions
  const validChecks = [
    { table: 'doctors', column: 'name' },
    { table: 'appointments', column: 'cancellation_reason' },
    { table: 'appointments', column: 'booked_by_uid' },
    { table: 'ambulance_broadcasts', column: 'rating' },
    { table: 'pharmacy_delivery_medicines', column: 'medicine_entry_id' },
    { table: 'pharmacy_delivery_medicines', column: 'availability' },
    { table: 'pharmacy_delivery_medicines', column: 'substitute_name' },
    { table: 'prescriptions', column: 'prescription_id' },
    { table: 'prescriptions', column: 'doctor_id' },
    { table: 'prescriptions', column: 'patient_id' },
    { table: 'prescriptions', column: 'appointment_id' },
    { table: 'prescription_medicines', column: 'prescription_id' },
    { table: 'prescription_medicines', column: 'name' },
    { table: 'prescription_medicines', column: 'dosage' },
    { table: 'prescription_investigations', column: 'prescription_id' },
    { table: 'prescription_investigations', column: 'name' },
    { table: 'prescription_referrals', column: 'prescription_id' },
    { table: 'patient_doctor_links', tableOnly: true }
  ];

  console.log('=== VERIFYING REQUISITE SCHEMA COLUMNS & TABLES ===');
  let validFailures = 0;
  for (const c of validChecks) {
    const tableExists = tables.has(c.table.toLowerCase());
    if (!tableExists) {
      console.log(`[FAIL] Table missing: ${c.table}`);
      validFailures++;
      continue;
    }
    if (c.tableOnly) {
      console.log(`[PASS] Table exists: ${c.table} (${tables.get(c.table.toLowerCase()).size} columns)`);
      continue;
    }
    const cols = tables.get(c.table.toLowerCase());
    const hasCol = cols.has(c.column.toLowerCase());
    if (hasCol) {
      console.log(`[PASS] ${c.table}.${c.column}`);
    } else {
      console.log(`[FAIL] Column missing: ${c.table}.${c.column}`);
      validFailures++;
    }
  }

  // 2. Verify that non-existent/phantom columns were purged from 20261026000001
  const purgedChecks = [
    { table: 'appointments', column: 'payment_status' },
    { table: 'appointments', column: 'consultation_fee' },
    { table: 'pharmacy_delivery_medicines', column: 'dispensed_quantity' },
    { table: 'pharmacy_delivery_medicines', column: 'substituted_medicine_name' },
    { table: 'pharmacy_delivery_medicines', column: 'substituted_dosage' },
    { table: 'pharmacy_delivery_medicines', column: 'status' }
  ];

  console.log('\n=== AUDITING PHANTOM COLUMNS (MUST NOT EXIST IN FUNCTION BODIES) ===');
  const newSql = fs.readFileSync(path.join(migrationsDir, '20261026000001_rpc_null_safe_authz.sql'), 'utf8');
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
  console.log(`  Requisite Schema Checks Failed: ${validFailures}`);
  console.log(`  Phantom Column References in New SQL: ${phantomFailures}`);
  console.log(`======================================================\n`);

  if (validFailures > 0 || phantomFailures > 0) {
    process.exit(1);
  }
  return { tables };
}

if (require.main === module) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}

module.exports = { buildSchemaCatalog };

'use strict';

const fs = require('fs');
const path = require('path');
const { parse } = require('libpg-query');

const migrationsDir = path.resolve(__dirname, '../../db/migrations');
const files = fs.readdirSync(migrationsDir).filter(f => f.endsWith('.sql')).sort();

async function scanTableDrift() {
  console.log(`Analyzing table definitions across ${files.length} migrations...\n`);

  const tables = {}; // table_name -> [{ file, columns: [{ name, type, default, notNull }] }]

  for (const file of files) {
    const sql = fs.readFileSync(path.join(migrationsDir, file), 'utf8');
    let parsed;
    try {
      parsed = await parse(sql);
    } catch (e) {
      console.warn(`Could not parse ${file}: ${e.message}`);
      continue;
    }

    for (const raw of parsed.stmts) {
      const stmt = raw.stmt;
      if (stmt.CreateStmt) {
        const create = stmt.CreateStmt;
        const relName = create.relation.relname;
        const schema = create.relation.schemaname || 'public';
        const full = `${schema}.${relName}`.toLowerCase();

        const cols = [];
        for (const elt of (create.tableElts || [])) {
          if (elt.ColumnDef) {
            const c = elt.ColumnDef;
            const colName = c.colname;
            cols.push(colName);
          }
        }

        if (!tables[full]) {
          tables[full] = [];
        }
        tables[full].push({ file, columns: cols });
      }
    }
  }

  console.log('Tables defined multiple times:');
  for (const [full, defs] of Object.entries(tables)) {
    if (defs.length > 1) {
      console.log(`\nTable: ${full} (defined in ${defs.length} files)`);
      const first = defs[0];
      for (let i = 1; i < defs.length; i++) {
        const later = defs[i];
        const missingInFirst = later.columns.filter(c => !first.columns.includes(c));
        const missingInLater = first.columns.filter(c => !later.columns.includes(c));
        console.log(`  Comparing ${first.file} -> ${later.file}:`);
        if (missingInFirst.length > 0) {
          console.log(`    Columns in later but NOT in earlier: ${missingInFirst.join(', ')}`);
        }
        if (missingInLater.length > 0) {
          console.log(`    Columns in earlier but NOT in later: ${missingInLater.join(', ')}`);
        }
        if (missingInFirst.length === 0 && missingInLater.length === 0) {
          console.log(`    Columns match exactly.`);
        }
      }
    }
  }
}

scanTableDrift().catch(console.error);


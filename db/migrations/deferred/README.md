# Deferred migrations (not run by `migrate.js`)

Files here are **out of** `db/migrations/*.sql` glob — they do not appear in `listSharedMigrationRelPaths()`.

Move back to `db/migrations/` only after operator gates in the audit roadmap (e.g. staging RLS harness green).
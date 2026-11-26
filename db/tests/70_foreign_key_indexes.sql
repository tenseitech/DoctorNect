-- Every foreign key in public has an index whose first column is the FK column (20261126000002).
SELECT tests.check('no foreign key column without a supporting index',
  NOT EXISTS (
    SELECT 1
    FROM pg_constraint c
    WHERE c.contype = 'f' AND c.connamespace = 'public'::regnamespace
      AND NOT EXISTS (SELECT 1 FROM pg_index i WHERE i.indrelid = c.conrelid AND i.indkey[0] = c.conkey[1])
  ));

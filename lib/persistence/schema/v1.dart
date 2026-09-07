/// The tables as of schema version 1.
///
/// A quantity is three columns (numerator, denominator, unit symbol) because a
/// `Rational` holds `BigInt` values that SQLite's 64-bit `INTEGER` cannot be
/// relied on to store. A scaled quantity is five: the exact pair, the displayed
/// pair, and the shared unit.
const _createIdxRunsRecipe =
    'CREATE INDEX idx_runs_recipe ON production_runs '
    '(recipe_id, recipe_revision)';

const schemaV1Statements = <String>[
  '''
CREATE TABLE ingredients (
  id                  TEXT PRIMARY KEY,
  name                TEXT NOT NULL,
  default_unit_symbol TEXT NOT NULL,
  category            TEXT
)''',
  '''
CREATE TABLE recipes (
  id                     TEXT NOT NULL,
  revision               INTEGER NOT NULL,
  name                   TEXT NOT NULL,
  category               TEXT,
  base_yield_numerator   TEXT NOT NULL,
  base_yield_denominator TEXT NOT NULL,
  base_yield_unit        TEXT NOT NULL,
  max_batch_numerator    TEXT,
  max_batch_denominator  TEXT,
  max_batch_unit         TEXT,
  preparation_notes      TEXT NOT NULL,
  modified_at            TEXT NOT NULL,
  is_archived            INTEGER NOT NULL,
  PRIMARY KEY (id, revision)
)''',
  '''
CREATE TABLE recipe_components (
  recipe_id            TEXT NOT NULL,
  recipe_revision      INTEGER NOT NULL,
  component_id         TEXT NOT NULL,
  target_kind          TEXT NOT NULL,
  target_id            TEXT NOT NULL,
  base_numerator       TEXT,
  base_denominator     TEXT,
  base_unit            TEXT,
  behavior             TEXT NOT NULL,
  rounding_increment   TEXT,
  note                 TEXT,
  display_order        INTEGER NOT NULL,
  PRIMARY KEY (recipe_id, recipe_revision, component_id),
  FOREIGN KEY (recipe_id, recipe_revision)
    REFERENCES recipes (id, revision) ON DELETE CASCADE
)''',
  '''
CREATE TABLE production_runs (
  id                    TEXT PRIMARY KEY,
  recipe_id             TEXT NOT NULL,
  recipe_revision       INTEGER NOT NULL,
  target_numerator      TEXT NOT NULL,
  target_denominator    TEXT NOT NULL,
  target_unit           TEXT NOT NULL,
  created_at            TEXT NOT NULL,
  result_json           TEXT NOT NULL
)''',
  // No PRIMARY KEY here: SQLite treats NULLs in a PRIMARY KEY or UNIQUE
  // index as distinct from one another, so a composite key that includes
  // the nullable component_id would not reject a second insert of the same
  // (run_id, warning_kind, recipe_id, NULL) tuple — it would permit the
  // duplicate. The two partial unique indexes below are what actually
  // enforce one row per acknowledgement, for the with-component and
  // without-component shapes separately.
  '''
CREATE TABLE run_acknowledgements (
  run_id       TEXT NOT NULL,
  warning_kind TEXT NOT NULL,
  recipe_id    TEXT NOT NULL,
  component_id TEXT,
  FOREIGN KEY (run_id) REFERENCES production_runs (id) ON DELETE CASCADE
)''',
  '''
CREATE TABLE run_overrides (
  run_id       TEXT NOT NULL,
  recipe_id    TEXT NOT NULL,
  component_id TEXT NOT NULL,
  numerator    TEXT NOT NULL,
  denominator  TEXT NOT NULL,
  unit_symbol  TEXT NOT NULL,
  PRIMARY KEY (run_id, recipe_id, component_id),
  FOREIGN KEY (run_id) REFERENCES production_runs (id) ON DELETE CASCADE
)''',
  _createIdxRunsRecipe,
  'CREATE INDEX idx_runs_created ON production_runs (created_at DESC)',
  '''
CREATE UNIQUE INDEX idx_ack_with_component
  ON run_acknowledgements (run_id, warning_kind, recipe_id, component_id)
  WHERE component_id IS NOT NULL
''',
  '''
CREATE UNIQUE INDEX idx_ack_without_component
  ON run_acknowledgements (run_id, warning_kind, recipe_id)
  WHERE component_id IS NULL
''',
];

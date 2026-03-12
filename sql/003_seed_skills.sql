INSERT INTO shared.skills (
    name,
    applies_to_kind,
    stage,
    execution_mode,
    description,
    inputs_required,
    outputs_expected,
    source_refs,
    known_failures,
    metadata
)
VALUES
(
    'inspect-live-schema-before-modeling',
    NULL,
    'mechanical',
    'mechanical',
    'Inspect the existing live PostgreSQL schema and stored data before designing new tables or migration steps, so the new model is grounded in actual usage rather than assumptions.',
    '["database connection","schema names or target tables"]'::jsonb,
    '["verified schema shape","design constraints","detected drift from docs"]'::jsonb,
    '["polyaccess.shared.databases","polyaccess.shared.source_discovery","threehorse.shared.*"]'::jsonb,
    '["designing from stale docs","missing live-data edge cases","reinventing solved structures"]'::jsonb,
    '{"category":"rebuild-discipline","seeded":true}'::jsonb
),
(
    'bootstrap-shared-substrate',
    'schema',
    'refactored',
    'mechanical',
    'Create the foundational shared schema, canonical tables, indexes, and views that the new system will use as its semantic substrate.',
    '["PostgreSQL database","foundation SQL","install script"]'::jsonb,
    '["shared schema","base tables","core indexes","current view"]'::jsonb,
    '["sql/001_foundation.sql","install.ps1"]'::jsonb,
    '["missing extensions","wrong schema name","non-idempotent DDL"]'::jsonb,
    '{"category":"database-foundation","seeded":true}'::jsonb
),
(
    'seed-self-describing-objects',
    'object',
    'refactored',
    'mechanical',
    'Insert system-owned object records that describe the substrate itself, so the platform can introspect and test its own shared structures through the same object model it uses for applications.',
    '["shared.databases row for system container","shared.objects","shared.object_edges"]'::jsonb,
    '["system container","schema object","table objects","view objects","descriptive edges"]'::jsonb,
    '["sql/002_seed_shared_objects.sql"]'::jsonb,
    '["partial seed application","duplicate edges without uniqueness","substrate not self-describing"]'::jsonb,
    '{"category":"self-description","seeded":true}'::jsonb
),
(
    'apply-ordered-sql-migrations',
    'schema',
    'mechanical',
    'mechanical',
    'Apply numbered SQL files in deterministic name order so schema creation and seed data can evolve incrementally without a single monolithic setup script.',
    '["sql directory with ordered files","psql executable"]'::jsonb,
    '["repeatable schema application","ordered seeds","incremental migration path"]'::jsonb,
    '["install.ps1"]'::jsonb,
    '["out-of-order application","missing migration files","manual schema drift"]'::jsonb,
    '{"category":"migration","seeded":true}'::jsonb
),
(
    'resolve-local-postgres-installation',
    NULL,
    'mechanical',
    'mechanical',
    'Locate a usable local PostgreSQL client installation on Windows by checking common install paths and falling back to an explicit override when needed.',
    '["Windows machine","optional explicit psql path"]'::jsonb,
    '["working psql path","fewer environment-specific setup failures"]'::jsonb,
    '["install.ps1"]'::jsonb,
    '["psql missing from PATH","version-specific hardcoding","installer failure on another machine"]'::jsonb,
    '{"category":"environment","seeded":true}'::jsonb
),
(
    'separate-object-import-from-runtime-instantiation',
    'object',
    'raw',
    'mechanical',
    'Import and store all discovered objects in shared first, then create runtime tables, views, and executable database artifacts as a later distinct phase.',
    '["source discovery manifest","database container","canonical object store"]'::jsonb,
    '["all imported objects in shared","clear boundary before runtime materialization"]'::jsonb,
    '["README.md design notes"]'::jsonb,
    '["mixing semantic import with runtime DDL too early","harder traceability","premature coupling to tenant schemas"]'::jsonb,
    '{"category":"import-architecture","seeded":true}'::jsonb
),
(
    'reference-driven-rebuild',
    NULL,
    'refactored',
    'hybrid',
    'When rebuilding a subsystem, inspect the old code and live data first, identify the real invariants, and only then implement the new layer. Do not reinvent behavior that already encodes hard-won knowledge.',
    '["legacy repo","live database","target subsystem"]'::jsonb,
    '["captured invariants","lower redesign risk","less knowledge loss across model changes"]'::jsonb,
    '["design discussion","polyaccess inspection","threehorse foundation work"]'::jsonb,
    '["blank-slate rewriting","losing Access import complexity","recreating old bugs"]'::jsonb,
    '{"category":"rebuild-discipline","seeded":true}'::jsonb
),
(
    'optimize-for-llm-traction',
    NULL,
    'refactored',
    'mechanical',
    'Structure the codebase and data model for maximum traction from an LLM: prefer complete self-contained objects, explicit lineage, consistent shapes, and durable provenance over human-oriented convenience or implicit mutation.',
    '["canonical object model","stage lineage","documentation and skills"]'::jsonb,
    '["LLM-readable substrate","safer traceability across layers","less hidden coupling in future transformations"]'::jsonb,
    '["README.md core principle","design discussions on layered objects"]'::jsonb,
    '["human-only abstractions","diff-only storage as the primary model","undocumented transformations","special-case-heavy schemas"]'::jsonb,
    '{"category":"llm-first-design","seeded":true}'::jsonb
)
ON CONFLICT (name) DO UPDATE SET
    applies_to_kind = EXCLUDED.applies_to_kind,
    stage = EXCLUDED.stage,
    execution_mode = EXCLUDED.execution_mode,
    description = EXCLUDED.description,
    inputs_required = EXCLUDED.inputs_required,
    outputs_expected = EXCLUDED.outputs_expected,
    source_refs = EXCLUDED.source_refs,
    known_failures = EXCLUDED.known_failures,
    metadata = EXCLUDED.metadata;

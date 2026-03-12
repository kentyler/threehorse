INSERT INTO shared.databases (
    database_id,
    name,
    schema_name,
    source_kind,
    description,
    metadata
)
VALUES (
    'threehorse_system',
    'Threehorse System',
    'shared',
    'native',
    'System container for objects that describe the shared substrate itself.',
    '{"role":"system","seeded":true}'::jsonb
)
ON CONFLICT (database_id) DO UPDATE SET
    name = EXCLUDED.name,
    schema_name = EXCLUDED.schema_name,
    source_kind = EXCLUDED.source_kind,
    description = EXCLUDED.description,
    metadata = EXCLUDED.metadata;

INSERT INTO shared.objects (
    database_id,
    kind,
    name,
    origin,
    stage,
    status,
    description,
    source_ref,
    payload,
    metadata,
    created_by
)
VALUES
(
    'threehorse_system',
    'schema',
    'shared',
    'native',
    'refactored',
    'current',
    'Canonical shared metadata schema for the Threehorse substrate.',
    '{"schema":"shared"}'::jsonb,
    '{"tables":["databases","source_discovery","objects","object_edges","skills"],"views":["current_objects"]}'::jsonb,
    '{"seeded":true}'::jsonb,
    'seed'
),
(
    'threehorse_system',
    'table',
    'shared.databases',
    'native',
    'refactored',
    'current',
    'Container records for all databases managed by the platform.',
    '{"schema":"shared","table":"databases"}'::jsonb,
    '{"columns":[{"name":"database_id","type":"text"},{"name":"name","type":"text"},{"name":"schema_name","type":"text"},{"name":"source_kind","type":"text"},{"name":"description","type":"text"},{"name":"metadata","type":"jsonb"},{"name":"created_at","type":"timestamptz"},{"name":"archived_at","type":"timestamptz"}]}'::jsonb,
    '{"seeded":true,"purpose":"database containers"}'::jsonb,
    'seed'
),
(
    'threehorse_system',
    'table',
    'shared.source_discovery',
    'native',
    'refactored',
    'current',
    'Raw discovery manifests for imported sources before object materialization.',
    '{"schema":"shared","table":"source_discovery"}'::jsonb,
    '{"columns":[{"name":"discovery_id","type":"uuid"},{"name":"database_id","type":"text"},{"name":"source_path","type":"text"},{"name":"discovery","type":"jsonb"},{"name":"created_by","type":"text"},{"name":"created_at","type":"timestamptz"}]}'::jsonb,
    '{"seeded":true,"purpose":"raw import manifests"}'::jsonb,
    'seed'
),
(
    'threehorse_system',
    'table',
    'shared.objects',
    'native',
    'refactored',
    'current',
    'Canonical store for imported, native, and derived objects.',
    '{"schema":"shared","table":"objects"}'::jsonb,
    '{"columns":[{"name":"object_id","type":"uuid"},{"name":"database_id","type":"text"},{"name":"discovery_id","type":"uuid"},{"name":"kind","type":"text"},{"name":"name","type":"text"},{"name":"origin","type":"text"},{"name":"stage","type":"text"},{"name":"status","type":"text"},{"name":"parent_object_id","type":"uuid"},{"name":"replaces_object_id","type":"uuid"},{"name":"description","type":"text"},{"name":"source_ref","type":"jsonb"},{"name":"payload","type":"jsonb"},{"name":"metadata","type":"jsonb"},{"name":"created_by","type":"text"},{"name":"created_at","type":"timestamptz"}]}'::jsonb,
    '{"seeded":true,"purpose":"canonical object substrate"}'::jsonb,
    'seed'
),
(
    'threehorse_system',
    'table',
    'shared.object_edges',
    'native',
    'refactored',
    'current',
    'Relationships between objects, including lineage and semantic links.',
    '{"schema":"shared","table":"object_edges"}'::jsonb,
    '{"columns":[{"name":"edge_id","type":"uuid"},{"name":"database_id","type":"text"},{"name":"from_object_id","type":"uuid"},{"name":"to_object_id","type":"uuid"},{"name":"relationship","type":"text"},{"name":"metadata","type":"jsonb"},{"name":"created_at","type":"timestamptz"}]}'::jsonb,
    '{"seeded":true,"purpose":"object graph edges"}'::jsonb,
    'seed'
),
(
    'threehorse_system',
    'table',
    'shared.skills',
    'native',
    'refactored',
    'current',
    'Catalog of import and transformation competencies used during migration.',
    '{"schema":"shared","table":"skills"}'::jsonb,
    '{"columns":[{"name":"skill_id","type":"uuid"},{"name":"name","type":"text"},{"name":"applies_to_kind","type":"text"},{"name":"stage","type":"text"},{"name":"execution_mode","type":"text"},{"name":"description","type":"text"},{"name":"inputs_required","type":"jsonb"},{"name":"outputs_expected","type":"jsonb"},{"name":"source_refs","type":"jsonb"},{"name":"known_failures","type":"jsonb"},{"name":"metadata","type":"jsonb"},{"name":"created_at","type":"timestamptz"}]}'::jsonb,
    '{"seeded":true,"purpose":"import skill catalog"}'::jsonb,
    'seed'
),
(
    'threehorse_system',
    'view',
    'shared.current_objects',
    'native',
    'refactored',
    'current',
    'Convenience view exposing current objects only.',
    '{"schema":"shared","view":"current_objects"}'::jsonb,
    '{"depends_on":["shared.objects"],"filter":{"status":"current"}}'::jsonb,
    '{"seeded":true,"purpose":"current object projection"}'::jsonb,
    'seed'
)
ON CONFLICT (database_id, kind, name) WHERE status = 'current'
DO UPDATE SET
    description = EXCLUDED.description,
    source_ref = EXCLUDED.source_ref,
    payload = EXCLUDED.payload,
    metadata = EXCLUDED.metadata,
    created_by = EXCLUDED.created_by;

INSERT INTO shared.object_edges (
    database_id,
    from_object_id,
    to_object_id,
    relationship,
    metadata
)
SELECT
    'threehorse_system',
    schema_object.object_id,
    member_object.object_id,
    'contains',
    '{"seeded":true}'::jsonb
FROM shared.objects schema_object
JOIN shared.objects member_object
    ON member_object.database_id = 'threehorse_system'
   AND member_object.name IN (
        'shared.databases',
        'shared.source_discovery',
        'shared.objects',
        'shared.object_edges',
        'shared.skills',
        'shared.current_objects'
   )
WHERE schema_object.database_id = 'threehorse_system'
  AND schema_object.kind = 'schema'
  AND schema_object.name = 'shared'
ON CONFLICT DO NOTHING;

INSERT INTO shared.object_edges (
    database_id,
    from_object_id,
    to_object_id,
    relationship,
    metadata
)
SELECT
    'threehorse_system',
    view_object.object_id,
    table_object.object_id,
    'depends_on',
    '{"seeded":true}'::jsonb
FROM shared.objects view_object
JOIN shared.objects table_object
    ON table_object.database_id = 'threehorse_system'
   AND table_object.name = 'shared.objects'
WHERE view_object.database_id = 'threehorse_system'
  AND view_object.kind = 'view'
  AND view_object.name = 'shared.current_objects'
ON CONFLICT DO NOTHING;

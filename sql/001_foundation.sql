CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE SCHEMA IF NOT EXISTS shared;

CREATE TABLE IF NOT EXISTS shared.databases (
    database_id    TEXT PRIMARY KEY,
    name           TEXT NOT NULL,
    schema_name    TEXT NOT NULL UNIQUE,
    source_kind    TEXT NOT NULL DEFAULT 'native'
        CHECK (source_kind IN ('native', 'imported')),
    description    TEXT,
    metadata       JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    archived_at    TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS shared.source_discovery (
    discovery_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    database_id    TEXT NOT NULL REFERENCES shared.databases(database_id) ON DELETE CASCADE,
    source_path    TEXT NOT NULL,
    discovery      JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_by     TEXT,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_source_discovery_database
    ON shared.source_discovery (database_id, created_at DESC);

CREATE TABLE IF NOT EXISTS shared.objects (
    object_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    database_id          TEXT NOT NULL REFERENCES shared.databases(database_id) ON DELETE CASCADE,
    discovery_id         UUID REFERENCES shared.source_discovery(discovery_id) ON DELETE SET NULL,
    kind                 TEXT NOT NULL,
    name                 TEXT NOT NULL,
    origin               TEXT NOT NULL
        CHECK (origin IN ('native', 'imported', 'derived')),
    stage                TEXT NOT NULL
        CHECK (stage IN ('raw', 'mechanical', 'llm-assisted', 'gap-resolved', 'refactored')),
    status               TEXT NOT NULL DEFAULT 'current'
        CHECK (status IN ('draft', 'current', 'superseded', 'archived')),
    parent_object_id     UUID REFERENCES shared.objects(object_id),
    replaces_object_id   UUID REFERENCES shared.objects(object_id),
    description          TEXT,
    source_ref           JSONB NOT NULL DEFAULT '{}'::jsonb,
    payload              JSONB NOT NULL DEFAULT '{}'::jsonb,
    metadata             JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_by           TEXT,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_objects_current_name
    ON shared.objects (database_id, kind, name)
    WHERE status = 'current';

CREATE INDEX IF NOT EXISTS idx_objects_database_kind
    ON shared.objects (database_id, kind);

CREATE INDEX IF NOT EXISTS idx_objects_stage
    ON shared.objects (stage);

CREATE INDEX IF NOT EXISTS idx_objects_parent
    ON shared.objects (parent_object_id);

CREATE INDEX IF NOT EXISTS idx_objects_discovery
    ON shared.objects (discovery_id);

CREATE INDEX IF NOT EXISTS idx_objects_payload_gin
    ON shared.objects USING GIN (payload);

CREATE TABLE IF NOT EXISTS shared.object_edges (
    edge_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    database_id      TEXT NOT NULL REFERENCES shared.databases(database_id) ON DELETE CASCADE,
    from_object_id   UUID NOT NULL REFERENCES shared.objects(object_id) ON DELETE CASCADE,
    to_object_id     UUID NOT NULL REFERENCES shared.objects(object_id) ON DELETE CASCADE,
    relationship     TEXT NOT NULL,
    metadata         JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_no_self_edge CHECK (from_object_id <> to_object_id)
);

CREATE INDEX IF NOT EXISTS idx_edges_database
    ON shared.object_edges (database_id, relationship);

CREATE INDEX IF NOT EXISTS idx_edges_from
    ON shared.object_edges (from_object_id, relationship);

CREATE INDEX IF NOT EXISTS idx_edges_to
    ON shared.object_edges (to_object_id, relationship);

CREATE UNIQUE INDEX IF NOT EXISTS idx_edges_unique
    ON shared.object_edges (database_id, from_object_id, to_object_id, relationship);

CREATE TABLE IF NOT EXISTS shared.skills (
    skill_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name             TEXT NOT NULL UNIQUE,
    applies_to_kind  TEXT,
    stage            TEXT
        CHECK (stage IS NULL OR stage IN ('raw', 'mechanical', 'llm-assisted', 'gap-resolved', 'refactored')),
    execution_mode   TEXT NOT NULL DEFAULT 'mechanical'
        CHECK (execution_mode IN ('mechanical', 'llm', 'hybrid', 'manual')),
    description      TEXT NOT NULL,
    inputs_required  JSONB NOT NULL DEFAULT '[]'::jsonb,
    outputs_expected JSONB NOT NULL DEFAULT '[]'::jsonb,
    source_refs      JSONB NOT NULL DEFAULT '[]'::jsonb,
    known_failures   JSONB NOT NULL DEFAULT '[]'::jsonb,
    metadata         JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE OR REPLACE VIEW shared.current_objects AS
SELECT *
FROM shared.objects
WHERE status = 'current';

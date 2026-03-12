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
    'import-raw-access-definitions',
    'object',
    'raw',
    'hybrid',
    'Register an imported application container, append a source discovery manifest, then copy raw Access object definitions into shared.objects without creating runtime tables, views, or loading row data.',
    '["Access .accdb path","legacy access export scripts","threehorse shared schema"]'::jsonb,
    '["database container row","append-only discovery row","raw table/query/form/report/module/macro objects"]'::jsonb,
    '["scripts/import-access-raw.ps1","C:/Users/Ken/Desktop/AccessClone/scripts/access"]'::jsonb,
    '["reimplementing export logic instead of reusing legacy scripts","importing row data too early","creating runtime schemas during the raw pass"]'::jsonb,
    '{"category":"import-architecture","seeded":true}'::jsonb
),
(
    'reuse-legacy-access-exporters',
    NULL,
    'raw',
    'mechanical',
    'Call the existing Access PowerShell exporters directly from the new system so the first-pass importer preserves hard-won Access-specific behavior instead of reinventing it.',
    '["legacy scripts path","compatible local Access installation"]'::jsonb,
    '["stable raw exports","less regression risk in Access extraction"]'::jsonb,
    '["C:/Users/Ken/Desktop/AccessClone/scripts/access/export_*.ps1","C:/Users/Ken/Desktop/AccessClone/scripts/access/list_*.ps1"]'::jsonb,
    '["losing import knowledge across rewrites","PowerShell COM edge cases resurfacing"]'::jsonb,
    '{"category":"rebuild-discipline","seeded":true}'::jsonb
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

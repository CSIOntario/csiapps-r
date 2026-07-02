# Sandbox mode for local development

Sandbox mode lets developers run the full schema -\> validate -\> ingest
-\> retrieve warehouse workflow entirely locally, with no network access
and no authentication. Enable it globally with
`options(csiapps.sandbox = TRUE)` (or by setting the
`CSIAPPS_ENV=sandbox` environment variable), or per call with
`make_request(..., sandbox = TRUE)`. Production scripts require no
changes: the same
[`make_request()`](https://csiontario.github.io/csiapps/reference/make_request.md)
calls are routed to a local, in-memory warehouse instead of the REST
API.

The sandbox emulates three endpoints:

- `GET api/warehouse/data-sources/{uuid}` – returns the schema
  previously registered with
  [`register_sandbox_schema()`](https://csiontario.github.io/csiapps/reference/register_sandbox_schema.md),
  nested under `head_primary_definition$schema` exactly like the real
  API.

- `POST api/warehouse/ingestion/primary/` – validates `body$records`
  against the registered schema for `body$source` (using `jsonvalidate`)
  and, on success, stores them in memory and writes the JSON payload to
  a per-source folder on disk for inspection (see
  [`browse_sandbox()`](https://csiontario.github.io/csiapps/reference/browse_sandbox.md)).

- `GET api/warehouse/data-records` – returns previously ingested records
  for `query$source_uuid`, each wrapped in the same envelope (`data`,
  `subject`, `created_at`, ...) the real API returns.

Any other endpoint raises an error. Sandbox state lasts for the R
session; use
[`clear_sandbox()`](https://csiontario.github.io/csiapps/reference/clear_sandbox.md)
to reset it between tests.

## Limitations

The sandbox faithfully simulates the *schema contract*, not the
warehouse. Anything that depends on server-side state will differ from
production:

- **Validation parity is approximate.** Sandbox ingestion validates
  records against the JSON Schema with Ajv (via `jsonvalidate`), which
  catches the most common failure modes (missing required fields, wrong
  types, length and pattern violations). The real server additionally
  enforces things the schema cannot express: resolution of
  `subject_field` values against registered profiles, duplicate/dataset
  handling against existing data, and token permissions. Validator
  implementations may also differ on edge cases (e.g. `format` keyword
  enforcement). Passing sandbox validation is therefore a *necessary but
  not sufficient* condition for production acceptance – do not treat a
  green sandbox run as a guarantee.

- **`subject` is always `NULL` in retrieved records.** In production the
  server links each ingested record to a registered profile and returns
  it (name, sport, ...) in the record envelope. The sandbox has no
  profile registry, so it cannot emulate this linkage and returns
  `subject = NULL` rather than fabricating misleading data. Code that
  displays or filters on subject fields will see placeholder values, and
  mistyped `subject_field` values that production would flag are
  accepted silently.

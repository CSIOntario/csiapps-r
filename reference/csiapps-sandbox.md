# Sandbox mode for local development

Sandbox mode lets developers run the full schema -\> validate -\> ingest
-\> retrieve warehouse workflow entirely locally, with no network access
and no authentication. **Sandbox mode is enabled by default**, so that
development work never reaches the production warehouse by accident: the
same
[`make_request()`](https://csiontario.github.io/csiapps/reference/make_request.md)
calls are routed to a local, in-memory warehouse instead of the REST
API. It is disabled for deployment with
`options(csiapps.sandbox = FALSE)` (or by setting
`CSIAPPS_ENV=production`), and can be overridden per call with the
`sandbox` argument of
[`make_request()`](https://csiontario.github.io/csiapps/reference/make_request.md).
Because the production and sandbox workflows use the same calls, no code
changes are needed when moving from development to deployment.

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

## Shiny app wrappers

Sandbox mode also lets a wrapped Shiny app (see
[`ui_wrapper()`](https://csiontario.github.io/csiapps/reference/ui_wrapper.md),
[`server_wrapper()`](https://csiontario.github.io/csiapps/reference/server_wrapper.md),
[`check_secrets()`](https://csiontario.github.io/csiapps/reference/check_secrets.md))
run locally without the OAuth2 redirect. The redirect exists only to
obtain an access token, and requires client credentials that cannot be
safely distributed, so in sandbox mode
[`server_wrapper()`](https://csiontario.github.io/csiapps/reference/server_wrapper.md)
**simulates the login** instead: it seeds the session from the
developer's existing `CSIAPPS_ACCESS_TOKEN` and hands it to the same
code path a production login would. The token is used **only to emulate
the login**: if it is present, `/me` is loaded from the real API so the
header shows the developer's real identity. All *data* – sport
organizations, athletes/profiles, and warehouse records – is served from
the local sandbox (the dummy registry and the emulated warehouse), never
the live API. If no token is set, the app shell still renders but shows
an unauthenticated notice prompting the developer to set a read-only
`CSIAPPS_ACCESS_TOKEN`. The same wrapped-app code runs in both modes;
only the `csiapps.sandbox` option differs.

## Limitations

- **The access token is used only to emulate login.** A wrapped app's
  `/me` identity is fetched from the real API with your token, so set
  the institute with
  [`set_institute()`](https://csiontario.github.io/csiapps/reference/set_institute.md)
  to match the institute that issued it or `/me` is rejected. Everything
  else is dummy: sport organizations and athletes come from the local
  registry
  ([`create_sport_org()`](https://csiontario.github.io/csiapps/reference/create_sport_org.md),
  [`create_profile()`](https://csiontario.github.io/csiapps/reference/create_profile.md))
  and warehouse reads/writes are emulated in memory. No real client data
  is read.

- **Only warehouse endpoints are routed through
  [`make_request()`](https://csiontario.github.io/csiapps/reference/make_request.md).**
  Calling `make_request("api/registration/...")` in sandbox raises a
  501; use the
  [`fetch_org_options()`](https://csiontario.github.io/csiapps/reference/fetch_org_options.md)
  /
  [`fetch_profiles()`](https://csiontario.github.io/csiapps/reference/fetch_profiles.md)
  helpers, which read the dummy registry instead. In sandbox,
  [`fetch_profiles()`](https://csiontario.github.io/csiapps/reference/fetch_profiles.md)
  honours only the `sport_org_id` filter; other filters are ignored. The
  sandbox faithfully simulates the *schema contract*, not the warehouse.
  Anything that depends on server-side state will differ from
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

- **`subject` linkage is emulated only for registered athletes.** On
  retrieval the sandbox resolves each record's `subject_field` value
  against athletes registered with
  [`create_profile()`](https://csiontario.github.io/csiapps/reference/create_profile.md)
  and returns the matched athlete (id, name, sport) in the record
  envelope, mirroring production. Resolution happens at read time, so
  athletes registered after ingestion are linked on the next read. If no
  athlete matches – because none was registered or the `subject_field`
  value is mistyped – `subject` is `NULL` rather than fabricated.
  Production would reject an unresolved subject; the sandbox accepts it
  silently, so a green sandbox ingest does not guarantee the server will
  link every record.

# CSIAPPS REST API

``` r

library(csiapps)
```

### Preamble

The following environment variables must be set to make requests to the
`CSIAPPS` REST API:

- `CSIAPPS_ACCESS_TOKEN`: The access token for authenticating API
  requests. This token should have the necessary permissions to access
  the desired endpoints.

### Overview

`csiapps` includes a generic
[`make_request()`](https://csiontario.github.io/csiapps-r/reference/make_request.md)
function to make requests to the `CSIAPPS` REST API. Please refer to the
[CSIAPPS Swagger documentation](https://apps.csiontario.ca/api/swagger/)
for full details on available endpoints, parameters, and response
formats.

Below are some common use cases for interacting with the API endpoints
using `csiapps`.

> **Note:** By default, `csiapps` runs in **sandbox mode**, so the
> **warehouse**
> [`make_request()`](https://csiontario.github.io/csiapps-r/reference/make_request.md)
> calls below are routed to a local, in-memory warehouse rather than the
> production API. This lets you develop and test safely without touching
> production data. Not every endpoint is emulated, though — the
> registration and auth endpoints are not, and require
> `sandbox = FALSE`; see [Which `make_request()` calls work in
> sandbox](#sandbox-mode) at the end of this article. This article
> documents the **production** REST API semantics; for the full local
> workflow — registering orgs and athletes, schemas, ingestion, and
> retrieval against the emulated warehouse — see the dedicated [Sandbox
> Mode](https://csiontario.github.io/csiapps-r/articles/sandbox.md)
> article.

### Authorization Status

The most basic endpoint is the `/api/csiauth/me/` endpoint, which can be
used to check the status of the user making the request. This endpoint
requires authentication, so if the request is successful, it indicates
that your access token is valid and has the necessary permissions to
access the REST API. You may need to specify your institute before
authenticating.

``` r


set_institute("csiontario") # or "csipacific" (the default)

result <- make_request(
  endpoint = "api/csiauth/me/",
  sandbox  = FALSE            # /me is not emulated; it needs the real API
)
```

> **Sandbox note:** `/api/csiauth/me/` is **not** emulated by the
> sandbox, so a console `make_request("api/csiauth/me/")` in the default
> sandbox mode raises a 501. Pass `sandbox = FALSE` to reach the real
> endpoint. Inside a wrapped Shiny app, `/me` is loaded for you by the
> login simulation (see the [Sandbox
> Mode](https://csiontario.github.io/csiapps-r/articles/sandbox.md)
> article) — you don’t call it directly.

### Registration API

The registration API provides access to profiles and organisations via
[`fetch_org_options()`](https://csiontario.github.io/csiapps-r/reference/fetch_org_options.md),
[`fetch_profiles()`](https://csiontario.github.io/csiapps-r/reference/fetch_profiles.md),
and
[`fetch_profile()`](https://csiontario.github.io/csiapps-r/reference/fetch_profile.md).
The examples below pass `sandbox = FALSE` to contact the **real**
registration API. In sandbox mode (the default) these same helpers read
from a local dummy registry — see the [Sandbox
Mode](https://csiontario.github.io/csiapps-r/articles/sandbox.md)
article for that workflow.

#### Organisations

[`fetch_org_options()`](https://csiontario.github.io/csiapps-r/reference/fetch_org_options.md)
returns all organisations your token can see, formatted as
`label`/`value` pairs ready for a Shiny `selectInput()`:

``` r

set_institute("csiontario")

orgs <- fetch_org_options(sandbox = FALSE)
# list(list(label = "CSI Ontario", value = 1L), ...)
```

##### Doing this with `make_request()`

[`fetch_org_options()`](https://csiontario.github.io/csiapps-r/reference/fetch_org_options.md)
is a thin wrapper over a `GET` to the `api/registration/organization/`
endpoint. You can make the same call directly:

``` r

resp <- make_request(
  endpoint = "api/registration/organization/",
  query    = list(limit = 1000),
  sandbox  = FALSE            # registration is NOT emulated in sandbox
)
orgs <- resp$results          # each element has $id and $name
```

> **Sandbox note:** unlike the warehouse examples further down, the
> registration endpoints have **no sandbox emulation**.
> `make_request("api/registration/...")` in the default sandbox mode
> raises a 501 — you must pass `sandbox = FALSE`. In sandbox, reach for
> [`fetch_org_options()`](https://csiontario.github.io/csiapps-r/reference/fetch_org_options.md)
> instead: it reads the local dummy registry directly (see the [Sandbox
> Mode](https://csiontario.github.io/csiapps-r/articles/sandbox.md)
> article).

#### Profiles

[`fetch_profiles()`](https://csiontario.github.io/csiapps-r/reference/fetch_profiles.md)
returns all profiles accessible to your token, with automatic
pagination. Filter by organisation using `sport_org_id`:

``` r

profiles <- fetch_profiles(sandbox = FALSE)

# Filter to a specific organisation
profiles <- fetch_profiles(
  filters = list(sport_org_id = 42L),
  sandbox = FALSE
)
```

A common pattern across dashboards is converting the profile list into a
data frame for display or matching:

``` r

profile_df <- do.call(rbind, lapply(profiles, function(p) {
  data.frame(
    id         = p$id,
    first_name = p$person$first_name %||% NA_character_,
    last_name  = p$person$last_name  %||% NA_character_,
    email      = p$person$email      %||% NA_character_
  )
}))
```

[`fetch_profile()`](https://csiontario.github.io/csiapps-r/reference/fetch_profile.md)
retrieves a single profile by ID:

``` r

profile <- fetch_profile(profile_id = 123L, sandbox = FALSE)
profile$person$first_name
```

##### Doing this with `make_request()`

Both helpers wrap the `api/registration/profile/` endpoint.
[`fetch_profiles()`](https://csiontario.github.io/csiapps-r/reference/fetch_profiles.md)
paginates and returns one flat list; `make_request(paginate = TRUE)`
returns a **list of pages**, so flatten the `results` yourself:

``` r

pages <- make_request(
  endpoint = "api/registration/profile/",
  query    = list(sport_org_id = 42L),   # omit to fetch all
  paginate = TRUE,
  sandbox  = FALSE                        # registration is NOT emulated in sandbox
)
profiles <- do.call(c, lapply(pages, function(p) p$results))
```

A single profile is the same endpoint with the ID appended — the direct
equivalent of
[`fetch_profile()`](https://csiontario.github.io/csiapps-r/reference/fetch_profile.md):

``` r

profile <- make_request(
  endpoint = "api/registration/profile/123",
  sandbox  = FALSE
)
```

> **Sandbox note:** as with organisations, these calls have **no sandbox
> emulation** and raise a 501 unless `sandbox = FALSE`. Use
> [`fetch_profiles()`](https://csiontario.github.io/csiapps-r/reference/fetch_profiles.md)
> /
> [`fetch_profile()`](https://csiontario.github.io/csiapps-r/reference/fetch_profile.md)
> in sandbox — they read the local dummy registry directly.

### Data Warehouse Ingestion

To ingest data records into the warehouse, we make a POST request to the
`/api/warehouse/ingestion/primary/` endpoint. Users supply the `source`
(uuid) of the target *data source*, a list of `records` to be ingested,
and (optionally) the `subject_field` by which each record can be
uniquely assigned to a user. The records must comply with the schema
defined for the target data source.

> **Note:** The `source` uuid is provisioned by the CSIAPPS team when
> they set up the remote data warehouse for your app, and supplied
> through the `SOURCE_UUID` environment variable — the app developer
> does not choose or hard-code it. Read it as
> `Sys.getenv("SOURCE_UUID")` (as below) so the same code runs in
> development and production. See the [Sandbox
> Mode](https://csiontario.github.io/csiapps-r/articles/sandbox.md)
> article for how this works during local development.

#### JSON Schema Definition

Consider the following [JSON Schema](https://json-schema.org/learn):

``` json
{
  "title": "A registration form",
  "description": "A simple form example.",
  "type": "object",
  "required": [
    "id",
    "firstName",
    "lastName"
  ],
  "properties": {
    "id": {
      "type": "string",
      "title": "ID"
    },
    "firstName": {
      "type": "string",
      "title": "First name",
      "default": "Chuck"
    },
    "lastName": {
      "type": "string",
      "title": "Last name",
      "default": "Norris"
    },
    "age": {
      "type": "integer",
      "title": "Age"
    },
    "telephone": {
      "type": "string",
      "title": "Telephone",
      "minLength": 10
    }
  }
}
```

Here, `id` is the required field that serves as the unique user
assignment for each record.

To create records that comply with this schema, we create the following
records:

``` r

records <- list(
  list(id = "xxxx", firstName = "John", lastName = "Doe", age = 30, telephone = "1234567890"),
  list(id = "yyyy", firstName = "Jane", lastName = "Smith", age = 25, telephone = "0987654321")
)
```

To retrieve the JSON schema definition from the data warehouse, we can
make a request to the `/api/warehouse/data-sources/{uuid}/` endpoint,
where `uuid` is the uuid of the target data source. The schema
definition is located in the `head_primary_definition$schema` field of
the response.

``` r

data_source <- make_request(
  endpoint = paste0("api/warehouse/data-sources/", Sys.getenv("SOURCE_UUID"))
)

schema <- data_source$head_primary_definition$schema
```

#### Data Record Validation

We can validate data records using the `jsonlite` and `jsonvalidate`
packages. Be sure to set `auto_unbox = TRUE` when converting the JSON
objects to strings.

``` r

json_schema <- jsonvalidate::json_schema$new(jsonlite::toJSON(schema, auto_unbox = T))

validate_record <- function(record) {
  json_schema$validate(jsonlite::toJSON(record, auto_unbox = T))
}

validation_results <- sapply(records, validate_record)

stopifnot(all(validation_results))
```

Finally, we can make the API request to ingest these records into the
warehouse:

``` r

result <- make_request(
  endpoint = "api/warehouse/ingestion/primary/",
  method = "POST",
  body = list(
    source = Sys.getenv("SOURCE_UUID"),
    records = records,
    subject_field = "id"
  )
)
```

### Data Record Retrieval

To retrieve data records from the warehouse, we make an API request to
the `/api/warehouse/data-records/` endpoint. The only required parameter
is the `source_uuid` of the requested table, but there are several
optional parameters for additional filtering. Note that we can set the
`paginate = TRUE` to retrieve all records matching the query parameters.

``` r

records <- make_request(
    endpoint = "api/warehouse/data-records",
    query = list(source_uuid = Sys.getenv("SOURCE_UUID")),
    paginate = TRUE
    )
```

### Sandbox Mode

[`make_request()`](https://csiontario.github.io/csiapps-r/reference/make_request.md)
runs against a **local sandbox** by default, so pipelines can be
developed and tested with no network access, no authentication, and no
risk of writing test data to the production warehouse. Sandbox mode is
enabled by default and is turned off only at deployment.

Not every endpoint is emulated, though — and this is the one gotcha
worth internalising. The sandbox emulates the **warehouse** endpoints
but **not** the registration or auth endpoints. Calls it does not
emulate raise a **501** unless you pass `sandbox = FALSE`:

| Endpoint (`make_request`) | Default sandbox | `sandbox = FALSE` | Sandbox alternative |
|----|----|----|----|
| `api/csiauth/me/` | ✗ 501 | ✓ | login simulation (Shiny) |
| `api/registration/organization/` | ✗ 501 | ✓ | [`fetch_org_options()`](https://csiontario.github.io/csiapps-r/reference/fetch_org_options.md) |
| `api/registration/profile/` | ✗ 501 | ✓ | [`fetch_profiles()`](https://csiontario.github.io/csiapps-r/reference/fetch_profiles.md) / [`fetch_profile()`](https://csiontario.github.io/csiapps-r/reference/fetch_profile.md) |
| `api/warehouse/data-sources/{uuid}` | ✓ emulated | ✓ | — |
| `api/warehouse/ingestion/primary/` | ✓ emulated | ✓ | — |
| `api/warehouse/data-records` | ✓ emulated | ✓ | — |

In short: the **warehouse**
[`make_request()`](https://csiontario.github.io/csiapps-r/reference/make_request.md)
examples in this article work in both modes, while the
**registration/auth**
[`make_request()`](https://csiontario.github.io/csiapps-r/reference/make_request.md)
examples work only against the real API (`sandbox = FALSE`). For
registration data in sandbox, use the `fetch_*` helpers, which read the
local dummy registry directly instead of going through
[`make_request()`](https://csiontario.github.io/csiapps-r/reference/make_request.md).

The full sandbox workflow — enabling/disabling it, registering sport
orgs and athletes, registering schemas, validating, ingesting, and
retrieving records against the emulated warehouse, and inspecting or
resetting sandbox state — is documented in its own article:

**→ [Sandbox
Mode](https://csiontario.github.io/csiapps-r/articles/sandbox.md)**

See also
[`?"csiapps-sandbox"`](https://csiontario.github.io/csiapps-r/reference/csiapps-sandbox.md)
for the reference-level overview.

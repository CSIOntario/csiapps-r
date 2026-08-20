# Fetch the current AMS athlete mapping

Fetches an AMS mapping data source and returns only its current
four-column mapping. In sandbox mode, the source is expected to contain
the already-current mapping and its four data fields are returned
directly. In production, the append-only warehouse history is reduced to
the most recent record for each mapping identity, and identities whose
latest record is inactive are removed.

## Usage

``` r
fetch_ams_mapping(
  source_uuid = Sys.getenv("AMS_MAPPING_UUID"),
  token = NULL,
  sandbox = is_sandbox_mode(),
  max_pages = 50
)
```

## Arguments

- source_uuid:

  Character. AMS mapping data-source identifier. Defaults to the
  `AMS_MAPPING_UUID` environment variable.

- token:

  Character. Authentication token. When not supplied, it is resolved in
  the same way as
  [`make_request()`](https://csiontario.github.io/csiapps-r/reference/make_request.md).
  Ignored in sandbox mode.

- sandbox:

  Logical. Route to the local sandbox (`TRUE`) or production (`FALSE`).
  Defaults to
  [`is_sandbox_mode()`](https://csiontario.github.io/csiapps-r/reference/is_sandbox_mode.md).

- max_pages:

  Maximum number of production response pages to fetch.

## Value

A data frame with columns `id`, `vendor`, `vendor_profile_id`, and
`vendor_profile_name`, containing one row per current mapping.

## Examples

``` r
if (FALSE) { # \dontrun{
mapping <- fetch_ams_mapping()
} # }
```

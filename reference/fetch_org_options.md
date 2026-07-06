# Fetch organisation options from the CSIAPPS registration API

Returns all organisations accessible to the authenticated user as a list
of `label`/`value` pairs, suitable for use in Shiny `selectInput()`
choices.

## Usage

``` r
fetch_org_options(token = NULL, sandbox = is_sandbox_mode())
```

## Arguments

- token:

  Character. Authentication token. Defaults to the
  `CSIAPPS_ACCESS_TOKEN` environment variable.

- sandbox:

  Logical. When `TRUE` (the default in development), no network call is
  made and an empty list is returned immediately. Set to `FALSE` for
  production to fetch real organisations. Defaults to
  [`is_sandbox_mode()`](https://csiontario.github.io/csiapps/reference/is_sandbox_mode.md).

## Value

A list of named lists, each with `label` (organisation name) and `value`
(organisation ID).

## See also

[`fetch_profiles()`](https://csiontario.github.io/csiapps/reference/fetch_profiles.md)
to fetch profiles,
[`set_institute()`](https://csiontario.github.io/csiapps/reference/set_institute.md)
to configure the target institute.

## Examples

``` r
if (FALSE) { # \dontrun{
set_institute("csiontario")
orgs <- fetch_org_options(sandbox = FALSE)
selectInput("org", "Organisation", choices = orgs)
} # }
```

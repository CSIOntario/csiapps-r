# Fetch a single profile from the CSIAPPS registration API

Retrieves one profile by its ID.

## Usage

``` r
fetch_profile(token = NULL, profile_id, sandbox = is_sandbox_mode())
```

## Arguments

- token:

  Character. Authentication token. When not supplied, it is resolved for
  the current Shiny session (the token stored by
  [`server_wrapper()`](https://csiontario.github.io/csiapps/reference/server_wrapper.md))
  and otherwise falls back to the `CSIAPPS_ACCESS_TOKEN` environment
  variable.

- profile_id:

  Integer or character. The ID of the profile to retrieve.

- sandbox:

  Logical. When `TRUE` (the default in development), no network call is
  made and the profile is looked up in the local dummy registry (those
  created with
  [`create_profile()`](https://csiontario.github.io/csiapps/reference/create_profile.md)),
  returning `NULL` if no such id exists. Set to `FALSE` to fetch the
  real profile from the API. Defaults to
  [`is_sandbox_mode()`](https://csiontario.github.io/csiapps/reference/is_sandbox_mode.md).

## Value

A single profile object as a list, or `NULL` if no profile with that id
exists. The structure mirrors the list elements returned by
[`fetch_profiles()`](https://csiontario.github.io/csiapps/reference/fetch_profiles.md).

## See also

[`fetch_profiles()`](https://csiontario.github.io/csiapps/reference/fetch_profiles.md)
to retrieve multiple profiles,
[`set_institute()`](https://csiontario.github.io/csiapps/reference/set_institute.md)
to configure the target institute.

## Examples

``` r
if (FALSE) { # \dontrun{
set_institute("csiontario")
profile <- fetch_profile(profile_id = 123L, sandbox = FALSE)
profile$person$first_name
} # }
```

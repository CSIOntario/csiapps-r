# Fetch profiles from the CSIAPPS registration API

Retrieves all profiles accessible to the authenticated user, with
optional filtering. Automatically paginates — all matching profiles are
returned in a single list regardless of how many pages the API uses.

## Usage

``` r
fetch_profiles(token = NULL, filters = list(), sandbox = is_sandbox_mode())
```

## Arguments

- token:

  Character. Authentication token. Defaults to the
  `CSIAPPS_ACCESS_TOKEN` environment variable.

- filters:

  Named list of query parameters for filtering. Common filters include
  `sport_org_id` (integer, filter by organisation) and `sport` (filter
  by sport). See the [CSIAPPS Swagger
  docs](https://apps.csiontario.ca/api/swagger/) for all available
  parameters.

- sandbox:

  Logical. When `TRUE` (the default in development), no network call is
  made and an empty list is returned immediately. Set to `FALSE` for
  production to fetch real profiles. Defaults to
  [`is_sandbox_mode()`](https://csiontario.github.io/csiapps/reference/is_sandbox_mode.md).

## Value

A list of profile objects. Each element contains a `person` sub-list
(`first_name`, `last_name`, `dob`, `email`, ...) and a
`current_nomination` sub-list (`role`, `organization`, ...). See the
[CSIAPPS Swagger docs](https://apps.csiontario.ca/api/swagger/) for the
full schema.

## See also

[`fetch_profile()`](https://csiontario.github.io/csiapps/reference/fetch_profile.md)
to retrieve a single profile by ID,
[`fetch_org_options()`](https://csiontario.github.io/csiapps/reference/fetch_org_options.md)
to list available organisations,
[`set_institute()`](https://csiontario.github.io/csiapps/reference/set_institute.md)
to configure the target institute.

## Examples

``` r
if (FALSE) { # \dontrun{
set_institute("csiontario")

# All profiles your token can see
profiles <- fetch_profiles(sandbox = FALSE)

# Profiles for a specific organisation
profiles <- fetch_profiles(filters = list(sport_org_id = 42L), sandbox = FALSE)

# Build a display data frame
profile_df <- do.call(rbind, lapply(profiles, function(p) {
  data.frame(
    id         = p$id,
    first_name = p$person$first_name %||% NA_character_,
    last_name  = p$person$last_name  %||% NA_character_,
    email      = p$person$email      %||% NA_character_
  )
}))
} # }
```

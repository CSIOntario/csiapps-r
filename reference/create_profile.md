# Create dummy athlete profiles in the sandbox

Generates `n` random athlete profiles and registers them under an
existing sandbox sport org, so sandbox
[`fetch_profiles()`](https://csiontario.github.io/csiapps/reference/fetch_profiles.md)
/
[`fetch_profile()`](https://csiontario.github.io/csiapps/reference/fetch_profile.md)
return prod-shaped data. The org must already exist (see
[`create_sport_org()`](https://csiontario.github.io/csiapps/reference/create_sport_org.md)).

## Usage

``` r
create_profile(n, sport_org_id, first_names = NULL, last_names = NULL)
```

## Arguments

- n:

  Integer. Number of profiles to create.

- sport_org_id:

  Integer. Id of the sport org (from
  [`create_sport_org()`](https://csiontario.github.io/csiapps/reference/create_sport_org.md))
  the athletes belong to. Stored as each profile's `sport$id` (the
  filter `fetch_profiles(filters = list(sport_org_id = ...))` uses), and
  its name becomes each profile's `sport$name`. The org must already
  exist.

- first_names, last_names:

  Character vectors of length `n` giving each athlete's first and last
  name. Provide both or neither. When both are `NULL` (default), `n`
  unique first/last pairs are drawn without replacement from the
  `babynames` dataset, so every athlete name is distinct.

## Value

The created profiles, invisibly. Appended to any already registered.

## See also

[`create_sport_org()`](https://csiontario.github.io/csiapps/reference/create_sport_org.md),
[csiapps-sandbox](https://csiontario.github.io/csiapps/reference/csiapps-sandbox.md)

## Examples

``` r
org <- create_sport_org("Rowing Canada")
#> csiapps sandbox: created sport org 173 ('Rowing Canada')
create_profile(2, org$id, first_names = c("Ada", "Blair"),
               last_names = c("Nkemelu", "Okafor"))
#> csiapps sandbox: created 2 athlete(s) under sport org 173 (2 total)
clear_sandbox()
#> csiapps sandbox: entire sandbox cleared
```

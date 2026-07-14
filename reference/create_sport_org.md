# Create a dummy sport organization in the sandbox

Registers a sport org so that sandbox reads
([`fetch_org_options()`](https://csiontario.github.io/csiapps/reference/fetch_org_options.md),
and `fetch_profiles(filters = list(sport_org_id = ...))`) behave like
production. The org's `name` becomes the `sport$name` of every athlete
created under it with
[`create_profile()`](https://csiontario.github.io/csiapps/reference/create_profile.md).

## Usage

``` r
create_sport_org(name, id = NULL)
```

## Arguments

- name:

  Character. Name of the sport organization (e.g. "Rowing Canada").
  Required.

- id:

  Integer. Optional org id. If `NULL` (default) an unused id in `1:999`
  is generated. If supplied, it must be a positive integer in `1:999`
  that does not collide with an existing sandbox org.

## Value

The created org (`list(id, name, annual_cycle_start)`), invisibly.

## See also

[`create_profile()`](https://csiontario.github.io/csiapps/reference/create_profile.md)
to add athletes,
[csiapps-sandbox](https://csiontario.github.io/csiapps/reference/csiapps-sandbox.md)
for an overview

## Examples

``` r
org <- create_sport_org("Rowing Canada")
#> csiapps sandbox: created sport org 452 ('Rowing Canada')
create_profile(5, org$id)
#> csiapps sandbox: created 5 athlete(s) under sport org 452 (5 total)
clear_sandbox()
#> csiapps sandbox: entire sandbox cleared
```

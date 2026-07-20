# Clear the local sandbox

Removes registered schemas, in-memory records, and on-disk payload
files. With no arguments the entire sandbox is reset; with a
`source_uuid` only that data source is cleared. Useful as test teardown
between unit tests.

## Usage

``` r
clear_sandbox(source_uuid = NULL)
```

## Arguments

- source_uuid:

  Character. Optional. If provided, clears only the schema, records, and
  payload folder for that specific source.

## Value

Invisibly, NULL

## See also

[csiapps-sandbox](https://csiontario.github.io/csiapps-r/reference/csiapps-sandbox.md)
for an overview of sandbox mode and its limitations

## Examples

``` r
clear_sandbox()
#> csiapps sandbox: entire sandbox cleared
```

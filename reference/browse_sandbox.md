# Open the sandbox payload directory in the system file explorer

Ingested payloads are written as pretty-printed JSON files, one folder
per data source, so developers can inspect the exact JSON that would
have been sent to the real API.

## Usage

``` r
browse_sandbox(source_uuid = NULL)
```

## Arguments

- source_uuid:

  Character. Optional. If provided, opens that specific source's payload
  folder instead of the sandbox root.

## Value

Invisibly, the path to the opened directory

## See also

[csiapps-sandbox](https://csiontario.github.io/csiapps-r/reference/csiapps-sandbox.md)
for an overview of sandbox mode and its limitations

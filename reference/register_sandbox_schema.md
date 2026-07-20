# Register a JSON schema in the local sandbox

Makes a schema available to sandbox requests under the given data source
uuid, emulating a data source that exists in the warehouse. The uuid
does not need to be a real production uuid – any identifying string
works.

## Usage

``` r
register_sandbox_schema(source_uuid, schema)
```

## Arguments

- source_uuid:

  Character. Identifier of the emulated data source.

- schema:

  The JSON Schema for the data source: an R list (as returned by
  `data_source$head_primary_definition$schema`), a JSON string, or a
  path to a JSON file.

## Value

The parsed schema, invisibly

## See also

[csiapps-sandbox](https://csiontario.github.io/csiapps-r/reference/csiapps-sandbox.md)
for an overview of sandbox mode and its limitations

## Examples

``` r
register_sandbox_schema("dummy-1234", '{
  "type": "object",
  "required": ["id"],
  "properties": {"id": {"type": "string"}}
}')
#> csiapps sandbox: schema registered for source 'dummy-1234'
clear_sandbox()
#> csiapps sandbox: entire sandbox cleared
```

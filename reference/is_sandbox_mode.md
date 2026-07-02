# Check whether sandbox mode is enabled globally

Determines the default value of the `sandbox` argument of
[`make_request()`](https://csiontario.github.io/csiapps/reference/make_request.md).
Sandbox mode is enabled when the `csiapps.sandbox` R option is `TRUE`,
or, if the option is unset, when the `CSIAPPS_ENV` environment variable
equals `"sandbox"`.

## Usage

``` r
is_sandbox_mode()
```

## Value

logical; `TRUE` if sandbox mode is enabled globally

## See also

[csiapps-sandbox](https://csiontario.github.io/csiapps/reference/csiapps-sandbox.md)
for an overview of sandbox mode

## Examples

``` r
is_sandbox_mode()
#> [1] FALSE

options(csiapps.sandbox = TRUE)
is_sandbox_mode()
#> [1] TRUE
options(csiapps.sandbox = NULL)
```

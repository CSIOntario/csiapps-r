# Check whether sandbox mode is enabled globally

Determines the default value of the `sandbox` argument of
[`make_request()`](https://csiontario.github.io/csiapps/reference/make_request.md).
**Sandbox mode is enabled by default**, so that requests never reach the
production warehouse unless it is explicitly turned off. It is disabled
when the `csiapps.sandbox` R option is set to `FALSE`, or, if that
option is unset, when the `CSIAPPS_ENV` environment variable equals
`"production"`. The R option, when set, always takes precedence over the
environment variable.

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
is_sandbox_mode() # TRUE by default
#> [1] TRUE

options(csiapps.sandbox = FALSE) # turn sandbox off (e.g. for deployment)
is_sandbox_mode()
#> [1] FALSE
options(csiapps.sandbox = NULL)
```

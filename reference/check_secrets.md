# Function to check that required environment variables for APPS authentication are set and valid

Function to check that required environment variables for APPS
authentication are set and valid

## Usage

``` r
check_secrets(verbose = FALSE, sandbox = is_sandbox_mode())
```

## Arguments

- verbose:

  logical; if TRUE, prints the current values of relevant environment
  variables (masking secrets) to the console

- sandbox:

  If TRUE, the OAuth secret checks are skipped (sandbox mode simulates
  the login and needs no client credentials); instead the presence of
  `CSIAPPS_ACCESS_TOKEN` is reported, since that determines whether real
  registration data is available. Never errors in sandbox mode. Defaults
  to
  [`is_sandbox_mode()`](https://csiontario.github.io/csiapps/reference/is_sandbox_mode.md).
  See
  [csiapps-sandbox](https://csiontario.github.io/csiapps/reference/csiapps-sandbox.md).

# Wrapper UI for Shiny apps

Provides a consistent navbar and footer, and handles authentication
redirects.

## Usage

``` r
ui_wrapper(..., sandbox = is_sandbox_mode())
```

## Arguments

- ...:

  Additional UI elements to include in the main content area

- sandbox:

  If TRUE, a "sandbox mode" banner is shown so it is obvious the app is
  not connected to the live warehouse. Defaults to
  [`is_sandbox_mode()`](https://csiontario.github.io/csiapps/reference/is_sandbox_mode.md).
  See
  [csiapps-sandbox](https://csiontario.github.io/csiapps/reference/csiapps-sandbox.md).

## Value

A Shiny UI object with a navbar, footer, and main content area

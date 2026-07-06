# Wrapper server function for Shiny apps

Handles OAuth2 PKCE authentication flow with CSIAPPS, managing user
tokens and info, and providing a consistent authentication status UI.

## Usage

``` r
server_wrapper(app_specific_logic, sandbox = is_sandbox_mode())
```

## Arguments

- app_specific_logic:

  Existing server logic of shiny web application

- sandbox:

  If TRUE, the real OAuth2 redirect is skipped and the session is seeded
  from the developer's existing `CSIAPPS_ACCESS_TOKEN`, so a wrapped app
  can be run locally without client credentials. If no token is set, the
  app shell renders with an unauthenticated notice. Defaults to
  [`is_sandbox_mode()`](https://csiontario.github.io/csiapps/reference/is_sandbox_mode.md),
  which is **TRUE by default**. Disable it for deployment with
  `options(csiapps.sandbox = FALSE)` (or `CSIAPPS_ENV=production`) to
  use the real login flow. See
  [csiapps-sandbox](https://csiontario.github.io/csiapps/reference/csiapps-sandbox.md)
  for details and limitations.

## Value

A Shiny server function that wraps the provided app-specific logic with
authentication handling and user info retrieval.

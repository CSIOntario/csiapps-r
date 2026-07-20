# Make an authenticated API request to CSIAPPS

Make an authenticated API request to CSIAPPS

## Usage

``` r
make_request(
  endpoint,
  method = "GET",
  body = NULL,
  query = list(),
  headers = list(),
  token = NULL,
  timeout = 20L,
  verbose = FALSE,
  paginate = FALSE,
  max_pages = 50,
  sandbox = is_sandbox_mode()
)
```

## Arguments

- endpoint:

  API endpoint path.

- method:

  HTTP method. Defaults to "GET"

- body:

  Optional request body for POST/PUT/PATCH requests; should be an R
  object that can be serialized to JSON

- query:

  Optional list of query parameters to include in the request URL

- headers:

  Optional list of additional HTTP headers to include in the request

- token:

  Authentication token. When not provided, it is resolved for the
  current Shiny session (the token stored by
  [`server_wrapper()`](https://csiontario.github.io/csiapps-r/reference/server_wrapper.md)),
  falling back to the `CSIAPPS_ACCESS_TOKEN` environment variable
  outside a session. Inside a Shiny session a not-yet-available token
  does not error: the request is cancelled quietly with
  [`shiny::req()`](https://rdrr.io/pkg/shiny/man/req.html), and the
  calling reactive or observer re-runs automatically once login
  completes (see
  [`token_ready()`](https://csiontario.github.io/csiapps-r/reference/token_ready.md)).
  Outside Shiny a missing token raises an error.

- timeout:

  Request timeout in seconds; defaults to 20

- verbose:

  If TRUE, prints request and response details to the console for
  debugging purposes

- paginate:

  If TRUE, will attempt to paginate through results using "next" links
  in the API response. Defaults to FALSE.

- max_pages:

  Maximum number of pages to fetch when paginate = TRUE; defaults to 50
  to prevent infinite loops

- sandbox:

  If TRUE, the request is routed to the local sandbox instead of the
  real REST API: no network call is made and no authentication is
  required. Only the **warehouse** endpoints are emulated; registration
  and auth endpoints (e.g. `api/registration/...`, `api/csiauth/me/`)
  are not, and raise a 501 in sandbox unless `sandbox = FALSE` (for
  registration reads, use
  [`fetch_org_options()`](https://csiontario.github.io/csiapps-r/reference/fetch_org_options.md)
  /
  [`fetch_profiles()`](https://csiontario.github.io/csiapps-r/reference/fetch_profiles.md)
  instead). Defaults to
  [`is_sandbox_mode()`](https://csiontario.github.io/csiapps-r/reference/is_sandbox_mode.md),
  which is **TRUE by default**. Disable sandbox mode globally with
  `options(csiapps.sandbox = FALSE)` (or `CSIAPPS_ENV=production`) to
  route requests to the production warehouse. See
  [csiapps-sandbox](https://csiontario.github.io/csiapps-r/reference/csiapps-sandbox.md)
  for supported endpoints and limitations. In sandbox mode the HTTP-only
  arguments (`headers`, `token`, `timeout`, `max_pages`) are ignored,
  since no network request is made.

## Value

List of parsed API responses

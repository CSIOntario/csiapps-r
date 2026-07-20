# Is a CSIAPPS access token available yet?

Returns `TRUE` once an access token is available for the current
context: inside a Shiny app wrapped by
[`server_wrapper()`](https://csiontario.github.io/csiapps-r/reference/server_wrapper.md),
the per-session token stored at login; outside Shiny, the
`CSIAPPS_ACCESS_TOKEN` environment variable.

## Usage

``` r
token_ready()
```

## Value

logical; `TRUE` if an access token is available.

## Details

The check is reactive-friendly: called from a reactive expression or
observer it takes a dependency on the session's token, so a guard like
`req(token_ready())` re-fires automatically when login completes,
instead of silently sticking in the cancelled state. Note that
[`make_request()`](https://csiontario.github.io/csiapps-r/reference/make_request.md)
and the `fetch_*()` helpers already gate themselves this way, so an
explicit guard is only needed for work that should wait for login
without making an API call (e.g. processing an uploaded file).

## See also

[`server_wrapper()`](https://csiontario.github.io/csiapps-r/reference/server_wrapper.md),
[`make_request()`](https://csiontario.github.io/csiapps-r/reference/make_request.md)

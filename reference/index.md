# Package index

## Functions

### Shiny

Functions for developing Shiny web applications.

- [`ui_wrapper()`](https://csiontario.github.io/csiapps/reference/ui_wrapper.md)
  : Wrapper UI for Shiny apps
- [`server_wrapper()`](https://csiontario.github.io/csiapps/reference/server_wrapper.md)
  : Wrapper server function for Shiny apps
- [`global_wrapper()`](https://csiontario.github.io/csiapps/reference/global_wrapper.md)
  : Wrap Global code for Shiny apps
- [`check_secrets()`](https://csiontario.github.io/csiapps/reference/check_secrets.md)
  : Function to check that required environment variables for APPS
  authentication are set and valid
- [`set_institute()`](https://csiontario.github.io/csiapps/reference/set_institute.md)
  : Set the target institute for API calls

### REST API

Functions for interfacing with the CSIAPPS REST API.

- [`make_request()`](https://csiontario.github.io/csiapps/reference/make_request.md)
  : Make an authenticated API request to CSIAPPS
- [`fetch_org_options()`](https://csiontario.github.io/csiapps/reference/fetch_org_options.md)
  : Fetch organisation options from the CSIAPPS registration API
- [`fetch_profiles()`](https://csiontario.github.io/csiapps/reference/fetch_profiles.md)
  : Fetch profiles from the CSIAPPS registration API
- [`fetch_profile()`](https://csiontario.github.io/csiapps/reference/fetch_profile.md)
  : Fetch a single profile from the CSIAPPS registration API

### Sandbox

Functions for simulating warehouse workflows in a local sandbox.

- [`csiapps-sandbox`](https://csiontario.github.io/csiapps/reference/csiapps-sandbox.md)
  : Sandbox mode for local development
- [`is_sandbox_mode()`](https://csiontario.github.io/csiapps/reference/is_sandbox_mode.md)
  : Check whether sandbox mode is enabled globally
- [`register_sandbox_schema()`](https://csiontario.github.io/csiapps/reference/register_sandbox_schema.md)
  : Register a JSON schema in the local sandbox
- [`clear_sandbox()`](https://csiontario.github.io/csiapps/reference/clear_sandbox.md)
  : Clear the local sandbox
- [`browse_sandbox()`](https://csiontario.github.io/csiapps/reference/browse_sandbox.md)
  : Open the sandbox payload directory in the system file explorer

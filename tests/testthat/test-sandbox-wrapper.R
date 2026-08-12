# Sandbox simulation of the Shiny app wrappers:
# check_secrets(), ui_wrapper(), and server_wrapper()'s simulated login.

# ---- check_secrets -----------------------------------------------------

test_that("check_secrets never errors in sandbox mode, even with no secrets", {
  withr::local_envvar(CSIAPPS_ACCESS_TOKEN = NA, CSIAPPS_REDIRECT_URI = NA)
  expect_true(suppressMessages(check_secrets(sandbox = TRUE)))
  expect_invisible(suppressMessages(check_secrets(sandbox = TRUE)))
})

test_that("check_secrets reports whether an access token is available", {
  withr::local_envvar(CSIAPPS_ACCESS_TOKEN = NA)
  expect_message(check_secrets(sandbox = TRUE), "no CSIAPPS_ACCESS_TOKEN")

  withr::local_envvar(CSIAPPS_ACCESS_TOKEN = "dev-token")
  expect_message(check_secrets(sandbox = TRUE), "real registration reads enabled")
})

test_that("check_secrets still validates OAuth secrets when sandbox is off", {
  withr::local_envvar(CSIAPPS_REDIRECT_URI = NA)
  expect_error(check_secrets(sandbox = FALSE), "Invalid or missing URL")
})

# ---- ui_wrapper --------------------------------------------------------

test_that("ui_wrapper shows a sandbox banner only in sandbox mode", {
  expect_match(as.character(ui_wrapper(sandbox = TRUE)), "Sandbox mode")
  expect_false(grepl("Sandbox mode", as.character(ui_wrapper(sandbox = FALSE))))
})

test_that("ui_wrapper injects locked, theme-independent chrome styles", {
  # `tags$head` content is hoisted by htmltools; render it the way Shiny does so
  # the injected <style> materialises (as.character() on the tagList drops head).
  rendered <- htmltools::renderTags(ui_wrapper(shiny::div("app content")))
  head <- paste(as.character(rendered$head), collapse = "")

  # Stable hook the injected CSS targets
  expect_match(rendered$html, 'id="csi-navbar"')
  # Scoped style block that pins the brand appearance and stacking
  expect_match(head, "#csi-navbar")
  expect_match(head, "position: sticky", fixed = TRUE)
  # Neutral-frame theme: white bar with a CSI-red brand accent line
  expect_match(head, "background-color: #ffffff !important", fixed = TRUE)
  expect_match(head, "border-bottom: 3px solid #d81f26 !important", fixed = TRUE)
  # Bootstrap 3's fixed 50px brand box must not let the 48px logo overflow
  # through the navbar's bottom border.
  expect_match(head, "height: auto !important", fixed = TRUE)
  expect_match(head, "padding-top: 8px !important", fixed = TRUE)
  expect_match(head, "padding-bottom: 8px !important", fixed = TRUE)
})

test_that("Atlantic institute routes and renders correctly", {
  original <- package_state$INSTITUTE
  withr::defer(package_state$INSTITUTE <- original)

  set_institute("csiatlantic")

  expect_identical(SITE_URL(), "https://apps.csiatlantic.ca")
  expect_identical(CSIAPPS_AUTH_URL(), "https://apps.csiatlantic.ca/o/authorize/")
  expect_identical(CSIAPPS_TOKEN_URL(), "https://apps.csiatlantic.ca/o/token/")
  expect_identical(CSIAPPS_USERINFO_URL(), "https://apps.csiatlantic.ca/api/csiauth/me")

  html <- htmltools::renderTags(ui_wrapper(sandbox = TRUE))$html
  expect_match(
    html,
    "https://www.csiatlantic.ca/sites/default/files/logo-institute.png",
    fixed = TRUE
  )
  expect_match(html, "CSI Atlantic", fixed = TRUE)

  expect_error(set_institute("csiquebec"))
})

# ---- server_wrapper: simulated login -----------------------------------

test_that("server_wrapper returns a function in both modes", {
  logic <- function(input, output, session) {}
  expect_true(is.function(server_wrapper(logic, sandbox = TRUE)))
  expect_true(is.function(server_wrapper(logic, sandbox = FALSE)))
})

test_that("sandbox shows an unauthenticated notice without a token", {
  withr::local_envvar(CSIAPPS_ACCESS_TOKEN = NA)
  server <- server_wrapper(function(input, output, session) {}, sandbox = TRUE)

  suppressMessages(shiny::testServer(server, {
    session$flushReact()
    # Sentinel token with no access_token -> no network call was attempted
    expect_null(user_token()$access_token)
    expect_true(isTRUE(user_token()$unauthenticated))
    expect_null(userinfo())
    # Auth status shows an unauthenticated notice, not a redirect or dummy name
    expect_match(output$auth_status$html, "CSIAPPS_ACCESS_TOKEN")
    expect_false(grepl("Redirecting", output$auth_status$html))
  }))
})

test_that("sandbox seeds the session from an existing access token", {
  withr::local_envvar(CSIAPPS_ACCESS_TOKEN = "dev-token-abc")
  # Keep the shared consumer offline: skip /me and stub the org lookup
  testthat::local_mocked_bindings(
    CSIAPPS_USERINFO_URL = function() "",
    fetch_org_options    = function(token = NULL, sandbox = is_sandbox_mode()) list()
  )
  server <- server_wrapper(function(input, output, session) {}, sandbox = TRUE)

  suppressMessages(shiny::testServer(server, {
    session$flushReact()
    # The existing token is adopted as the "granted" token...
    expect_identical(user_token()$access_token, "dev-token-abc")
    # ...and stored on the session (per-session, so concurrent users never
    # share a token) for make_request()/helpers to read
    expect_identical(shiny::isolate(session$userData$csiapps_token_rv()), "dev-token-abc")
  }))
})

# ---- registration helpers: sandbox mode ------------------------------------

test_that("fetch_org_options returns empty list in sandbox mode", {
  expect_message(
    result <- fetch_org_options(sandbox = TRUE),
    "csiapps sandbox"
  )
  expect_identical(result, list())
})

test_that("fetch_profiles returns empty list in sandbox mode", {
  expect_message(
    result <- fetch_profiles(sandbox = TRUE),
    "csiapps sandbox"
  )
  expect_identical(result, list())
})

test_that("fetch_profile returns NULL in sandbox mode", {
  expect_message(
    result <- fetch_profile(profile_id = 1L, sandbox = TRUE),
    "csiapps sandbox"
  )
  expect_null(result)
})

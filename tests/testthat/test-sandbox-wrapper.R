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
  expect_match(as.character(ui_wrapper(sandbox = TRUE)), "SANDBOX MODE")
  expect_false(grepl("SANDBOX MODE", as.character(ui_wrapper(sandbox = FALSE))))
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
    fetch_org_options    = function(token = NULL) list()
  )
  server <- server_wrapper(function(input, output, session) {}, sandbox = TRUE)

  suppressMessages(shiny::testServer(server, {
    session$flushReact()
    # The existing token is adopted as the "granted" token...
    expect_identical(user_token()$access_token, "dev-token-abc")
    # ...and published to the environment for make_request()/helpers
    expect_identical(Sys.getenv("CSIAPPS_ACCESS_TOKEN"), "dev-token-abc")
  }))
})

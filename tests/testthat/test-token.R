# Per-session token resolution and reactive auth gating.

test_that("token_ready() falls back to the env var outside Shiny", {
  withr::local_envvar(CSIAPPS_ACCESS_TOKEN = NA)
  expect_false(token_ready())

  withr::local_envvar(CSIAPPS_ACCESS_TOKEN = "cli-token")
  expect_true(token_ready())
})

test_that("make_request errors loudly outside Shiny when no token is set", {
  withr::local_envvar(CSIAPPS_ACCESS_TOKEN = NA)
  expect_error(
    make_request("api/registration/organization", sandbox = FALSE),
    "not authenticated"
  )
})

test_that("req(token_ready()) blocks before login and re-fires after", {
  withr::local_envvar(CSIAPPS_ACCESS_TOKEN = NA)

  server <- function(input, output, session) {
    runs <- shiny::reactiveVal(0L)
    shiny::observe({
      shiny::req(token_ready())
      # isolate: the observer must not depend on the counter it increments
      runs(shiny::isolate(runs()) + 1L)
    })
  }

  shiny::testServer(server, {
    session$flushReact()
    expect_identical(runs(), 0L)   # gated: not authenticated yet

    # Simulate server_wrapper() storing the token at login
    csiapps:::.set_session_token(session, "tok-123")
    session$flushReact()
    expect_identical(runs(), 1L)   # guard re-fired on its own

    # Logout clears the token; already-run observers are not re-triggered
    # (the rv changing invalidates them, but the guard cancels quietly)
    csiapps:::.set_session_token(session, NULL)
    session$flushReact()
    expect_identical(runs(), 1L)
    expect_false(shiny::isolate(token_ready()))
  })
})

test_that("make_request gates quietly inside a session before login", {
  withr::local_envvar(CSIAPPS_ACCESS_TOKEN = NA)

  server <- function(input, output, session) {
    reached_after <- shiny::reactiveVal(FALSE)
    shiny::observe({
      make_request("api/warehouse/data-records", sandbox = FALSE)
      reached_after(TRUE)
    })
  }

  shiny::testServer(server, {
    # Pre-login: the request is cancelled via req(), not an error
    expect_no_error(session$flushReact())
    expect_false(reached_after())
  })
})

test_that("the env placeholder satisfies nzchar() but is never a credential", {
  withr::local_envvar(CSIAPPS_ACCESS_TOKEN = NA)
  .seed_env_placeholder()
  withr::defer(Sys.unsetenv("CSIAPPS_ACCESS_TOKEN"))

  # Legacy guards like req(nzchar(Sys.getenv(...))) pass...
  expect_true(nzchar(Sys.getenv("CSIAPPS_ACCESS_TOKEN")))
  # ...but the placeholder is not treated as a token anywhere:
  expect_false(token_ready())
  expect_error(
    make_request("api/registration/organization", sandbox = FALSE),
    "not authenticated"
  )
  # even when a legacy app passes the env var through explicitly
  expect_error(
    make_request("api/registration/organization",
                 token = Sys.getenv("CSIAPPS_ACCESS_TOKEN"), sandbox = FALSE),
    "not authenticated"
  )
})

test_that("seeding never overwrites a real env token", {
  withr::local_envvar(CSIAPPS_ACCESS_TOKEN = "real-cli-token")
  .seed_env_placeholder()
  expect_identical(Sys.getenv("CSIAPPS_ACCESS_TOKEN"), "real-cli-token")
})

test_that("legacy env-var guard + make_request works unchanged in a session", {
  withr::local_envvar(CSIAPPS_ACCESS_TOKEN = NA)
  .seed_env_placeholder()
  withr::defer(Sys.unsetenv("CSIAPPS_ACCESS_TOKEN"))

  # The untouched pattern from pre-0.1.1 apps: an env-var guard ahead of an
  # API call inside a reactive.
  server <- function(input, output, session) {
    reached_api <- shiny::reactiveVal(FALSE)
    shiny::observe({
      shiny::req(nzchar(Sys.getenv("CSIAPPS_ACCESS_TOKEN")))  # legacy guard
      make_request("api/registration/organization", sandbox = FALSE)
      reached_api(TRUE)
    })
  }

  shiny::testServer(server, {
    # Pre-login: guard passes (placeholder), make_request gates quietly
    expect_no_error(session$flushReact())
    expect_false(reached_api())
  })
})

test_that("fetch helpers gate quietly inside a session before login", {
  withr::local_envvar(CSIAPPS_ACCESS_TOKEN = NA)

  server <- function(input, output, session) {
    reached_after <- shiny::reactiveVal(FALSE)
    shiny::observe({
      fetch_org_options(sandbox = FALSE)
      reached_after(TRUE)
    })
  }

  shiny::testServer(server, {
    expect_no_error(session$flushReact())
    expect_false(reached_after())
  })
})

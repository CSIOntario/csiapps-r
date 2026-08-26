test_that("quarto_setup requires a Shiny session", {
  expect_error(quarto_setup(), "active Shiny session")
})

test_that("quarto_setup accepts an authenticated sandbox session", {
  withr::local_envvar(CSIAPPS_ACCESS_TOKEN = "quarto-dev-token")
  testthat::local_mocked_bindings(CSIAPPS_USERINFO_URL = function() "")
  protected_body <- withr::local_tempfile()
  writeLines("<main>Protected report</main>", protected_body, useBytes = TRUE)

  server <- function(input, output, session) {
    quarto_setup(
      protected_body = protected_body,
      config_file = "does-not-exist.json",
      sandbox = TRUE
    )
  }

  suppressMessages(shiny::testServer(server, {
    session$flushReact()
    expect_true(shiny::isolate(token_ready()))
    expect_true(session$userData$csiapps_quarto_initialized)
    session$flushReact()
    expect_true(session$userData$csiapps_quarto_initialized)
  }))
})

test_that("quarto_setup reveals sandbox reports without contacting CSI", {
  withr::local_envvar(CSIAPPS_ACCESS_TOKEN = NA)
  protected_body <- withr::local_tempfile()
  writeLines("<main>Local sandbox report</main>", protected_body, useBytes = TRUE)

  server <- function(input, output, session) {
    quarto_setup(
      protected_body = protected_body,
      config_file = "does-not-exist.json",
      sandbox = TRUE
    )
  }

  suppressMessages(shiny::testServer(server, {
    session$flushReact()
    expect_false(shiny::isolate(token_ready()))
    expect_true(session$userData$csiapps_quarto_initialized)

    session$setInputs(logout = 1)
    session$flushReact()
    expect_false(shiny::isolate(token_ready()))
    expect_match(output$auth_status$html, "Signed out")
  }))
})

test_that("shared redirects use the existing browser message channel", {
  messages <- list()
  session <- list(
    clientData = list(url_pathname = "/report/"),
    sendCustomMessage = function(type, message) {
      messages[[type]] <<- message
    }
  )

  expect_identical(.redirect_current(session), "/report/")
  expect_identical(messages$csip_redirect, "/report/")
})

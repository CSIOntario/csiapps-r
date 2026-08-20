test_that("Quarto datasets serialize as a complete row registry", {
  data <- data.frame(
    id = c(1L, 2L),
    name = c("Ada", "Zoë"),
    score = c(NA_real_, 9.5),
    date = as.Date(c("2026-08-19", "2026-08-20"))
  )

  parsed <- jsonlite::fromJSON(.quarto_datasets_json(list(athletes = data)))

  expect_identical(nrow(parsed$athletes), 2L)
  expect_identical(parsed$athletes$name, c("Ada", "Zoë"))
  expect_true(is.na(parsed$athletes$score[[1]]))
  expect_identical(parsed$athletes$date, c("2026-08-19", "2026-08-20"))
  expect_identical(.quarto_datasets_json(list()), "{}")
})

test_that("Quarto dataset validation rejects ambiguous registries", {
  expect_error(.quarto_datasets_json(data.frame(id = 1)), "named list")
  expect_error(.quarto_datasets_json(list(unnamed = c(1, 2))), "data frame or a list")

  duplicated <- list(data.frame(id = 1), data.frame(id = 2))
  names(duplicated) <- c("athletes", "athletes")
  expect_error(.quarto_datasets_json(duplicated), "unique")
})

test_that("quarto_setup requires a Shiny session and provider", {
  expect_error(quarto_setup(snapshot_data = list()), "zero-argument function")
  expect_error(quarto_setup(), "active Shiny session")
})

test_that("quarto_setup loads data only after the session token is ready", {
  withr::local_envvar(CSIAPPS_ACCESS_TOKEN = "quarto-dev-token")
  testthat::local_mocked_bindings(CSIAPPS_USERINFO_URL = function() "")
  protected_body <- withr::local_tempfile()
  writeLines("<main>Protected report</main>", protected_body, useBytes = TRUE)

  server <- function(input, output, session) {
    quarto_setup(
      snapshot_data = function() list(athletes = data.frame(id = 1:2)),
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

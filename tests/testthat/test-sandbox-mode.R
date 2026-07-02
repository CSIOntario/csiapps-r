# is_sandbox_mode() and make_request() routing

test_that("is_sandbox_mode is TRUE by default", {
  withr::local_options(csiapps.sandbox = NULL)
  withr::local_envvar(CSIAPPS_ENV = NA)
  expect_true(is_sandbox_mode())
})

test_that("CSIAPPS_ENV disables sandbox only for the literal 'production'", {
  withr::local_options(csiapps.sandbox = NULL)

  withr::local_envvar(CSIAPPS_ENV = "production")
  expect_false(is_sandbox_mode())

  # any other value leaves sandbox on (fail-safe: never route to prod by typo)
  withr::local_envvar(CSIAPPS_ENV = "staging")
  expect_true(is_sandbox_mode())
})

test_that("is_sandbox_mode respects the csiapps.sandbox option", {
  withr::local_envvar(CSIAPPS_ENV = NA)

  withr::local_options(csiapps.sandbox = TRUE)
  expect_true(is_sandbox_mode())

  withr::local_options(csiapps.sandbox = FALSE)
  expect_false(is_sandbox_mode())
})

test_that("is_sandbox_mode respects the CSIAPPS_ENV environment variable", {
  withr::local_options(csiapps.sandbox = NULL)

  withr::local_envvar(CSIAPPS_ENV = "sandbox")
  expect_true(is_sandbox_mode())

  withr::local_envvar(CSIAPPS_ENV = "production")
  expect_false(is_sandbox_mode())
})

test_that("the option takes precedence over the environment variable", {
  withr::local_envvar(CSIAPPS_ENV = "sandbox")
  withr::local_options(csiapps.sandbox = FALSE)
  expect_false(is_sandbox_mode())
})

test_that("non-logical option values are treated as FALSE", {
  withr::local_envvar(CSIAPPS_ENV = NA)
  withr::local_options(csiapps.sandbox = "yes")
  expect_false(is_sandbox_mode())
})

test_that("make_request keeps its full production signature plus sandbox", {
  expect_named(formals(make_request),
    c("endpoint", "method", "body", "query", "headers", "token",
      "timeout", "verbose", "paginate", "max_pages", "sandbox"))
})

test_that("production path still requires a token when sandbox is off", {
  # sandbox is on by default, so disable it explicitly to reach the prod path
  withr::local_options(csiapps.sandbox = FALSE)
  withr::local_envvar(CSIAPPS_ENV = NA, CSIAPPS_ACCESS_TOKEN = NA)
  expect_error(make_request("api/csiauth/me/"), "no CSIAPPS_ACCESS_TOKEN set")
})

test_that("with nothing configured, requests route to the sandbox by default", {
  local_clean_sandbox()
  withr::local_options(csiapps.sandbox = NULL)
  withr::local_envvar(CSIAPPS_ENV = NA, CSIAPPS_ACCESS_TOKEN = NA)

  suppressMessages(register_sandbox_schema("default-route", test_schema()))
  res <- suppressMessages(make_request("api/warehouse/data-sources/default-route"))
  expect_identical(res$head_primary_definition$schema$title, "A registration form")
})

test_that("sandbox = FALSE per-call override wins over a global sandbox option", {
  withr::local_options(csiapps.sandbox = TRUE)
  withr::local_envvar(CSIAPPS_ACCESS_TOKEN = NA)
  expect_error(
    make_request("api/csiauth/me/", sandbox = FALSE),
    "no CSIAPPS_ACCESS_TOKEN set"
  )
})

test_that("global sandbox option routes requests locally without a token", {
  local_clean_sandbox()
  withr::local_options(csiapps.sandbox = TRUE)
  withr::local_envvar(CSIAPPS_ACCESS_TOKEN = NA)

  suppressMessages(register_sandbox_schema("route-test", test_schema()))
  res <- suppressMessages(make_request("api/warehouse/data-sources/route-test"))
  expect_identical(res$head_primary_definition$schema$title, "A registration form")
})

test_that("every sandbox request announces that no real API call is made", {
  local_clean_sandbox()
  suppressMessages(register_sandbox_schema("msg-test", test_schema()))
  expect_message(
    make_request("api/warehouse/data-sources/msg-test", sandbox = TRUE),
    "no real API call made"
  )
})

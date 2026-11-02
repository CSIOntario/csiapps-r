compat_response <- function(body = list(), status = 200L) httr2::response(
  status_code = status, headers = list(`content-type` = "application/json"),
  body = charToRaw(jsonlite::toJSON(body, auto_unbox = TRUE, null = "null")))

test_that("a browser session never falls back to a process access token", {
  withr::local_envvar(CSIAPPS_ACCESS_TOKEN = "console-only-token")
  a <- shiny::MockShinySession$new(); b <- shiny::MockShinySession$new()
  withr::defer({ a$close(); b$close() })
  expect_false(shiny::withReactiveDomain(a, token_ready()))
  .set_session_token(a, "session-a")
  .set_session_token(b, "session-b")
  expect_identical(shiny::withReactiveDomain(a, .current_token()), "session-a")
  expect_identical(shiny::withReactiveDomain(b, .current_token()), "session-b")
  .set_session_token(a, NULL)
  expect_false(shiny::withReactiveDomain(a, token_ready()))
  expect_identical(shiny::withReactiveDomain(b, .current_token()), "session-b")
  expect_true(token_ready()) # console behavior remains available outside a session
})

test_that("repeated subjects and count-only pagination preserve server caps", {
  urls <- character()
  httr2::local_mocked_responses(function(req) {
    urls <<- c(urls, req$url)
    offset <- (length(urls) - 1L) * 2L
    compat_response(list(count = 4L, results = lapply(offset + 1:2, function(i) list(id = i))))
  })
  pages <- make_request("api/warehouse/v2/data-records/", token = "fake", sandbox = FALSE,
                        query = list(subject = c(1L, 2L), limit = 500L), query_multi = "explode", paginate = TRUE)
  expect_length(pages, 2)
  expect_equal(sum(vapply(pages, function(p) length(p$results), integer(1))), 4)
  expect_match(urls[1], "subject=1&subject=2", fixed = TRUE)
  expect_match(urls[2], "offset=2", fixed = TRUE)
  expect_match(urls[2], "subject=1&subject=2", fixed = TRUE)
})

test_that("next links still work and page caps cannot silently truncate records", {
  urls <- character()
  httr2::local_mocked_responses(function(req) {
    urls <<- c(urls, req$url)
    compat_response(list(count = 2L, results = list(list(id = length(urls))),
                         `next` = if (length(urls) == 1L) "https://apps.csipacific.ca/api/records/?offset=1" else NULL))
  })
  expect_length(make_request("api/records/", token = "fake", sandbox = FALSE, paginate = TRUE), 2)
  urls <- character()
  expect_error(make_request("api/records/", token = "fake", sandbox = FALSE, paginate = TRUE, max_pages = 1), "max_pages")
})

test_that("writes can explicitly disable retries and empty success bodies parse cleanly", {
  calls <- 0L
  httr2::local_mocked_responses(function(req) {
    calls <<- calls + 1L
    compat_response(list(detail = "Temporary unavailable"), 503L)
  })
  expect_error(make_request("api/warehouse/v2/ingestion/primary/", method = "POST", body = list(records = list()),
                            token = "fake", sandbox = FALSE, retry_max_tries = 1L), class = "httr2_http_503")
  expect_identical(calls, 1L)
  httr2::local_mocked_responses(function(req) httr2::response(status_code = 204L, body = raw()))
  expect_identical(make_request("api/empty/", token = "fake", sandbox = FALSE), list())
})

test_that("public PKCE clients send client_id without Basic credentials", {
  withr::local_envvar(CSIAPPS_CLIENT_ID = "public-client", CSIAPPS_CLIENT_SECRET = NA,
                     CSIAPPS_REDIRECT_URI = "http://127.0.0.1:6059/")
  seen <- NULL
  httr2::local_mocked_responses(function(req) { seen <<- req; compat_response(list(access_token = "fake")) })
  expect_identical(exchange_code_for_token("fake-code", "fake-verifier")$access_token, "fake")
  expect_identical(as.character(seen$body$data$client_id), "public-client")
  expect_null(seen$headers$Authorization)
  expect_identical(as.character(seen$body$data$code_verifier), "fake-verifier")
})

test_that("401 responses clear only the rejected session token", {
  withr::local_envvar(CSIAPPS_ACCESS_TOKEN = "console-only")
  a <- shiny::MockShinySession$new(); b <- shiny::MockShinySession$new()
  withr::defer({a$close(); b$close()})
  .set_session_token(a, "expired"); .set_session_token(b, "valid")
  httr2::local_mocked_responses(function(req) compat_response(list(detail = "Expired"), 401L))
  expect_error(shiny::withReactiveDomain(a, make_request("api/records/", sandbox = FALSE)), class = "httr2_http_401")
  expect_false(shiny::withReactiveDomain(a, token_ready()))
  expect_true(shiny::withReactiveDomain(b, token_ready()))
})

test_that("the real wrapper authenticates, clears callback parameters and stays signed out", {
  withr::local_envvar(CSIAPPS_CLIENT_ID = "fake-client", CSIAPPS_CLIENT_SECRET = NA,
                     CSIAPPS_REDIRECT_URI = "http://127.0.0.1:6059/", CSIAPPS_ACCESS_TOKEN = NA)
  local_mocked_bindings(exchange_code_for_token = function(...) list(access_token = "wrapper-token"))
  httr2::local_mocked_responses(function(req) compat_response(list(first_name = "Demo", last_name = "Practitioner")))
  shiny::testServer(server_wrapper(function(input, output, session) {}, sandbox = FALSE, pause_on_logout = TRUE), {
    session$clientData <- list(url_search = "?code=fake", url_pathname = "/")
    expect_no_error(session$flushReact())
    expect_true(token_ready())
    expect_match(paste(unlist(output$auth_status), collapse = " "), "Demo Practitioner")
    session$setInputs(logout = 1)
    expect_false(token_ready())
    expect_match(paste(unlist(output$auth_status), collapse = " "), "Signed out")
  })
})

test_that("token exchange failures remain reviewable instead of crashing the session", {
  withr::local_envvar(CSIAPPS_CLIENT_ID = "fake-client", CSIAPPS_CLIENT_SECRET = NA,
                     CSIAPPS_REDIRECT_URI = "http://127.0.0.1:6059/", CSIAPPS_ACCESS_TOKEN = NA)
  local_mocked_bindings(exchange_code_for_token = function(...) stop("Fictional token endpoint failure"))
  shiny::testServer(server_wrapper(function(input, output, session) {}, sandbox = FALSE), {
    session$clientData <- list(url_search = "?code=fake", url_pathname = "/")
    expect_message(session$flushReact(), "token exchange failed")
    expect_false(token_ready())
    expect_match(paste(unlist(output$auth_status), collapse = " "), "Authentication error")
  })
})

test_that("profile helpers share session invalidation on rejected credentials", {
  session <- shiny::MockShinySession$new(); withr::defer(session$close())
  .set_session_token(session, "expired")
  httr2::local_mocked_responses(function(req) compat_response(list(detail = "Expired"), 401L))
  expect_error(shiny::withReactiveDomain(session, fetch_profiles(sandbox = FALSE)), class = "httr2_http_401")
  expect_false(shiny::withReactiveDomain(session, token_ready()))
})

test_that("null next links still respect the total count and incomplete pagination fails loudly", {
  calls <- 0L
  httr2::local_mocked_responses(function(req) {
    calls <<- calls + 1L
    compat_response(list(count = 2L, results = list(list(id = calls)), `next` = NULL))
  })
  expect_length(make_request("api/records/", token = "fake", sandbox = FALSE, paginate = TRUE), 2)
  httr2::local_mocked_responses(function(req) compat_response(list(count = 2L, results = list(), `next` = NULL)))
  expect_error(make_request("api/records/", token = "fake", sandbox = FALSE, paginate = TRUE), "before all records")
})

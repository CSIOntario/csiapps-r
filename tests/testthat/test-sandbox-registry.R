# Dummy sport-org + athlete registry in sandbox mode:
# create_sport_org(), create_profile(), and the fetch_* helpers reading them.

# distinct first/last name vectors so create_profile() needs no babynames
fn <- function(n) paste0("First", seq_len(n))
ln <- function(n) paste0("Last", seq_len(n))

test_that("create_sport_org requires a name", {
  local_clean_sandbox()
  expect_error(suppressMessages(create_sport_org()))
  expect_error(suppressMessages(create_sport_org("")))
})

test_that("create_sport_org generates an unused 3-digit id when none is given", {
  local_clean_sandbox()
  org <- suppressMessages(create_sport_org("Rowing Canada"))
  expect_true(org$id >= 100 && org$id <= 999)
  expect_identical(org$name, "Rowing Canada")
})

test_that("create_sport_org honours a supplied id and rejects collisions", {
  local_clean_sandbox()
  suppressMessages(create_sport_org("Swim BC", id = 321))
  expect_error(suppressMessages(create_sport_org("Swim BC", id = 321)), "already exists")
})

test_that("create_profile requires an existing sport org", {
  local_clean_sandbox()
  expect_error(
    suppressMessages(create_profile(2, sport_org_id = 999,
                                    first_names = fn(2), last_names = ln(2))),
    "does not exist")
})

test_that("fetch_org_options returns seeded orgs as label/value pairs", {
  local_clean_sandbox()
  suppressMessages(create_sport_org("Cycling Canada", id = 100))
  opts <- suppressMessages(fetch_org_options(sandbox = TRUE))
  expect_length(opts, 1)
  expect_identical(opts[[1]]$value, 100L)
  expect_identical(opts[[1]]$label, "Cycling Canada")
})

test_that("fetch_profiles returns prod-shaped athletes filtered by sport_org_id", {
  local_clean_sandbox()
  suppressMessages(create_sport_org("Rowing Canada", id = 100))
  suppressMessages(create_sport_org("Swim BC", id = 200))
  suppressMessages(create_profile(3, sport_org_id = 100, first_names = fn(3), last_names = ln(3)))
  suppressMessages(create_profile(2, sport_org_id = 200, first_names = fn(2), last_names = ln(2)))

  all_p <- suppressMessages(fetch_profiles(sandbox = TRUE))
  expect_length(all_p, 5)

  only_100 <- suppressMessages(fetch_profiles(filters = list(sport_org_id = 100), sandbox = TRUE))
  expect_length(only_100, 3)
  # Shape parity with prod: identity + link fields are populated (not NULL)
  p <- only_100[[1]]
  expect_true(nzchar(p$person$first_name))
  expect_true(nzchar(p$person$last_name))
  expect_identical(p$sport$id, 100L)
})

test_that("fetch_profile returns one athlete by id, NULL when unknown", {
  local_clean_sandbox()
  suppressMessages(create_sport_org("Rowing Canada", id = 100))
  suppressMessages(create_profile(2, sport_org_id = 100, first_names = fn(2), last_names = ln(2)))

  p <- suppressMessages(fetch_profile(profile_id = 1, sandbox = TRUE))
  expect_identical(p$id, 1L)
  expect_null(suppressMessages(fetch_profile(profile_id = 999, sandbox = TRUE)))
})

test_that("ingested records link to a registered athlete via subject_field", {
  local_clean_sandbox()
  suppressMessages(create_sport_org("Rowing Canada", id = 100))
  suppressMessages(create_profile(1, sport_org_id = 100, first_names = fn(1), last_names = ln(1)))  # athlete id 1

  schema <- list(type = "object", required = list("athlete_id"),
                 properties = list(athlete_id = list(type = "integer")))
  suppressMessages(register_sandbox_schema("src-1", schema))
  suppressMessages(make_request(
    endpoint = "api/warehouse/ingestion/primary/", method = "POST",
    body = list(source = "src-1",
                records = list(list(athlete_id = 1L), list(athlete_id = 999L)),
                subject_field = "athlete_id"),
    sandbox = TRUE))

  page <- suppressMessages(make_request(
    endpoint = "api/warehouse/data-records", method = "GET",
    query = list(source_uuid = "src-1"), sandbox = TRUE))

  # Record 1 links to athlete 1; record 2 (no such athlete) stays NULL
  expect_true(nzchar(page$results[[1]]$subject$first_name))
  expect_identical(page$results[[1]]$subject$id, 1L)
  expect_null(page$results[[2]]$subject)
})

test_that("empty registry still yields empty/NULL reads (back-compat)", {
  local_clean_sandbox()
  expect_identical(suppressMessages(fetch_org_options(sandbox = TRUE)), list())
  expect_identical(suppressMessages(fetch_profiles(sandbox = TRUE)), list())
  expect_null(suppressMessages(fetch_profile(profile_id = 1, sandbox = TRUE)))
})

test_that("an athlete's sport name is its sport org's name", {
  local_clean_sandbox()
  org <- suppressMessages(create_sport_org("Rowing Canada", id = 100))
  suppressMessages(create_profile(1, sport_org_id = 100, first_names = fn(1), last_names = ln(1)))
  p <- suppressMessages(fetch_profile(profile_id = 1, sandbox = TRUE))
  expect_identical(p$sport$name, org$name)
})

test_that("create_profile uses supplied first/last names", {
  local_clean_sandbox()
  suppressMessages(create_sport_org("Rowing Canada", id = 100))
  suppressMessages(create_profile(2, sport_org_id = 100,
                                  first_names = c("Ada", "Blair"),
                                  last_names  = c("Lovelace", "Okafor")))
  p <- suppressMessages(fetch_profile(profile_id = 1, sandbox = TRUE))
  expect_identical(p$person$first_name, "Ada")
  expect_identical(p$person$last_name, "Lovelace")
})

test_that("create_profile rejects half-specified or mismatched names", {
  local_clean_sandbox()
  suppressMessages(create_sport_org("Rowing Canada", id = 100))
  expect_error(
    suppressMessages(create_profile(2, sport_org_id = 100, first_names = c("Ada", "Blair"))),
    "both")
  expect_error(
    suppressMessages(create_profile(2, sport_org_id = 100,
                                    first_names = "Ada", last_names = c("Lovelace", "Okafor"))))
})

test_that("create_profile generates unique names from babynames when none given", {
  local_clean_sandbox()
  suppressMessages(create_sport_org("Rowing Canada", id = 100))
  suppressMessages(create_profile(20, sport_org_id = 100))
  profs <- suppressMessages(fetch_profiles(sandbox = TRUE))
  full <- vapply(profs, function(p) paste(p$person$first_name, p$person$last_name), character(1))
  expect_length(full, 20)
  expect_length(unique(full), 20)  # every athlete name distinct
})

test_that("record subjects resolve at read time so late profiles backfill", {
  local_clean_sandbox()
  suppressMessages(create_sport_org("Rowing Canada", id = 100))
  suppressMessages(create_profile(1, sport_org_id = 100, first_names = fn(1), last_names = ln(1)))  # athlete id 1

  schema <- list(type = "object", required = list("athlete_id"),
                 properties = list(athlete_id = list(type = "integer")))
  suppressMessages(register_sandbox_schema("src-bf", schema))
  # Ingest a record for athlete 2, who does not exist yet
  suppressMessages(make_request(
    endpoint = "api/warehouse/ingestion/primary/", method = "POST",
    body = list(source = "src-bf",
                records = list(list(athlete_id = 2L)),
                subject_field = "athlete_id"),
    sandbox = TRUE))

  before <- suppressMessages(make_request(
    endpoint = "api/warehouse/data-records", method = "GET",
    query = list(source_uuid = "src-bf"), sandbox = TRUE))
  expect_null(before$results[[1]]$subject)

  # Register athlete 2 after ingestion; the same record now backfills
  suppressMessages(create_profile(1, sport_org_id = 100, first_names = fn(1), last_names = ln(1)))  # athlete id 2
  after <- suppressMessages(make_request(
    endpoint = "api/warehouse/data-records", method = "GET",
    query = list(source_uuid = "src-bf"), sandbox = TRUE))
  expect_identical(after$results[[1]]$subject$id, 2L)
})

test_that("create_* warn when not in sandbox mode", {
  local_clean_sandbox()
  withr::local_options(csiapps.sandbox = FALSE)
  expect_warning(suppressMessages(create_sport_org("Rowing Canada", id = 100)), "sandbox")
  expect_warning(
    suppressMessages(create_profile(1, sport_org_id = 100, first_names = fn(1), last_names = ln(1))),
    "sandbox")
})

test_that("create_sport_org rejects invalid supplied ids", {
  local_clean_sandbox()
  expect_error(suppressMessages(create_sport_org("Rowing Canada", id = 0)))
  expect_error(suppressMessages(create_sport_org("Rowing Canada", id = -5)))
  expect_error(suppressMessages(create_sport_org("Rowing Canada", id = 1.5)))
})

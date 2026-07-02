# Sandbox endpoint emulation: schema registration, ingestion, retrieval,
# clearing, and error routes

# ---- register_sandbox_schema -------------------------------------------

test_that("schemas can be registered from a list, JSON string, and file", {
  local_clean_sandbox()

  # list
  expect_message(register_sandbox_schema("from-list", test_schema()), "schema registered")

  # JSON string
  json <- jsonlite::toJSON(test_schema(), auto_unbox = TRUE)
  suppressMessages(register_sandbox_schema("from-string", as.character(json)))

  # file path
  path <- withr::local_tempfile(fileext = ".json")
  writeLines(as.character(json), path)
  suppressMessages(register_sandbox_schema("from-file", path))

  for (uuid in c("from-list", "from-string", "from-file")) {
    res <- suppressMessages(make_request(
      paste0("api/warehouse/data-sources/", uuid), sandbox = TRUE))
    expect_identical(res$head_primary_definition$schema$title, "A registration form")
  }
})

test_that("registering a schema again overwrites the previous one", {
  local_clean_sandbox()
  suppressMessages(register_sandbox_schema("overwrite", test_schema()))
  s2 <- test_schema()
  s2$title <- "Version 2"
  suppressMessages(register_sandbox_schema("overwrite", s2))

  res <- suppressMessages(make_request("api/warehouse/data-sources/overwrite", sandbox = TRUE))
  expect_identical(res$head_primary_definition$schema$title, "Version 2")
})

test_that("register_sandbox_schema rejects invalid arguments", {
  expect_error(register_sandbox_schema(42, test_schema()))
  expect_error(register_sandbox_schema("", test_schema()))
  expect_error(register_sandbox_schema(c("a", "b"), test_schema()))
  expect_error(register_sandbox_schema("ok", 42), "must be a list")
})

# ---- schema retrieval route --------------------------------------------

test_that("schema retrieval returns the API response shape", {
  local_clean_sandbox()
  suppressMessages(register_sandbox_schema("shape", test_schema()))

  res <- suppressMessages(make_request("api/warehouse/data-sources/shape", sandbox = TRUE))
  expect_identical(res$uuid, "shape")
  expect_type(res$head_primary_definition, "list")
  expect_identical(res$head_primary_definition$schema, test_schema())
})

test_that("schema retrieval tolerates leading and trailing slashes", {
  local_clean_sandbox()
  suppressMessages(register_sandbox_schema("slashes", test_schema()))

  for (ep in c("api/warehouse/data-sources/slashes",
               "/api/warehouse/data-sources/slashes",
               "api/warehouse/data-sources/slashes/",
               "/api/warehouse/data-sources/slashes/")) {
    res <- suppressMessages(make_request(ep, sandbox = TRUE))
    expect_identical(res$uuid, "slashes")
  }
})

test_that("retrieving an unregistered schema fails like a 404", {
  local_clean_sandbox()
  expect_error(
    suppressMessages(make_request("api/warehouse/data-sources/nope", sandbox = TRUE)),
    "API request failed \\(404\\).*register_sandbox_schema"
  )
})

# ---- ingestion route ---------------------------------------------------

test_that("valid records are ingested with the real 201 response shape", {
  local_clean_sandbox()
  res <- quiet_ingest("ingest-ok")

  expect_named(res, c("dataset", "created_records"))
  expect_identical(res$created_records, 2L)
  expect_identical(res$dataset$source, "ingest-ok")
  expect_true(nzchar(res$dataset$uuid))
})

test_that("ingestion accepts a lowercase method", {
  local_clean_sandbox()
  suppressMessages(register_sandbox_schema("lower", test_schema()))
  res <- suppressMessages(make_request(
    "api/warehouse/ingestion/primary/", method = "post",
    body = list(source = "lower", records = test_records()), sandbox = TRUE))
  expect_identical(res$created_records, 2L)
})

test_that("schema violations are rejected with indices and Ajv detail", {
  local_clean_sandbox()
  suppressMessages(register_sandbox_schema("invalid", test_schema()))

  bad <- list(
    list(id = "a", firstName = "Too", lastName = "Short", telephone = "123"), # minLength
    list(firstName = "No", lastName = "Id"),                                  # missing required
    list(id = "c", firstName = "Bad", lastName = "Age", age = "thirty")       # wrong type
  )
  err <- tryCatch(
    suppressMessages(make_request("api/warehouse/ingestion/primary/", method = "POST",
                 body = list(source = "invalid", records = bad), sandbox = TRUE)),
    error = conditionMessage)

  expect_match(err, "API request failed \\(400\\)")
  expect_match(err, "record\\(s\\) 1, 2, 3")
  expect_match(err, "fewer than 10 characters")   # Ajv minLength detail
  expect_match(err, "required")                    # Ajv required detail
})

test_that("a batch with any invalid record stores nothing (all-or-nothing)", {
  local_clean_sandbox()
  suppressMessages(register_sandbox_schema("atomic", test_schema()))

  mixed <- c(test_records(), list(list(firstName = "No", lastName = "Id")))
  expect_error(
    suppressMessages(make_request("api/warehouse/ingestion/primary/", method = "POST",
                 body = list(source = "atomic", records = mixed), sandbox = TRUE)),
    "record\\(s\\) 3"
  )

  page <- suppressMessages(make_request("api/warehouse/data-records",
              query = list(source_uuid = "atomic"), sandbox = TRUE))
  expect_identical(page$count, 0L)
})

test_that("ingestion validates required body fields", {
  local_clean_sandbox()
  suppressMessages(register_sandbox_schema("body-check", test_schema()))

  expect_error(
    suppressMessages(make_request("api/warehouse/ingestion/primary/", method = "POST",
                 body = list(records = test_records()), sandbox = TRUE)),
    "API request failed \\(400\\)")
  expect_error(
    suppressMessages(make_request("api/warehouse/ingestion/primary/", method = "POST",
                 body = list(source = "body-check"), sandbox = TRUE)),
    "API request failed \\(400\\)")
  expect_error(
    suppressMessages(make_request("api/warehouse/ingestion/primary/", method = "POST",
                 body = list(source = "body-check", records = list()), sandbox = TRUE)),
    "no records provided")
})

test_that("ingesting to an unregistered source fails like a 404", {
  local_clean_sandbox()
  expect_error(
    suppressMessages(make_request("api/warehouse/ingestion/primary/", method = "POST",
                 body = list(source = "ghost", records = test_records()), sandbox = TRUE)),
    "API request failed \\(404\\)")
})

test_that("accepted payloads are written to one folder per source", {
  local_clean_sandbox()
  quiet_ingest("disk-a")
  quiet_ingest("disk-a", records = list(list(id = "z", firstName = "Zoe", lastName = "Zed")))
  quiet_ingest("disk-b")

  dir_a <- file.path(csiapps:::sandbox_dir(), "disk-a")
  dir_b <- file.path(csiapps:::sandbox_dir(), "disk-b")
  files_a <- list.files(dir_a, pattern = "^payload_.*\\.json$", full.names = TRUE)
  files_b <- list.files(dir_b, pattern = "^payload_.*\\.json$", full.names = TRUE)
  expect_length(files_a, 2)
  expect_length(files_b, 1)

  # payload files round-trip as valid JSON matching what was ingested
  reread <- jsonlite::fromJSON(files_b[1], simplifyVector = FALSE)
  expect_length(reread, 2)
  expect_identical(reread[[1]]$id, "xxxx")
})

test_that("a schema with a single required field still enforces it", {
  local_clean_sandbox()
  suppressMessages(register_sandbox_schema("single-req", '{
    "type": "object",
    "required": ["id"],
    "properties": {"id": {"type": "string"}}
  }'))

  # missing the single required field must be rejected
  expect_error(
    suppressMessages(make_request("api/warehouse/ingestion/primary/", method = "POST",
                 body = list(source = "single-req", records = list(list(other = "x"))),
                 sandbox = TRUE)),
    "API request failed \\(400\\)")
})

# ---- retrieval route ---------------------------------------------------

test_that("retrieved records use the warehouse envelope shape", {
  local_clean_sandbox()
  ingest_res <- quiet_ingest("envelope")

  page <- suppressMessages(make_request("api/warehouse/data-records",
              query = list(source_uuid = "envelope"), sandbox = TRUE))

  expect_named(page, c("count", "next", "previous", "results"))
  expect_identical(page$count, 2L)
  expect_length(page$results, 2)

  rec <- page$results[[1]]
  expect_named(rec, c("id", "dataset_uuid", "data", "subject", "created_at", "updated_at"))
  expect_null(rec$subject)                                    # documented limitation
  expect_identical(rec$dataset_uuid, ingest_res$dataset$uuid)
  expect_identical(rec$data, test_records()[[1]])
  expect_match(rec$created_at, "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$")
})

test_that("record ids increment across ingests", {
  local_clean_sandbox()
  quiet_ingest("ids")
  quiet_ingest("ids", records = list(list(id = "z", firstName = "Zoe", lastName = "Zed")))

  page <- suppressMessages(make_request("api/warehouse/data-records",
              query = list(source_uuid = "ids"), sandbox = TRUE))
  expect_identical(vapply(page$results, `[[`, integer(1), "id"), 1:3)
})

test_that("paginate = TRUE returns a list of pages, matching production", {
  local_clean_sandbox()
  quiet_ingest("pages")

  pages <- suppressMessages(make_request("api/warehouse/data-records",
              query = list(source_uuid = "pages"), paginate = TRUE, sandbox = TRUE))
  expect_length(pages, 1)
  expect_identical(pages[[1]]$count, 2L)
  expect_null(pages[[1]]$`next`)
})

test_that("retrieval from a source with no records returns an empty page", {
  local_clean_sandbox()
  page <- suppressMessages(make_request("api/warehouse/data-records",
              query = list(source_uuid = "never-ingested"), sandbox = TRUE))
  expect_identical(page$count, 0L)
  expect_length(page$results, 0)
})

test_that("retrieval without source_uuid fails like a 400", {
  expect_error(
    suppressMessages(make_request("api/warehouse/data-records", sandbox = TRUE)),
    "API request failed \\(400\\).*source_uuid")
})

test_that("sandbox records are compatible with flatten_record", {
  local_clean_sandbox()
  quiet_ingest("flatten")

  page <- suppressMessages(make_request("api/warehouse/data-records",
              query = list(source_uuid = "flatten"), sandbox = TRUE))
  flat <- csiapps:::flatten_record(page$results[[1]])

  expect_identical(flat$profile, "-")   # NULL subject falls back gracefully
  expect_identical(flat$sport, NA)
  expect_identical(flat$data$id, "xxxx")
})

# ---- clear_sandbox / browse_sandbox ------------------------------------

test_that("targeted clear removes one source and leaves others intact", {
  local_clean_sandbox()
  quiet_ingest("keep")
  quiet_ingest("drop")

  expect_message(clear_sandbox("drop"), "cleared source 'drop'")

  expect_false(dir.exists(file.path(csiapps:::sandbox_dir(), "drop")))
  expect_error(
    suppressMessages(make_request("api/warehouse/data-sources/drop", sandbox = TRUE)), "404")

  kept <- suppressMessages(make_request("api/warehouse/data-records",
              query = list(source_uuid = "keep"), sandbox = TRUE))
  expect_identical(kept$count, 2L)
  expect_true(dir.exists(file.path(csiapps:::sandbox_dir(), "keep")))
})

test_that("global clear wipes all schemas, records, and folders", {
  local_clean_sandbox()
  quiet_ingest("wipe-1")
  quiet_ingest("wipe-2")

  expect_message(clear_sandbox(), "entire sandbox cleared")

  expect_length(list.dirs(csiapps:::sandbox_dir(), recursive = FALSE), 0)
  for (uuid in c("wipe-1", "wipe-2")) {
    expect_error(
      suppressMessages(make_request(paste0("api/warehouse/data-sources/", uuid), sandbox = TRUE)),
      "404")
    page <- suppressMessages(make_request("api/warehouse/data-records",
                query = list(source_uuid = uuid), sandbox = TRUE))
    expect_identical(page$count, 0L)
  }
})

test_that("clearing a source that was never registered does not error", {
  expect_message(clear_sandbox("never-existed"), "cleared source")
})

test_that("browse_sandbox errors for a source with no payload folder", {
  local_clean_sandbox()
  expect_error(browse_sandbox("no-such-source"), "does not exist")
})

# ---- unsupported endpoints ---------------------------------------------

test_that("unsupported endpoints fail like a 501 listing what is supported", {
  err <- tryCatch(
    suppressMessages(make_request("api/csiauth/me/", sandbox = TRUE)),
    error = conditionMessage)
  expect_match(err, "API request failed \\(501\\)")
  expect_match(err, "not emulated")
  expect_match(err, "api/warehouse/ingestion/primary")

  # right path, wrong method is also unsupported
  expect_error(
    suppressMessages(make_request("api/warehouse/data-records", method = "POST", sandbox = TRUE)),
    "501")
  expect_error(
    suppressMessages(make_request("api/warehouse/ingestion/primary/", method = "GET", sandbox = TRUE)),
    "501")
})

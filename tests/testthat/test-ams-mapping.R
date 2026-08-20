ams_schema <- function() {
  list(
    type = "object",
    additionalProperties = FALSE,
    required = as.list(c("id", "vendor", "vendor_profile_id", "vendor_profile_name")),
    properties = list(
      id = list(type = "number"),
      vendor = list(type = "string"),
      vendor_profile_id = list(type = "string"),
      vendor_profile_name = list(type = "string")
    )
  )
}

test_that("fetch_ams_mapping returns the four-column sandbox mapping", {
  local_clean_sandbox()
  records <- list(
    list(id = 1, vendor = "VendorX", vendor_profile_id = "VX-1",
         vendor_profile_name = "Ada N."),
    list(id = 2, vendor = "VendorX", vendor_profile_id = "VX-2",
         vendor_profile_name = "Blair O.")
  )
  suppressMessages(register_sandbox_schema("ams-test", ams_schema()))
  suppressMessages(make_request(
    "api/warehouse/ingestion/primary/",
    method = "POST",
    body = list(source = "ams-test", records = records, subject_field = "id"),
    sandbox = TRUE
  ))

  actual <- suppressMessages(fetch_ams_mapping("ams-test", sandbox = TRUE))

  expect_s3_class(actual, "data.frame")
  expect_named(actual, c("id", "vendor", "vendor_profile_id", "vendor_profile_name"))
  expect_equal(actual, do.call(rbind, lapply(records, as.data.frame)))
})

test_that("fetch_ams_mapping reduces paginated production history", {
  pages <- list(
    list(results = list(
      list(id = 1, updated_at = "2026-01-01T00:00:00Z",
           data = list(id = 1, vendor = "VendorX", vendor_profile_id = "VX-1",
                       vendor_profile_name = "Ada", active = TRUE)),
      list(id = 2, updated_at = "2026-01-02T00:00:00Z",
           data = list(id = 1, vendor = "VendorX", vendor_profile_id = "VX-1",
                       vendor_profile_name = "Ada", active = FALSE)),
      list(id = 3, updated_at = "2026-01-03T00:00:00Z",
           data = list(id = 2, vendor = "VendorX", vendor_profile_id = "VX-1",
                       vendor_profile_name = "Ada corrected", active = TRUE))
    )),
    list(results = list(
      list(id = 4, updated_at = "2026-01-04T00:00:00Z",
           data = list(id = 3, vendor = "VendorY", vendor_profile_id = "VY-3",
                       vendor_profile_name = "Cai")),
      list(id = 10, updated_at = "2026-01-05T00:00:00Z",
           data = list(id = 4, vendor = "VendorY", vendor_profile_id = "VY-4",
                       vendor_profile_name = "Devon", active = TRUE)),
      list(id = 11, updated_at = "2026-01-05T00:00:00Z",
           data = list(id = 4, vendor = "VendorY", vendor_profile_id = "VY-4",
                       vendor_profile_name = "Devon", active = FALSE))
    ))
  )
  testthat::local_mocked_bindings(make_request = function(...) pages)

  actual <- fetch_ams_mapping("prod-ams", token = "token", sandbox = FALSE)

  expect_equal(actual$id, c(2, 3))
  expect_equal(actual$vendor_profile_name, c("Ada corrected", "Cai"))
  expect_named(actual, c("id", "vendor", "vendor_profile_id", "vendor_profile_name"))
})

test_that("fetch_ams_mapping handles empty and malformed responses", {
  testthat::local_mocked_bindings(
    make_request = function(...) list(list(results = list()))
  )
  empty <- fetch_ams_mapping("prod-ams", sandbox = FALSE)
  expect_equal(nrow(empty), 0)
  expect_named(empty, c("id", "vendor", "vendor_profile_id", "vendor_profile_name"))

  testthat::local_mocked_bindings(
    make_request = function(...) list(list(results = list(
      list(id = 1, updated_at = "2026-01-01T00:00:00Z",
           data = list(id = 1, vendor = "VendorX", vendor_profile_id = "VX-1"))
    )))
  )
  expect_error(fetch_ams_mapping("prod-ams", sandbox = FALSE),
               "record 1.*vendor_profile_name")
  expect_error(fetch_ams_mapping("", sandbox = TRUE), "AMS_MAPPING_UUID")
})

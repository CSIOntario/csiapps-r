# Shared fixtures for sandbox tests

# The example schema from the API vignette
test_schema <- function() {
  list(
    title = "A registration form",
    type = "object",
    required = list("id", "firstName", "lastName"),
    properties = list(
      id        = list(type = "string"),
      firstName = list(type = "string"),
      lastName  = list(type = "string"),
      age       = list(type = "integer"),
      telephone = list(type = "string", minLength = 10)
    )
  )
}

test_records <- function() {
  list(
    list(id = "xxxx", firstName = "John", lastName = "Doe",   age = 30, telephone = "1234567890"),
    list(id = "yyyy", firstName = "Jane", lastName = "Smith", age = 25, telephone = "0987654321")
  )
}

# Register a schema and ingest records quietly; returns the ingest response
quiet_ingest <- function(uuid, records = test_records(), schema = test_schema()) {
  suppressMessages(register_sandbox_schema(uuid, schema))
  suppressMessages(make_request(
    endpoint = "api/warehouse/ingestion/primary/",
    method = "POST",
    body = list(source = uuid, records = records, subject_field = "id"),
    sandbox = TRUE
  ))
}

# Reset sandbox state before/after a test
local_clean_sandbox <- function(env = parent.frame()) {
  suppressMessages(clear_sandbox())
  withr::defer(suppressMessages(clear_sandbox()), envir = env)
}

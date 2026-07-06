# -------------------------------------------------------------------
# Local sandbox emulation of the CSIAPPS data warehouse
# -------------------------------------------------------------------

#' Sandbox mode for local development
#'
#' @description
#' Sandbox mode lets developers run the full schema -> validate -> ingest ->
#' retrieve warehouse workflow entirely locally, with no network access and no
#' authentication. **Sandbox mode is enabled by default**, so that development
#' work never reaches the production warehouse by accident: the same
#' [make_request()] calls are routed to a local, in-memory warehouse instead of
#' the REST API. It is disabled for deployment with
#' `options(csiapps.sandbox = FALSE)` (or by setting `CSIAPPS_ENV=production`),
#' and can be overridden per call with the `sandbox` argument of
#' [make_request()]. Because the production and sandbox workflows use the same
#' calls, no code changes are needed when moving from development to deployment.
#'
#' The sandbox emulates three endpoints:
#'
#' * `GET api/warehouse/data-sources/{uuid}` -- returns the schema previously
#'   registered with [register_sandbox_schema()], nested under
#'   `head_primary_definition$schema` exactly like the real API.
#' * `POST api/warehouse/ingestion/primary/` -- validates `body$records`
#'   against the registered schema for `body$source` (using `jsonvalidate`)
#'   and, on success, stores them in memory and writes the JSON payload to a
#'   per-source folder on disk for inspection (see [browse_sandbox()]).
#' * `GET api/warehouse/data-records` -- returns previously ingested records
#'   for `query$source_uuid`, each wrapped in the same envelope
#'   (`data`, `subject`, `created_at`, ...) the real API returns.
#'
#' Any other endpoint raises an error. Sandbox state lasts for the R session;
#' use [clear_sandbox()] to reset it between tests.
#'
#' @section Shiny app wrappers:
#' Sandbox mode also lets a wrapped Shiny app (see [ui_wrapper()],
#' [server_wrapper()], [check_secrets()]) run locally without the OAuth2
#' redirect. The redirect exists only to obtain an access token, and requires
#' client credentials that cannot be safely distributed, so in sandbox mode
#' [server_wrapper()] **simulates the login** instead: it seeds the session from
#' the developer's existing `CSIAPPS_ACCESS_TOKEN` and hands it to the same code
#' path a production login would. If that token is present, `/me` and the
#' organization list are loaded from the **real** registration API, so the
#' developer sees their real identity and organizations. If no token is set, the
#' app shell still renders but shows an unauthenticated notice prompting the
#' developer to set a read-only `CSIAPPS_ACCESS_TOKEN`. The same wrapped-app code
#' therefore runs in both modes; only the `csiapps.sandbox` option differs.
#'
#' @section Limitations:
#' * **Sandbox is not fully offline for wrapped apps.** Warehouse endpoints
#'   routed through [make_request()] are emulated locally, but the wrapper's
#'   registration reads (`/me`, organizations, profiles) bypass [make_request()]
#'   and call the real API with your token. Sandbox mode is thus deliberately
#'   split: warehouse data is emulated, registration/auth data is real. Set the
#'   institute with [set_institute()] to match the institute that issued your
#'   token, or those reads will be rejected.
#' The sandbox faithfully simulates the *schema contract*, not the warehouse.
#' Anything that depends on server-side state will differ from production:
#'
#' * **Validation parity is approximate.** Sandbox ingestion validates records
#'   against the JSON Schema with Ajv (via `jsonvalidate`), which catches the
#'   most common failure modes (missing required fields, wrong types, length
#'   and pattern violations). The real server additionally enforces things the
#'   schema cannot express: resolution of `subject_field` values against
#'   registered profiles, duplicate/dataset handling against existing data,
#'   and token permissions. Validator implementations may also differ on edge
#'   cases (e.g. `format` keyword enforcement). Passing sandbox validation is
#'   therefore a *necessary but not sufficient* condition for production
#'   acceptance -- do not treat a green sandbox run as a guarantee.
#' * **`subject` is always `NULL` in retrieved records.** In production the
#'   server links each ingested record to a registered profile and returns it
#'   (name, sport, ...) in the record envelope. The sandbox has no profile
#'   registry, so it cannot emulate this linkage and returns `subject = NULL`
#'   rather than fabricating misleading data. Code that displays or filters on
#'   subject fields will see placeholder values, and mistyped `subject_field`
#'   values that production would flag are accepted silently.
#'
#' @name csiapps-sandbox
NULL

# Hidden environment holding sandbox state for the session
.sandbox_env <- new.env(parent = emptyenv())
.sandbox_env$schemas <- list()
.sandbox_env$records <- list()
.sandbox_env$dir     <- NULL

# Lazily create the on-disk sandbox directory (tempdir-based, per session)
sandbox_dir <- function() {
  if (is.null(.sandbox_env$dir) || !dir.exists(.sandbox_env$dir)) {
    .sandbox_env$dir <- tempfile(pattern = "csiapps_sandbox_")
    dir.create(.sandbox_env$dir, recursive = TRUE)
  }
  .sandbox_env$dir
}

# Strip leading/trailing slashes so routing tolerates both
# "api/warehouse/data-records" and "/api/warehouse/data-records/"
normalize_endpoint <- function(endpoint) {
  gsub("^/+|/+$", "", endpoint)
}

sandbox_error <- function(status, msg) {
  # Mirror the error format of the real HTTP path so tryCatch-based
  # error handling works identically in both modes
  stop(sprintf("API request failed (%s): %s [csiapps sandbox]", status, msg), call. = FALSE)
}

#' Register a JSON schema in the local sandbox
#'
#' Makes a schema available to sandbox requests under the given data source
#' uuid, emulating a data source that exists in the warehouse. The uuid does
#' not need to be a real production uuid -- any identifying string works.
#'
#' @param source_uuid Character. Identifier of the emulated data source.
#' @param schema The JSON Schema for the data source: an R list (as returned by
#' `data_source$head_primary_definition$schema`), a JSON string, or a path to a
#' JSON file.
#'
#' @return The parsed schema, invisibly
#' @seealso [csiapps-sandbox] for an overview of sandbox mode and its limitations
#' @export
#' @examples
#' register_sandbox_schema("dummy-1234", '{
#'   "type": "object",
#'   "required": ["id"],
#'   "properties": {"id": {"type": "string"}}
#' }')
#' clear_sandbox()
register_sandbox_schema <- function(source_uuid, schema) {
  stopifnot(is.character(source_uuid), length(source_uuid) == 1, nzchar(source_uuid))

  if (is.character(schema)) {
    schema <- jsonlite::fromJSON(schema, simplifyVector = FALSE)
  }
  if (!is.list(schema)) {
    stop("register_sandbox_schema: `schema` must be a list, a JSON string, or a path to a JSON file.", call. = FALSE)
  }

  .sandbox_env$schemas[[source_uuid]] <- schema
  message(sprintf("csiapps sandbox: schema registered for source '%s'", source_uuid))
  invisible(schema)
}

#' Clear the local sandbox
#'
#' Removes registered schemas, in-memory records, and on-disk payload files.
#' With no arguments the entire sandbox is reset; with a `source_uuid` only
#' that data source is cleared. Useful as test teardown between unit tests.
#'
#' @param source_uuid Character. Optional. If provided, clears only the schema,
#' records, and payload folder for that specific source.
#'
#' @return Invisibly, NULL
#' @seealso [csiapps-sandbox] for an overview of sandbox mode and its limitations
#' @export
#' @examples
#' clear_sandbox()
clear_sandbox <- function(source_uuid = NULL) {
  if (is.null(source_uuid)) {
    .sandbox_env$schemas <- list()
    .sandbox_env$records <- list()

    if (!is.null(.sandbox_env$dir) && dir.exists(.sandbox_env$dir)) {
      unlink(list.dirs(.sandbox_env$dir, full.names = TRUE, recursive = FALSE), recursive = TRUE)
    }
    message("csiapps sandbox: entire sandbox cleared")
  } else {
    .sandbox_env$schemas[[source_uuid]] <- NULL
    .sandbox_env$records[[source_uuid]] <- NULL

    if (!is.null(.sandbox_env$dir)) {
      target_dir <- file.path(.sandbox_env$dir, source_uuid)
      if (dir.exists(target_dir)) unlink(target_dir, recursive = TRUE)
    }
    message(sprintf("csiapps sandbox: cleared source '%s'", source_uuid))
  }
  invisible(NULL)
}

#' Open the sandbox payload directory in the system file explorer
#'
#' Ingested payloads are written as pretty-printed JSON files, one folder per
#' data source, so developers can inspect the exact JSON that would have been
#' sent to the real API.
#'
#' @param source_uuid Character. Optional. If provided, opens that specific
#' source's payload folder instead of the sandbox root.
#'
#' @return Invisibly, the path to the opened directory
#' @seealso [csiapps-sandbox] for an overview of sandbox mode and its limitations
#' @export
browse_sandbox <- function(source_uuid = NULL) {
  target_dir <- sandbox_dir()
  if (!is.null(source_uuid)) {
    target_dir <- file.path(target_dir, source_uuid)
  }
  if (!dir.exists(target_dir)) {
    stop(sprintf("csiapps sandbox: directory '%s' does not exist. Have you ingested any data yet?", target_dir), call. = FALSE)
  }
  utils::browseURL(target_dir)
  invisible(target_dir)
}

# ---- Internal request router -------------------------------------------

# Emulates make_request() against the local sandbox. Same argument meanings
# as make_request(); headers/token/timeout/max_pages are HTTP-only and ignored.
.make_sandbox_request <- function(
    endpoint,
    method = "GET",
    body = NULL,
    query = list(),
    verbose = FALSE,
    paginate = FALSE
  ) {
  ep     <- normalize_endpoint(endpoint)
  method <- toupper(method)

  message(sprintf("csiapps sandbox: emulating %s %s (no real API call made)", method, ep))

  # ROUTE 1: schema retrieval -- GET api/warehouse/data-sources/{uuid}
  if (grepl("^api/warehouse/data-sources/.+$", ep) && method == "GET") {
    source_uuid <- sub("^api/warehouse/data-sources/", "", ep)
    schema <- .sandbox_env$schemas[[source_uuid]]
    if (is.null(schema)) {
      sandbox_error(404, sprintf(
        "no schema registered for source '%s'. Register one with register_sandbox_schema().", source_uuid))
    }
    return(list(
      uuid = source_uuid,
      head_primary_definition = list(schema = schema)
    ))
  }

  # ROUTE 2: ingestion -- POST api/warehouse/ingestion/primary/
  if (ep == "api/warehouse/ingestion/primary" && method == "POST") {
    return(sandbox_ingest(body, verbose = verbose))
  }

  # ROUTE 3: record retrieval -- GET api/warehouse/data-records
  if (ep == "api/warehouse/data-records" && method == "GET") {
    source_uuid <- query$source_uuid
    if (is.null(source_uuid)) {
      sandbox_error(400, "'source_uuid' query parameter is required.")
    }

    records <- .sandbox_env$records[[source_uuid]] %||% list()
    page <- list(
      count    = length(records),
      `next`   = NULL,
      previous = NULL,
      results  = records
    )
    # The real make_request(paginate = TRUE) returns a list of parsed pages
    if (paginate) return(list(page))
    return(page)
  }

  sandbox_error(501, sprintf(
    paste0("endpoint '%s' (%s) is not emulated by the sandbox. Supported: ",
           "GET api/warehouse/data-sources/{uuid}, ",
           "POST api/warehouse/ingestion/primary/, ",
           "GET api/warehouse/data-records."),
    ep, method))
}

# ---- Sandbox session seeding for server_wrapper() ----------------------

# Simulate the OAuth redirect for a wrapped Shiny app in sandbox mode.
#
# The real redirect exists only to obtain an access token, so instead of
# contacting the identity provider (which would require client credentials
# we cannot safely distribute) we reuse the CSIAPPS_ACCESS_TOKEN the
# developer already has. The seeded token is handed to the *same*
# observeEvent(user_token()) consumer server_wrapper() uses in production,
# so `/me` and the organization list are loaded from the real registration
# API exactly as they would be after a production login.
#
# When no token is present the app still runs, but with a simulated identity
# (see the `csiapps.sandbox_user` option) and no real data -- enough to
# exercise the UI shell offline.
#
# @param user_token,userinfo the reactiveVals created in server_wrapper()
# @keywords internal
.sandbox_seed_session <- function(user_token, userinfo) {
  tok <- Sys.getenv("CSIAPPS_ACCESS_TOKEN")
  if (nzchar(tok)) {
    message("csiapps sandbox: simulating login with your existing CSIAPPS_ACCESS_TOKEN")
    # `sandbox = TRUE` marks the origin; the shared consumer only reads $access_token
    user_token(list(access_token = tok, sandbox = TRUE))
  } else {
    message("csiapps sandbox: no CSIAPPS_ACCESS_TOKEN set; running unauthenticated")
    # Non-null sentinel with no $access_token: shared consumer short-circuits before
    # any network call; auth_status shows an unauthenticated notice
    user_token(list(sandbox = TRUE, unauthenticated = TRUE))
  }
  invisible(NULL)
}

# Validate and store records for POST api/warehouse/ingestion/primary/
sandbox_ingest <- function(body, verbose = FALSE) {
  source_uuid <- body$source
  records     <- body$records

  if (is.null(source_uuid) || is.null(records)) {
    sandbox_error(400, "'source' and 'records' must be provided in the body.")
  }
  if (length(records) == 0) {
    sandbox_error(400, "no records provided.")
  }

  schema <- .sandbox_env$schemas[[source_uuid]]
  if (is.null(schema)) {
    sandbox_error(404, sprintf(
      "no schema registered for source '%s'. Register one with register_sandbox_schema().", source_uuid))
  }

  if (!requireNamespace("jsonvalidate", quietly = TRUE)) {
    stop("csiapps sandbox: package 'jsonvalidate' is required for sandbox ingestion. ",
         "Install it with install.packages(\"jsonvalidate\").", call. = FALSE)
  }

  # Validate exactly as the API vignette does, so R-to-JSON serialization
  # quirks (auto_unbox, NA handling) are exercised faithfully
  json_schema <- jsonvalidate::json_schema$new(jsonlite::toJSON(schema, auto_unbox = TRUE))

  validation <- lapply(records, function(record) {
    json_schema$validate(jsonlite::toJSON(record, auto_unbox = TRUE), verbose = TRUE)
  })
  is_valid <- vapply(validation, isTRUE, logical(1))

  if (!all(is_valid)) {
    failed <- which(!is_valid)
    details <- vapply(failed, function(i) {
      errs <- attr(validation[[i]], "errors")
      msg <- if (is.null(errs)) "" else paste0(errs$instancePath, " ", errs$message, collapse = "; ")
      sprintf("record %d: %s", i, msg)
    }, character(1))
    sandbox_error(400, paste0(
      "validation failed for record(s) ", paste(failed, collapse = ", "), ".\n",
      paste(details, collapse = "\n")))
  }

  now          <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  dataset_uuid <- paste(sprintf("%02x", as.integer(openssl::rand_bytes(16))), collapse = "")
  n_existing   <- length(.sandbox_env$records[[source_uuid]])

  # Wrap each record in the envelope shape returned by the real
  # data-records endpoint (see flatten_record()); subject linkage cannot
  # be emulated locally, so subject is always NULL
  wrapped <- lapply(seq_along(records), function(i) {
    list(
      id           = n_existing + i,
      dataset_uuid = dataset_uuid,
      data         = records[[i]],
      subject      = NULL,
      created_at   = now,
      updated_at   = now
    )
  })
  .sandbox_env$records[[source_uuid]] <- c(.sandbox_env$records[[source_uuid]], wrapped)

  # Write the payload to disk for developer inspection
  target_dir <- file.path(sandbox_dir(), source_uuid)
  if (!dir.exists(target_dir)) dir.create(target_dir, recursive = TRUE)
  file_name <- sprintf("payload_%s_%03d.json",
                       format(Sys.time(), "%Y%m%d_%H%M%S"),
                       length(list.files(target_dir)) + 1L)
  file_path <- file.path(target_dir, file_name)
  writeLines(jsonlite::toJSON(records, auto_unbox = TRUE, na = "null", pretty = TRUE), file_path)

  if (verbose) {
    message(sprintf("csiapps sandbox: %d record(s) validated and stored for source '%s'", length(records), source_uuid))
    message("  payload written to: ", file_path)
  }

  # Same response shape as the real 201 ingestion response
  list(
    dataset = list(uuid = dataset_uuid, source = source_uuid),
    created_records = length(records)
  )
}

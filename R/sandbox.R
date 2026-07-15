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
#' path a production login would. The token is used **only to emulate the
#' login**: if it is present, `/me` is loaded from the real API so the header
#' shows the developer's real identity. All *data* -- sport organizations,
#' athletes/profiles, and warehouse records -- is served from the local sandbox
#' (the dummy registry and the emulated warehouse), never the live API. If no
#' token is set, the app shell still renders but shows an unauthenticated notice
#' prompting the developer to set a read-only `CSIAPPS_ACCESS_TOKEN`. The same
#' wrapped-app code runs in both modes; only the `csiapps.sandbox` option differs.
#'
#' @section Limitations:
#' * **The access token is used only to emulate login.** A wrapped app's `/me`
#'   identity is fetched from the real API with your token, so set the institute
#'   with [set_institute()] to match the institute that issued it or `/me` is
#'   rejected. Everything else is dummy: sport organizations and athletes come
#'   from the local registry ([create_sport_org()], [create_profile()]) and
#'   warehouse reads/writes are emulated in memory. No real client data is read.
#' * **Only warehouse endpoints are routed through [make_request()].** Calling
#'   `make_request("api/registration/...")` in sandbox raises a 501; use the
#'   [fetch_org_options()] / [fetch_profiles()] helpers, which read the dummy
#'   registry instead. In sandbox, [fetch_profiles()] honours only the
#'   `sport_org_id` filter; other filters are ignored.
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
#' * **`subject` linkage is emulated only for registered athletes.** On
#'   retrieval the sandbox resolves each record's `subject_field` value against
#'   athletes registered with [create_profile()] and returns the matched athlete
#'   (id, name, sport) in the record envelope, mirroring production. Resolution
#'   happens at read time, so athletes registered after ingestion are linked on
#'   the next read. If no athlete matches -- because none was registered or the
#'   `subject_field` value is mistyped -- `subject` is `NULL` rather than
#'   fabricated. Production would reject an unresolved subject; the sandbox
#'   accepts it silently, so a green sandbox ingest does not guarantee the server
#'   will link every record.
#'
#' @name csiapps-sandbox
NULL

# Hidden environment holding sandbox state for the session
.sandbox_env <- new.env(parent = emptyenv())
.sandbox_env$schemas  <- list()
.sandbox_env$records  <- list()
.sandbox_env$orgs     <- list()  # dummy sport orgs, keyed by id (as character)
.sandbox_env$profiles <- list()  # dummy athlete profiles, in insertion order
.sandbox_env$dir      <- NULL

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
    .sandbox_env$schemas  <- list()
    .sandbox_env$records  <- list()
    .sandbox_env$orgs     <- list()
    .sandbox_env$profiles <- list()

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

# ---- Dummy registration registry (sport orgs + athletes) ---------------

.sandbox_org_ids <- function() {
  vapply(.sandbox_env$orgs, function(o) as.integer(o$id), integer(1))
}

# Resolve an ingested record's subject against the athlete registry, mirroring
# the production link: body$subject_field names the field in the record whose
# value must match a registered athlete's id. Returns NULL (an unlinked record,
# exactly as before) when there's no subject_field, no value, or no such athlete.
.sandbox_resolve_subject <- function(record, subject_field) {
  if (is.null(subject_field)) return(NULL)
  key <- record[[subject_field]]
  if (is.null(key)) return(NULL)
  hit <- Filter(function(p) identical(as.character(p$id), as.character(key)), .sandbox_env$profiles)
  if (!length(hit)) return(NULL)
  p <- hit[[1]]
  # Shape mirrors what flatten_record() reads off a record subject.
  list(
    id         = p$id,
    first_name = p$person$first_name,
    last_name  = p$person$last_name,
    sport      = p$sport
  )
}

# n unique first/last name pairs, drawn without replacement from babynames so
# every athlete name is distinct. babynames ships first names only, so we draw
# 2n distinct names from that pool and split them into firsts and lasts.
.sandbox_random_names <- function(n) {
  if (n == 0) return(list(first = character(0), last = character(0)))
  pool <- unique(babynames::babynames$name)
  if (length(pool) < 2 * n) {
    stop(sprintf("create_profile: cannot draw %d unique names; babynames has only %d.",
                 2 * n, length(pool)), call. = FALSE)
  }
  draw <- sample(pool, 2 * n)  # without replacement -> all distinct
  list(first = draw[seq_len(n)], last = draw[n + seq_len(n)])
}

# Build one prod-shaped athlete profile. Identity (first/last) is supplied by
# the caller and the sport-org link (sport$id) plus sport$name come from the
# org; the remaining fields are schema-shaped placeholders so the object matches
# the /api/registration/profile/ athlete payload.
.sandbox_make_profile <- function(id, sport_org_id, first, last) {
  # Athlete's sport name is the org's name, so profile and org stay coherent.
  org_name <- .sandbox_env$orgs[[as.character(sport_org_id)]]$name
  list(
    role_slug = "athlete",
    id        = id,
    person = list(
      id                    = id,
      first_name            = first,
      last_name             = last,
      email                 = sprintf("%s.%s@example.com", tolower(first), tolower(last)),
      dob                   = as.character(Sys.Date() - sample(6570:12775, 1)),
      majority_age          = "",
      guardian              = NULL,
      emergency_contact     = NULL,
      competent_minor       = TRUE,
      social_media_accounts = list()
    ),
    sport              = list(id = as.integer(sport_org_id), name = org_name),
    current_enrollment = "",
    current_nomination = "",
    residence_city     = NULL,
    birth_city         = NULL,
    status             = "ACTIVE",
    confirmed_date     = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    discipline         = "",
    para_role          = "ATHLETE",
    sex_of_competition = sample(c("M", "F"), 1),
    gender             = sample(c("M", "F"), 1),
    ethnicity          = "",
    ethnicity_other    = "",
    pronouns           = sample(c("HE", "SHE", "THEY"), 1),
    pronouns_other     = "",
    disability         = "NO",
    birth_country      = "CAN",
    residence_country  = "CAN",
    education_attending   = TRUE,
    education_level       = "ATTENDING_SECONDARY",
    education_institution = "",
    education_css         = "NO",
    created_by         = 0,
    updated_by         = 0,
    updated_by_profile = 0,
    role               = 0,
    carding_level      = 0
  )
}

#' Create a dummy sport organization in the sandbox
#'
#' Registers a sport org so that sandbox reads (`fetch_org_options()`, and
#' `fetch_profiles(filters = list(sport_org_id = ...))`) behave like production.
#' The org's `name` becomes the `sport$name` of every athlete created under it
#' with [create_profile()].
#'
#' @param name Character. Name of the sport organization (e.g. "Rowing Canada").
#'   Required.
#' @param id Integer. Optional org id. If `NULL` (default) an unused id in
#'   `1:999` is generated. If supplied, it must be a positive integer in
#'   `1:999` that does not collide with an existing sandbox org.
#'
#' @return The created org (`list(id, name, annual_cycle_start)`), invisibly.
#' @seealso [create_profile()] to add athletes, [csiapps-sandbox] for an overview
#' @export
#' @examples
#' org <- create_sport_org("Rowing Canada")
#' create_profile(5, org$id)
#' clear_sandbox()
create_sport_org <- function(name, id = NULL) {
  if (!is_sandbox_mode()) {
    warning("create_sport_org: not in sandbox mode; dummy orgs are only read by sandbox helpers and have no effect in production.", call. = FALSE)
  }
  stopifnot(is.character(name), length(name) == 1, nzchar(name))
  existing <- .sandbox_org_ids()
  if (is.null(id)) {
    pool <- setdiff(1:999, existing)
    if (length(pool) == 0) stop("create_sport_org: too many sport orgs in the sandbox. Limit is 999.", call. = FALSE)
    id <- pool[sample.int(length(pool), 1)] #sample(pool, 1) - this behaves undesirably when pool is length 1
  } else {
    stopifnot(is.numeric(id), length(id) == 1, is.finite(id), id == as.integer(id), id > 0, id <= 999)
    id <- as.integer(id)
    if (id %in% existing) {
      stop(sprintf("create_sport_org: sport org id %d already exists in the sandbox.", id), call. = FALSE)
    }
  }

  org <- list(
    id                 = id,
    name               = name,
    annual_cycle_start = as.character(Sys.Date())
  )
  .sandbox_env$orgs[[as.character(id)]] <- org
  message(sprintf("csiapps sandbox: created sport org %d ('%s')", id, org$name))
  invisible(org)
}

#' Create dummy athlete profiles in the sandbox
#'
#' Generates `n` random athlete profiles and registers them under an existing
#' sandbox sport org, so sandbox `fetch_profiles()` / `fetch_profile()` return
#' prod-shaped data. The org must already exist (see [create_sport_org()]).
#'
#' @param n Integer. Number of profiles to create.
#' @param sport_org_id Integer. Id of the sport org (from [create_sport_org()])
#'   the athletes belong to. Stored as each profile's `sport$id` (the filter
#'   `fetch_profiles(filters = list(sport_org_id = ...))` uses), and its name
#'   becomes each profile's `sport$name`. The org must already exist.
#' @param first_names,last_names Character vectors of length `n` giving each
#'   athlete's first and last name. Provide both or neither. When both are `NULL`
#'   (default), `n` unique first/last pairs are drawn without replacement from
#'   the `babynames` dataset, so every athlete name is distinct.
#'
#' @return The created profiles, invisibly. Appended to any already registered.
#' @seealso [create_sport_org()], [csiapps-sandbox]
#' @export
#' @examples
#' org <- create_sport_org("Rowing Canada")
#' create_profile(2, org$id, first_names = c("Ada", "Blair"),
#'                last_names = c("Nkemelu", "Okafor"))
#' clear_sandbox()
create_profile <- function(n, sport_org_id, first_names = NULL, last_names = NULL) {
  if (!is_sandbox_mode()) {
    warning("create_profile: not in sandbox mode; dummy profiles are only read by sandbox helpers and have no effect in production.", call. = FALSE)
  }
  stopifnot(is.numeric(n), length(n) == 1, n >= 0)
  sport_org_id <- as.integer(sport_org_id)
  if (!(as.character(sport_org_id) %in% names(.sandbox_env$orgs))) {
    stop(sprintf(
      "create_profile: sport org '%s' does not exist; create it first with create_sport_org(%s).",
      sport_org_id, sport_org_id), call. = FALSE)
  }

  # Names: caller supplies both vectors, or neither and we generate unique ones.
  if (is.null(first_names) && is.null(last_names)) {
    pairs       <- .sandbox_random_names(n)
    first_names <- pairs$first
    last_names  <- pairs$last
  } else if (is.null(first_names) || is.null(last_names)) {
    stop("create_profile: provide both `first_names` and `last_names`, or neither.", call. = FALSE)
  } else {
    stopifnot(is.character(first_names), is.character(last_names),
              length(first_names) == n, length(last_names) == n)
  }

  start <- length(.sandbox_env$profiles)
  new   <- lapply(seq_len(n), function(i)
    .sandbox_make_profile(start + i, sport_org_id, first_names[i], last_names[i]))
  .sandbox_env$profiles <- c(.sandbox_env$profiles, new)
  message(sprintf("csiapps sandbox: created %d athlete(s) under sport org %d (%d total)",
                  n, sport_org_id, length(.sandbox_env$profiles)))
  invisible(new)
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
    # Resolve each record's subject at *read* time (not ingest) so athletes
    # registered with create_profile() after ingestion backfill correctly. The
    # envelope is rebuilt explicitly (dropping the internal subject_field and
    # keeping `subject` as NULL when unresolved) to match the real API shape.
    results <- lapply(records, function(rec) {
      list(
        id           = rec$id,
        dataset_uuid = rec$dataset_uuid,
        data         = rec$data,
        subject      = .sandbox_resolve_subject(rec$data, rec$subject_field),
        created_at   = rec$created_at,
        updated_at   = rec$updated_at
      )
    })
    page <- list(
      count    = length(results),
      `next`   = NULL,
      previous = NULL,
      results  = results
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
# observeEvent(user_token()) consumer server_wrapper() uses in production, so
# `/me` is loaded from the real registration API exactly as after a production
# login. It is used *only* to emulate the login: all data (orgs, athletes,
# warehouse) is served from the local sandbox, never the real API.
#
# When no token is present the app still renders, but shows an unauthenticated
# notice: a token is required to emulate the login and populate `/me`.
#
# @param user_token the reactiveVal created in server_wrapper()
# @keywords internal
.sandbox_seed_session <- function(user_token) {
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
  source_uuid   <- body$source
  records       <- body$records
  subject_field <- body$subject_field

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

  # Wrap each record in the envelope shape returned by the real data-records
  # endpoint (see flatten_record()). We store subject_field (not a resolved
  # subject) so the athlete link is resolved at read time -- this lets athletes
  # registered after ingestion backfill instead of being frozen as NULL.
  wrapped <- lapply(seq_along(records), function(i) {
    list(
      id            = n_existing + i,
      dataset_uuid  = dataset_uuid,
      data          = records[[i]],
      subject_field = subject_field,
      created_at    = now,
      updated_at    = now
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

# ---- CSI APPS/Warehouse constants ----
SPORT_ORG_ENDPOINT <- "/api/registration/organization/"
PROFILE_ENDPOINT <- "/api/registration/profile/"

# environment variables
package_state <- new.env(parent = emptyenv())
package_state$INSTITUTE <- "csipacific"
VALID_INSTITUTES <- c("csipacific", "csiontario", "csiatlantic")
SITE_URL <- function() paste0("https://apps.", package_state$INSTITUTE, ".ca")
CSIAPPS_AUTH_URL <- function() paste0(SITE_URL(), "/o/authorize/")
CSIAPPS_TOKEN_URL <- function() paste0(SITE_URL(), "/o/token/")
CSIAPPS_USERINFO_URL <- function() paste0(SITE_URL(), "/api/csiauth/me")

#' Set the target institute for API calls
#'
#' @param institute One of "csipacific", "csiontario", or "csiatlantic"
#'
#' @export
#' @examples
#' set_institute("csiontario")
set_institute <- function(institute = "csipacific") {
  stopifnot(is.character(institute), length(institute) == 1, nzchar(institute),
            institute %in% VALID_INSTITUTES)

  package_state$INSTITUTE <- institute
}

#' Function to check that required environment variables for APPS authentication are set and valid
#'
#' @param verbose logical; if TRUE, prints the current values of relevant environment variables (masking secrets) to the console
#' @param sandbox If TRUE, the OAuth secret checks are skipped (sandbox mode
#' simulates the login and needs no client credentials); instead the presence of
#' `CSIAPPS_ACCESS_TOKEN` is reported, since that determines whether real
#' registration data is available. Never errors in sandbox mode. Defaults to
#' [is_sandbox_mode()]. See [csiapps-sandbox].
#'
#' @export
check_secrets <- function(verbose = FALSE, sandbox = is_sandbox_mode()) {

  if (isTRUE(sandbox)) {
    if (nzchar(Sys.getenv("CSIAPPS_ACCESS_TOKEN"))) {
      message("csiapps sandbox: CSIAPPS_ACCESS_TOKEN found - real registration reads enabled")
    } else {
      message("csiapps sandbox: no CSIAPPS_ACCESS_TOKEN set - running unauthenticated (set a token to emulate login and load /me)")
    }
    return(invisible(TRUE))
  }

  bad <- character()
  if (!grepl("^https?://", CSIAPPS_AUTH_URL()))      bad <- c(bad, "CSIAPPS_AUTH_URL")
  if (!grepl("^https?://", CSIAPPS_TOKEN_URL()))     bad <- c(bad, "CSIAPPS_TOKEN_URL")
  if (!grepl("^https?://", Sys.getenv("CSIAPPS_REDIRECT_URI")))  bad <- c(bad, "CSIAPPS_REDIRECT_URI")
  if (length(bad) > 0) stop("Invalid or missing URL env vars: ", paste(bad, collapse = ", "))

  if (verbose) {

    message("AUTH_URL: '", CSIAPPS_AUTH_URL(), "'  REDIRECT_URI: '", Sys.getenv("CSIAPPS_REDIRECT_URI"), "'")

    env_dump <- list(
      CSIAPPS_CLIENT_ID          = Sys.getenv("CSIAPPS_CLIENT_ID"),
      CSIAPPS_CLIENT_SECRET_SET  = nzchar(Sys.getenv("CSIAPPS_CLIENT_SECRET")),
      CSIAPPS_AUTH_URL           = CSIAPPS_AUTH_URL(),
      CSIAPPS_TOKEN_URL          = CSIAPPS_TOKEN_URL(),
      CSIAPPS_REDIRECT_URI       = Sys.getenv("CSIAPPS_REDIRECT_URI"),
      CSIAPPS_SCOPE              = Sys.getenv("CSIAPPS_SCOPE", "read write"),
      CSIAPPS_USERINFO_URL       = CSIAPPS_USERINFO_URL()
    )
    message("CSIAPPS environment on startup:")
    utils::str(env_dump)
  }
}

# -------------------------------------------------------------------
# Registration API helpers
# -------------------------------------------------------------------

#' Flatten a record object into a simpler structure
#'
#' @param rec a data record object as returned by the warehouse API endpoints
#'
#' @return a list with flattened fields for easier analysis, including
#' `id`, `dataset_uuid`, `profile` (subject name), `created_at`, `updated_at`, `sport`, and `data` (original data payload)
#' @keywords internal
flatten_record <- function(rec) {
  data <- rec$data %||% list()

  record_identifier <- rec$uuid %||% rec$id
  subject           <- rec$subject
  subject_label     <- "-"
  if (!is.null(subject)) {
    fn <- subject$first_name %||% ""
    ln <- subject$last_name  %||% ""
    subject_label <- trimws(paste(fn, ln))
    if (!nzchar(subject_label)) subject_label <- "-"
  }

  list(
    id             = record_identifier,
    dataset_uuid   = rec$dataset_uuid %||% NA,
    profile        = subject_label,
    created_at     = rec$created_at %||% NA,
    updated_at     = rec$updated_at %||% NA,
    sport          = rec$subject$sport$name %||% NA,
    data           = data
  )
}

#' Fetch organisation options from the CSIAPPS registration API
#'
#' Returns all organisations accessible to the authenticated user as a list of
#' `label`/`value` pairs, suitable for use in Shiny `selectInput()` choices.
#'
#' @param token Character. Authentication token. When not supplied, it is
#'   resolved for the current Shiny session (the token stored by
#'   [server_wrapper()]) and otherwise falls back to the `CSIAPPS_ACCESS_TOKEN`
#'   environment variable.
#' @param sandbox Logical. When `TRUE` (the default in development), no network
#'   call is made and the local dummy registry is returned (the orgs registered
#'   with [create_sport_org()]). Set to `FALSE` to fetch real organisations from
#'   the API. Defaults to [is_sandbox_mode()].
#'
#' @return A list of named lists, each with `label` (organisation name) and
#'   `value` (organisation ID).
#'
#' @seealso [fetch_profiles()] to fetch profiles, [set_institute()] to
#'   configure the target institute.
#' @export
#' @examples
#' \dontrun{
#' set_institute("csiontario")
#' orgs <- fetch_org_options(sandbox = FALSE)
#' selectInput("org", "Organisation", choices = orgs)
#' }
fetch_org_options <- function(token = NULL, sandbox = is_sandbox_mode()) {
  if (isTRUE(sandbox)) {
    message("csiapps sandbox: fetch_org_options() reading local registry (see create_sport_org())")
    return(lapply(unname(.sandbox_env$orgs), function(o) list(label = o$name, value = o$id)))
  }
  if (.no_token(token)) {
    token <- .current_token()
  }
  if (!nzchar(token)) .auth_gate("fetch_org_options")

  url <- paste0(SITE_URL(), SPORT_ORG_ENDPOINT)  # "/api/registration/organization/"

  req <- httr2::request(url) |>
    httr2::req_headers(
      Authorization = paste("Bearer", token),
      Accept        = "application/json"
    ) |>
    httr2::req_url_query(limit = 1000L)

  resp   <- httr2::req_perform(req)
  status <- httr2::resp_status(resp)
  txt    <- httr2::resp_body_string(resp)

  if (status >= 400) {
    stop(sprintf("fetch_org_options failed (%s): %s", status, txt))
  }

  items <- jsonlite::fromJSON(txt, simplifyVector = FALSE)

  if (!is.null(items$results)) {
    rv <- lapply(items$results, function(item) {
      list(
        label = item$name,
        value = item$id
      )
    })
  } else if (is.list(items)) {
    rv <- lapply(items, function(val) {
      list(label = val, value = val)
    })
  } else {
    rv <- list()
  }

  rv
}

#' Fetch profiles from the CSIAPPS registration API
#'
#' Retrieves all profiles accessible to the authenticated user, with optional
#' filtering. Automatically paginates — all matching profiles are returned in a
#' single list regardless of how many pages the API uses.
#'
#' @param token Character. Authentication token. When not supplied, it is
#'   resolved for the current Shiny session (the token stored by
#'   [server_wrapper()]) and otherwise falls back to the `CSIAPPS_ACCESS_TOKEN`
#'   environment variable.
#' @param filters Named list of query parameters for filtering. Common filters
#'   include `sport_org_id` (integer, filter by organisation) and `sport`
#'   (filter by sport). See the
#'   [CSIAPPS Swagger docs](https://apps.csiontario.ca/api/swagger/) for all
#'   available parameters.
#' @param sandbox Logical. When `TRUE` (the default in development), no network
#'   call is made and profiles are read from the local dummy registry (those
#'   created with [create_profile()]); only the `sport_org_id` filter is applied,
#'   other filters are ignored. Set to `FALSE` to fetch real profiles from the
#'   API. Defaults to [is_sandbox_mode()].
#'
#' @return A list of profile objects. Each element contains a `person` sub-list
#'   (`first_name`, `last_name`, `dob`, `email`, ...), a `sport` sub-list
#'   (`id`, `name`), and top-level fields such as `status` and
#'   `current_nomination`. See the
#'   [CSIAPPS Swagger docs](https://apps.csiontario.ca/api/swagger/) for the
#'   full schema.
#'
#' @seealso [fetch_profile()] to retrieve a single profile by ID,
#'   [fetch_org_options()] to list available organisations,
#'   [set_institute()] to configure the target institute.
#' @export
#' @examples
#' \dontrun{
#' set_institute("csiontario")
#'
#' # All profiles your token can see
#' profiles <- fetch_profiles(sandbox = FALSE)
#'
#' # Profiles for a specific organisation
#' profiles <- fetch_profiles(filters = list(sport_org_id = 42L), sandbox = FALSE)
#'
#' # Build a display data frame
#' profile_df <- do.call(rbind, lapply(profiles, function(p) {
#'   data.frame(
#'     id         = p$id,
#'     first_name = p$person$first_name %||% NA_character_,
#'     last_name  = p$person$last_name  %||% NA_character_,
#'     email      = p$person$email      %||% NA_character_
#'   )
#' }))
#' }
fetch_profiles <- function(token = NULL, filters = list(), sandbox = is_sandbox_mode()) {
  if (isTRUE(sandbox)) {
    message("csiapps sandbox: fetch_profiles() reading local registry (see create_profile())")
    profs <- unname(.sandbox_env$profiles)
    sid   <- filters$sport_org_id
    if (!is.null(sid)) {
      profs <- Filter(function(p) identical(as.integer(p$sport$id), as.integer(sid)), profs)
    }
    return(profs)
  }
  if (.no_token(token)) {
    token <- .current_token()
  }
  if (!nzchar(token)) .auth_gate("fetch_profiles")

  url    <- paste0(SITE_URL(), PROFILE_ENDPOINT)  # "/api/registration/profile/"
  params <- c(filters, list(limit = 100L, offset = 0L))
  all    <- list()

  repeat {
    req <- httr2::request(url) |>
      httr2::req_headers(
        Authorization = paste("Bearer", token),
        Accept        = "application/json"
      )

    if (!is.null(params)) {
      req <- do.call(httr2::req_url_query, c(list(req), params))
    }

    resp   <- httr2::req_perform(req)
    status <- httr2::resp_status(resp)
    txt    <- httr2::resp_body_string(resp)

    if (status >= 400) {
      stop(sprintf("fetch_profiles failed (%s): %s", status, txt))
    }

    payload <- jsonlite::fromJSON(txt, simplifyVector = FALSE)
    all     <- c(all, payload$results %||% list())

    url    <- payload$`next`
    params <- NULL  # `next` already has query params
    if (is.null(url) || !nzchar(url)) break
  }

  all
}

#' Fetch a single profile from the CSIAPPS registration API
#'
#' Retrieves one profile by its ID.
#'
#' @param token Character. Authentication token. When not supplied, it is
#'   resolved for the current Shiny session (the token stored by
#'   [server_wrapper()]) and otherwise falls back to the `CSIAPPS_ACCESS_TOKEN`
#'   environment variable.
#' @param profile_id Integer or character. The ID of the profile to retrieve.
#' @param sandbox Logical. When `TRUE` (the default in development), no network
#'   call is made and the profile is looked up in the local dummy registry (those
#'   created with [create_profile()]), returning `NULL` if no such id exists. Set
#'   to `FALSE` to fetch the real profile from the API. Defaults to
#'   [is_sandbox_mode()].
#'
#' @return A single profile object as a list, or `NULL` if no profile with that
#'   id exists. The structure mirrors the list elements returned by
#'   [fetch_profiles()].
#'
#' @seealso [fetch_profiles()] to retrieve multiple profiles,
#'   [set_institute()] to configure the target institute.
#' @export
#' @examples
#' \dontrun{
#' set_institute("csiontario")
#' profile <- fetch_profile(profile_id = 123L, sandbox = FALSE)
#' profile$person$first_name
#' }
fetch_profile <- function(token = NULL, profile_id, sandbox = is_sandbox_mode()) {
  if (isTRUE(sandbox)) {
    message("csiapps sandbox: fetch_profile() reading local registry (see create_profile())")
    hit <- Filter(function(p) identical(as.integer(p$id), as.integer(profile_id)), .sandbox_env$profiles)
    return(if (length(hit)) hit[[1]] else NULL)
  }
  if (.no_token(token)) {
    token <- .current_token()
  }
  if (!nzchar(token)) .auth_gate("fetch_profile")

  # URL-encode the id so an unusual value can't alter the request path.
  enc_id <- utils::URLencode(as.character(profile_id), reserved = TRUE)
  path   <- sprintf("%s%s", PROFILE_ENDPOINT, enc_id)  # "/api/registration/profile/{id}"
  url    <- paste0(SITE_URL(), path)

  req <- httr2::request(url) |>
    httr2::req_headers(
      Authorization = paste("Bearer", token),
      Accept        = "application/json"
    )

  resp   <- httr2::req_perform(req)
  status <- httr2::resp_status(resp)
  txt    <- httr2::resp_body_string(resp)

  if (status >= 400) {
    stop(sprintf("fetch_profile failed (%s): %s", status, txt))
  }

  jsonlite::fromJSON(txt, simplifyVector = FALSE)
}

# -------------------------------------------------------------------
# PKCE helpers
# -------------------------------------------------------------------

pkce_base64url <- function(raw_bytes) {
  b64 <- openssl::base64_encode(raw_bytes)
  b64 <- gsub("+", "-", b64, fixed = TRUE)
  b64 <- gsub("/", "_", b64, fixed = TRUE)
  sub("=+$", "", b64)
}

#' Encode a PKCE code verifier into a state string for the auth request
#'
#' @param verifier a PKCE code verifier string
#' @importFrom stats runif
#' @keywords internal
#'
pkce_state_encode <- function(verifier) {
  payload <- jsonlite::toJSON(
    list(
      v = verifier,
      r = as.integer(runif(1, 1, 1e9))
    ),
    auto_unbox = TRUE
  )
  pkce_base64url(charToRaw(payload))
}

pkce_base64url_decode <- function(x) {
  x <- gsub("-", "+", x, fixed = TRUE)
  x <- gsub("_", "/", x, fixed = TRUE)
  padding <- 4 - (nchar(x) %% 4)
  if (padding < 4) x <- paste0(x, strrep("=", padding))
  openssl::base64_decode(x)
}

pkce_state_decode <- function(state) {
  raw <- pkce_base64url_decode(state)
  jsonlite::fromJSON(rawToChar(raw))
}

# -------------------------------------------------------------------
# Token exchange
# -------------------------------------------------------------------

exchange_code_for_token <- function(code, code_verifier = NULL) {
  req <- httr2::request(CSIAPPS_TOKEN_URL()) |>
    httr2::req_auth_basic(Sys.getenv("CSIAPPS_CLIENT_ID"), Sys.getenv("CSIAPPS_CLIENT_SECRET")) |>
    httr2::req_body_form(
      grant_type    = "authorization_code",
      code          = code,
      redirect_uri  = Sys.getenv("CSIAPPS_REDIRECT_URI"),
      code_verifier = code_verifier
    ) |>
    httr2::req_error(is_error = function(resp) FALSE)  # don't throw on HTTP errors

  resp     <- httr2::req_perform(req)
  status   <- httr2::resp_status(resp)
  body_txt <- httr2::resp_body_string(resp)
  body <- tryCatch(
    jsonlite::fromJSON(body_txt, simplifyVector = TRUE),
    error = function(e) list(raw = body_txt)
  )

  if (status >= 200 && status < 300) {
    body
  } else {
    list(
      error   = "token_exchange_http_error",
      status  = status,
      payload = body
    )
  }
}


#' Check whether sandbox mode is enabled globally
#'
#' Determines the default value of the `sandbox` argument of [make_request()].
#' **Sandbox mode is enabled by default**, so that requests never reach the
#' production warehouse unless it is explicitly turned off. It is disabled when
#' the `csiapps.sandbox` R option is set to `FALSE`, or, if that option is
#' unset, when the `CSIAPPS_ENV` environment variable equals `"production"`.
#' The R option, when set, always takes precedence over the environment
#' variable.
#'
#' @return logical; `TRUE` if sandbox mode is enabled globally
#' @seealso [csiapps-sandbox] for an overview of sandbox mode
#' @export
#' @examples
#' is_sandbox_mode() # TRUE by default
#'
#' options(csiapps.sandbox = FALSE) # turn sandbox off (e.g. for deployment)
#' is_sandbox_mode()
#' options(csiapps.sandbox = NULL)
is_sandbox_mode <- function() {
  opt <- getOption("csiapps.sandbox", NULL)
  if (!is.null(opt)) return(isTRUE(opt))          # explicit option always wins
  env <- Sys.getenv("CSIAPPS_ENV")
  if (nzchar(env)) return(!identical(env, "production")) # only "production" disables
  TRUE                                            # nothing set -> sandbox ON
}

# ---- Per-session token storage ------------------------------------------
#
# The access token lives in a reactiveVal kept on session$userData, so
# concurrent users never share or clobber each other's token (the reason the
# process-wide env var was retired). It is a reactiveVal rather than a plain
# value so that reading it from a reactive context registers a dependency: an
# app reactive that runs before login completes is cancelled quietly (see
# .auth_gate()) and re-runs on its own once server_wrapper() stores the token.
# Lazily created so it does not matter whether the wrapper or the app touches
# it first; userData is shared with module sessions, so modules see the same
# token.

.token_rv <- function(domain) {
  rv <- domain$userData$csiapps_token_rv
  if (is.null(rv)) {
    rv <- shiny::reactiveVal(NULL)
    domain$userData$csiapps_token_rv <- rv
  }
  rv
}

# Called by server_wrapper() on login/logout.
.set_session_token <- function(session, token) {
  .token_rv(session)(token)
}

# Legacy compatibility. Before tokens became per-session, server_wrapper()
# exported the real token as a process-wide env var, and some apps copied
# guards like req(nzchar(Sys.getenv("CSIAPPS_ACCESS_TOKEN"))) into their server
# code. Seeding the env var with this non-secret placeholder keeps those guards
# passing (real gating now happens inside make_request()/token_ready(), which
# never accept the placeholder as a credential), so legacy apps keep working
# without a code change and without a real token ever going process-global.
.TOKEN_PLACEHOLDER <- "<csiapps-token-managed-per-session>"

.seed_env_placeholder <- function() {
  if (!nzchar(Sys.getenv("CSIAPPS_ACCESS_TOKEN"))) {
    Sys.setenv(CSIAPPS_ACCESS_TOKEN = .TOKEN_PLACEHOLDER)
  }
  invisible()
}

# TRUE when a token argument/value cannot be used as a credential and must be
# resolved (or gated) instead. The placeholder is deliberately unusable so a
# legacy app passing token = Sys.getenv("CSIAPPS_ACCESS_TOKEN") explicitly
# still gets the per-session token rather than sending the placeholder.
.no_token <- function(token) {
  is.null(token) || !nzchar(token) || identical(token, .TOKEN_PLACEHOLDER)
}

# Resolve the access token for an API request. Inside a Shiny session, read the
# per-session token — reactively when a reactive context is active (so the
# caller re-runs when the token changes), quietly via isolate() otherwise
# (e.g. inside a downloadHandler). Outside a Shiny session (CLI, scripts) fall
# back to the process-wide CSIAPPS_ACCESS_TOKEN environment variable.
.current_token <- function() {
  domain <- shiny::getDefaultReactiveDomain()
  if (!is.null(domain)) {
    rv  <- .token_rv(domain)
    tok <- tryCatch(rv(), error = function(e) shiny::isolate(rv()))
    if (!.no_token(tok)) return(tok)
  }
  tok <- Sys.getenv("CSIAPPS_ACCESS_TOKEN")
  if (.no_token(tok)) "" else tok
}

# Called when a token is required but absent. Inside a Shiny session that is
# the normal pre-login state, so cancel the current computation quietly with
# req(); because .current_token() just read the token reactiveVal, the
# computation re-runs on its own when login completes. Outside Shiny a missing
# token is a configuration error, so fail loudly.
.auth_gate <- function(what) {
  if (!is.null(shiny::getDefaultReactiveDomain())) shiny::req(FALSE)
  stop(what, ": no CSIAPPS_ACCESS_TOKEN set; user not authenticated?", call. = FALSE)
}

#' Is a CSIAPPS access token available yet?
#'
#' Returns `TRUE` once an access token is available for the current context:
#' inside a Shiny app wrapped by [server_wrapper()], the per-session token
#' stored at login; outside Shiny, the `CSIAPPS_ACCESS_TOKEN` environment
#' variable.
#'
#' The check is reactive-friendly: called from a reactive expression or
#' observer it takes a dependency on the session's token, so a guard like
#' `req(token_ready())` re-fires automatically when login completes, instead of
#' silently sticking in the cancelled state. Note that [make_request()] and the
#' `fetch_*()` helpers already gate themselves this way, so an explicit guard
#' is only needed for work that should wait for login without making an API
#' call (e.g. processing an uploaded file).
#'
#' @return logical; `TRUE` if an access token is available.
#' @seealso [server_wrapper()], [make_request()]
#' @export
token_ready <- function() {
  nzchar(.current_token())
}

#' Make an authenticated API request to CSIAPPS
#'
#' @param endpoint API endpoint path.
#' @param method HTTP method. Defaults to "GET"
#' @param body Optional request body for POST/PUT/PATCH requests; should be an R object that can be serialized to JSON
#' @param query Optional list of query parameters to include in the request URL
#' @param headers Optional list of additional HTTP headers to include in the request
#' @param token Authentication token. When not provided, it is resolved for the current Shiny session (the token stored by [server_wrapper()]), falling back to the `CSIAPPS_ACCESS_TOKEN` environment variable outside a session. Inside a Shiny session a not-yet-available token does not error: the request is cancelled quietly with [shiny::req()], and the calling reactive or observer re-runs automatically once login completes (see [token_ready()]). Outside Shiny a missing token raises an error.
#' @param timeout Request timeout in seconds; defaults to 20
#' @param verbose If TRUE, prints request and response details to the console for debugging purposes
#' @param paginate If TRUE, will attempt to paginate through results using "next" links in the API response. Defaults to FALSE.
#' @param max_pages Maximum number of pages to fetch when paginate = TRUE; defaults to 50 to prevent infinite loops
#' @param sandbox If TRUE, the request is routed to the local sandbox instead of
#' the real REST API: no network call is made and no authentication is required.
#' Only the **warehouse** endpoints are emulated; registration and auth endpoints
#' (e.g. `api/registration/...`, `api/csiauth/me/`) are not, and raise a 501 in
#' sandbox unless `sandbox = FALSE` (for registration reads, use
#' [fetch_org_options()] / [fetch_profiles()] instead). Defaults to
#' [is_sandbox_mode()], which is **TRUE by default**. Disable sandbox mode
#' globally with `options(csiapps.sandbox = FALSE)` (or `CSIAPPS_ENV=production`)
#' to route requests to the production warehouse. See [csiapps-sandbox] for
#' supported endpoints and limitations. In sandbox mode the HTTP-only arguments
#' (`headers`, `token`, `timeout`, `max_pages`) are ignored, since no network
#' request is made.
#'
#' @return List of parsed API responses
#' @export
make_request <- function(
    endpoint,
    method = "GET",
    body = NULL,
    query = list(),
    headers = list(),
    token = NULL,
    timeout = 20L,
    verbose = FALSE,
    paginate = FALSE,
    max_pages = 50,
    sandbox = is_sandbox_mode()
  ) {
  if (isTRUE(sandbox)) {
    return(.make_sandbox_request(
      endpoint = endpoint,
      method   = method,
      body     = body,
      query    = query,
      verbose  = verbose,
      paginate = paginate
    ))
  }

  # Resolve the token per Shiny session (see .current_token()); the process-wide
  # env var is only the fallback for non-Shiny use, so concurrent app users never
  # share a token.
  if (.no_token(token)) token <- .current_token()

  .make_http_request(
    endpoint  = endpoint,
    method    = method,
    body      = body,
    query     = query,
    headers   = headers,
    token     = token,
    timeout   = timeout,
    verbose   = verbose,
    paginate  = paginate,
    max_pages = max_pages
  )
}

.make_http_request <- function(
    endpoint,
    method = "GET",
    body = NULL,
    query = list(),
    headers = list(),
    token = NULL,
    timeout = 20L,
    verbose = FALSE,
    paginate = FALSE,
    max_pages = 50
  ) {
  if (.no_token(token)) .auth_gate("make_request")

  req <- httr2::request(SITE_URL()) |>
    httr2::req_url_path_append(endpoint) |>
    httr2::req_method(toupper(method)) |>
    httr2::req_auth_bearer_token(token) |>
    httr2::req_timeout(timeout) |>
    httr2::req_retry(max_tries = 3, max_seconds = 10) # might want to play with this

  if (!is.null(body)) req <- req |> httr2::req_body_json(body)
  if (length(query) > 0) req <- req |> httr2::req_url_query(!!!query)
  if (length(headers) > 0) req <- req |> httr2::req_headers(!!!headers)

  parse_response <- function(resp) {
    status <- httr2::resp_status(resp)
    txt    <- httr2::resp_body_string(resp)

    if(length(txt) == 0) {
      return(list())
    }

    if(verbose) {
      message(method, " request to ", endpoint, " returned status ", status)
      if (!is.null(query)) message("  params:", paste(names(query), query, collapse = ", "), "\n")
      cat("  response:\n", txt, "\n")
    }

    if (status >= 400) {
      stop(sprintf("API request failed (%s): %s", status, txt))
    }

    tryCatch(
      jsonlite::fromJSON(txt, simplifyVector = FALSE),
      error = function(e) list(raw = txt, error = "json_parse_error", message = e$message)
    )
  }

  if(paginate) {

    next_by_link <- function(resp, req) {
      next_url <- httr2::resp_body_json(resp, simplifyVector = FALSE)$`next`
      if (is.null(next_url)) return(NULL)
      req |> httr2::req_url(next_url)
    }

    resps <- req |> httr2::req_perform_iterative(
      next_req = next_by_link,
      max_reqs = max_pages,
      progress = FALSE
    )

    return(lapply(resps, parse_response))

  } else{
    return(parse_response(httr2::req_perform(req)))
  }
}

#' Fetch the current AMS athlete mapping
#'
#' Fetches an AMS mapping data source and returns only its current four-column
#' mapping. In sandbox mode, the source is expected to contain the already-current
#' mapping and its four data fields are returned directly. In production, the
#' append-only warehouse history is reduced to the most recent record for each
#' mapping identity, and identities whose latest record is inactive are removed.
#'
#' @param source_uuid Character. AMS mapping data-source identifier. Defaults to
#'   the `AMS_MAPPING_UUID` environment variable.
#' @param token Character. Authentication token. When not supplied, it is
#'   resolved in the same way as [make_request()]. Ignored in sandbox mode.
#' @param sandbox Logical. Route to the local sandbox (`TRUE`) or production
#'   (`FALSE`). Defaults to [is_sandbox_mode()].
#' @param max_pages Maximum number of production response pages to fetch.
#'
#' @return A data frame with columns `id`, `vendor`, `vendor_profile_id`, and
#'   `vendor_profile_name`, containing one row per current mapping.
#' @export
#' @examples
#' \dontrun{
#' mapping <- fetch_ams_mapping()
#' }
fetch_ams_mapping <- function(
    source_uuid = Sys.getenv("AMS_MAPPING_UUID"),
    token = NULL,
    sandbox = is_sandbox_mode(),
    max_pages = 50
  ) {
  if (!is.character(source_uuid) || length(source_uuid) != 1 || !nzchar(trimws(source_uuid))) {
    stop("fetch_ams_mapping: pass `source_uuid` or set AMS_MAPPING_UUID.", call. = FALSE)
  }
  source_uuid <- trimws(source_uuid)

  out_cols <- c("id", "vendor", "vendor_profile_id", "vendor_profile_name")
  empty <- data.frame(
    id = character(),
    vendor = character(),
    vendor_profile_id = character(),
    vendor_profile_name = character(),
    stringsAsFactors = FALSE
  )
  pages <- make_request(
    endpoint = "api/warehouse/data-records",
    query = list(source_uuid = source_uuid),
    token = token,
    paginate = TRUE,
    max_pages = max_pages,
    sandbox = sandbox
  )
  records <- unlist(lapply(pages, function(page) page$results %||% list()),
                    recursive = FALSE, use.names = FALSE)
  if (!length(records)) return(empty)

  rows <- lapply(seq_along(records), function(i) {
    rec <- records[[i]]
    data <- rec$data
    missing <- out_cols[vapply(out_cols, function(col) {
      !is.list(data) || is.null(data[[col]]) || length(data[[col]]) != 1
    }, logical(1))]
    if (length(missing)) {
      stop(sprintf("fetch_ams_mapping: record %d is missing core field(s): %s.",
                   i, paste(missing, collapse = ", ")), call. = FALSE)
    }

    row <- data.frame(
      id = data$id,
      vendor = as.character(data$vendor),
      vendor_profile_id = as.character(data$vendor_profile_id),
      vendor_profile_name = as.character(data$vendor_profile_name),
      stringsAsFactors = FALSE
    )
    if (!isTRUE(sandbox)) {
      active <- data$active
      if (is.null(active) || !length(active) || is.na(active[[1]])) {
        active <- TRUE
      } else if (is.logical(active)) {
        active <- isTRUE(active[[1]])
      } else {
        value <- toupper(trimws(as.character(active[[1]])))
        active <- !value %in% c("FALSE", "F", "0", "NO", "N")
      }
      row$.active <- active
      row$.updated_at <- as.character(rec$updated_at %||% "")
      row$.record_id <- as.character(rec$id %||% "")
      row$.position <- i
    }
    row
  })
  mapping <- do.call(rbind, rows)
  rownames(mapping) <- NULL

  if (isTRUE(sandbox)) return(mapping[, out_cols, drop = FALSE])

  numeric_id <- suppressWarnings(as.numeric(mapping$.record_id))
  numeric_id[is.na(numeric_id)] <- -Inf
  mapping <- mapping[order(mapping$.updated_at, numeric_id, mapping$.record_id,
                           mapping$.position, na.last = TRUE), , drop = FALSE]
  latest <- !duplicated(mapping[, out_cols, drop = FALSE], fromLast = TRUE)
  mapping <- mapping[latest & mapping$.active, out_cols, drop = FALSE]
  rownames(mapping) <- NULL
  mapping
}

`%||%` <- function(a, b) if (!is.null(a)) a else b

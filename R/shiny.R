
#' Wrap Global code for Shiny apps
#'
#' Allows for global variable assignment and function definitions to be accessible by the server function.
#'
#' @param code A block of R code
#'
#' @return The result of evaluating the code block in the Global Environment
#' @export
global_wrapper <- function(code) {
  # Capture the code block passed in (...)
  expr <- substitute(code)

  # Evaluate it specifically in the Global Environment
  eval(expr, envir = .GlobalEnv)
}


#' Wrapper UI for Shiny apps
#'
#' Provides a consistent navbar and footer, and handles authentication redirects.
#'
#' @param ... Additional UI elements to include in the main content area
#' @param sandbox If TRUE, a "sandbox mode" banner is shown so it is obvious the
#' app is not connected to the live warehouse. Defaults to [is_sandbox_mode()].
#' See [csiapps-sandbox].
#'
#' @return A Shiny UI object with a navbar, footer, and main content area
#' @export
ui_wrapper <- function(..., sandbox = is_sandbox_mode()) {
  sandbox_banner <- if (isTRUE(sandbox)) {
    tags$div(
      class = "text-center border-bottom",
      style = "background:#faf6ec;color:#8a6d3b;font-size:12px;padding:3px 0;letter-spacing:.02em;",
      # HTML entity (not a literal em-dash) so it renders correctly regardless
      # of the served page's charset.
      HTML("Sandbox mode &mdash; not connected to the live warehouse")
    )
  }

  tagList(
    tags$head(
      tags$script(HTML(
        "
      Shiny.addCustomMessageHandler('csip_redirect', function(url) {
        if (url && typeof url === 'string') {
          window.top.location.href = url;
        }
      });
      "
      )),
      tags$link(rel=" shortcut icon", href="https://csiontario.ca/wp-content/uploads/2022/04/cropped-CSIO-Favicon-192x192.png"),
      csi_chrome_styles()
    ),
    navbar_ui(),
    sandbox_banner,
    fluidPage(
      shinyjs::useShinyjs(),
      style = "padding-bottom: 80px;",
      uiOutput("auth_status"),   # Signed in as X Y + Logout or redirect text
      # Application
      ...
    ),
    footer_ui()
  )
}

#' Wrapper server function for Shiny apps
#'
#' Handles OAuth2 PKCE authentication flow with CSIAPPS, managing user tokens and info, and providing a consistent authentication status UI.
#'
#' @param app_specific_logic Existing server logic of shiny web application
#' @param sandbox If TRUE, the real OAuth2 redirect is skipped and the session is
#' seeded from the developer's existing `CSIAPPS_ACCESS_TOKEN`, so a wrapped app
#' can be run locally without client credentials. If no token is set, the app
#' shell renders with an unauthenticated notice. Defaults to [is_sandbox_mode()],
#' which is **TRUE by default**. Disable it for deployment with
#' `options(csiapps.sandbox = FALSE)` (or `CSIAPPS_ENV=production`) to use the
#' real login flow. See [csiapps-sandbox] for details and limitations.
#'
#' @return A Shiny server function that wraps the provided app-specific logic with authentication handling and user info retrieval.
#' @export
server_wrapper <- function(app_specific_logic, sandbox = is_sandbox_mode()) {

  function(input, output, session) {

    user_token <- reactiveVal(NULL)
    userinfo   <- reactiveVal(NULL)

    # org / profile state
    org_options_rv      <- reactiveVal(NULL)

    if (isTRUE(sandbox)) {

      # ---------------- Sandbox: simulate the redirect ----------------
      # Skip the OAuth handshake entirely and seed the token from the
      # environment; the shared observeEvent() below consumes it exactly
      # as it would a token obtained from a real login.
      .sandbox_seed_session(user_token, userinfo)

    } else {

      # ---------------- CSI OAuth2 PKCE flow ----------------

      observe({
        query <- parseQueryString(session$clientData$url_search)
        code  <- query$code
        state <- query$state
        err   <- query$error
        err_desc <- query$error_description

        #message("DEBUG query: ", session$clientData$url_search)

        if (!is.null(err)) {
          #message("AUTH ERROR from provider: ", err, " - ", err_desc)
          user_token(list(error = err, error_description = err_desc))
          Sys.unsetenv("CSIAPPS_ACCESS_TOKEN")
          shinyjs::runjs("window.location.href = window.location.pathname;") # good enough fix
          #return()
        }

        # 1) No code + no token -> redirect to CSI
        if (is.null(code) && is.null(user_token())) {
          pk <- httr2::oauth_flow_auth_code_pkce()
          st <- pkce_state_encode(pk$verifier)

          csi_client <- httr2::oauth_client(
            id        = Sys.getenv("CSIAPPS_CLIENT_ID"),
            token_url = CSIAPPS_TOKEN_URL(),
            secret    = Sys.getenv("CSIAPPS_CLIENT_SECRET")
          )

          auth_url <- httr2::oauth_flow_auth_code_url(
            client       = csi_client,
            auth_url     = CSIAPPS_AUTH_URL(),
            redirect_uri = Sys.getenv("CSIAPPS_REDIRECT_URI"),
            scope        = Sys.getenv("CSIAPPS_SCOPE", "read write"),
            auth_params  = list(
              code_challenge        = pk$challenge,
              code_challenge_method = pk$method,
              state                 = st
            )
          )

          #message("DEBUG login_url: ", auth_url)
          session$sendCustomMessage("csip_redirect", auth_url) # not sure what this does
          return()
        }

        # 2) Have code but no token yet -> exchange
        if (!is.null(code) && is.null(user_token())) {
          verifier <- NULL
          if (!is.null(state)) {
            decoded <- pkce_state_decode(state)
            verifier <- decoded$v
          }
          token <- exchange_code_for_token(code, code_verifier = verifier)
          #message("DEBUG token payload:"); utils::str(token)
          #print(token)
          user_token(token)
        }
      })

    }

    # Load /me and update global access token when we get a token.
    # Shared by the production and sandbox paths: in sandbox the token is the
    # developer's own, so `/me` and org loading hit the real registration API.
    observeEvent(user_token(), {
      tok <- user_token()

      # Clear any old token
      Sys.unsetenv("CSIAPPS_ACCESS_TOKEN")

      # Bail if token exchange failed
      if (is.null(tok) || !is.null(tok$error)) {
        #return()
        shinyjs::runjs("window.location.href = window.location.pathname;") # good enough fix
      }

      access_token <- tok$access_token

      if (is.null(access_token) || !nzchar(access_token)) return()

      # 1) Make token available globally (Warehouse + helpers)
      Sys.setenv(CSIAPPS_ACCESS_TOKEN = access_token)

      # 2) Load /me for first_name / last_name (for header). Guarded so an
      #    expired or rejected token degrades gracefully instead of crashing
      #    the session (e.g. a stale local token in sandbox mode).
      if (!is.null(CSIAPPS_USERINFO_URL()) && nzchar(CSIAPPS_USERINFO_URL())) {
        ui_me <- tryCatch({
          req <- httr2::request(CSIAPPS_USERINFO_URL()) |>
            httr2::req_auth_bearer_token(access_token)
          resp <- httr2::req_perform(req)
          httr2::resp_body_json(resp, simplifyVector = TRUE)
        }, error = function(e) {
          showNotification(
            paste("Error loading user info:", conditionMessage(e)),
            type = "error"
          )
          NULL
        })
        if (!is.null(ui_me)) userinfo(ui_me)
      }

      # 3) Load organization list *here* (no separate observer)
      org_opts <- tryCatch(
        fetch_org_options(access_token),  # pass explicit token, no race
        error = function(e) {
          showNotification(
            paste("Error loading organizations:", conditionMessage(e)),
            type = "error"
          )
          NULL
        }
      )
      org_options_rv(org_opts)

    })

    # Auth status UI: first/last name + logout
    output$auth_status <- renderUI({
      tok <- user_token()

      if (is.null(tok)) {
        return(tags$p("Redirecting to CSIAPPS for authentication..."))
      }

      if (!is.null(tok$error)) {
        return(tagList(
          tags$p("Authentication error (see logs).")
        ))
      }

      if (isTRUE(tok$unauthenticated)) {
        return(tags$p(HTML("Not authenticated &mdash; set CSIAPPS_ACCESS_TOKEN to use sandbox mode with real data.")))
      }

      ui_me <- userinfo()
      name_text <- if (!is.null(ui_me$first_name) && !is.null(ui_me$last_name)) {
        sprintf("Signed in as %s %s", ui_me$first_name, ui_me$last_name)
      } else {
        "Signed in"
      }
      if (isTRUE(sandbox)) name_text <- paste0(name_text, " (sandbox)")

      tagList(
        #br(),
        br(),
        tags$p(name_text)
        #actionButton("logout", "Log out")
      )
    })

    observeEvent(input$logout, {
      userinfo(NULL)
      Sys.unsetenv("CSIAPPS_ACCESS_TOKEN")
      if (isTRUE(sandbox)) {
        # No IdP to redirect to; re-seed the simulated session instead
        .sandbox_seed_session(user_token, userinfo)
      } else {
        user_token(NULL)
        #session$reload()
        shinyjs::runjs("window.location.href = window.location.pathname;") # good enough fix
      }
    })

    eval(body(app_specific_logic), envir = environment())

  }
}

# -------------------------------------------------------------------
# Navbar, footer, profile card, tabs
# -------------------------------------------------------------------

# Scoped, high-specificity styles that pin the CSI navbar/footer appearance so
# it does not depend on the wrapped app's Bootstrap theme or CSS. Targeted by id
# and marked `!important` so an app that sets `bs_theme()` or injects CSS cannot
# override the brand background, text colour, or stacking. Injected into
# `ui_wrapper()`'s <head>.
csi_chrome_styles <- function() {
  # Chrome appearance. The default "neutral frame" keeps the bar on a white
  # surface so it complements any app palette and the CSI logo sits on its
  # native background; a thin CSI-red accent line carries the brand, and a soft
  # shadow + hairline separate the chrome from any app colour. Flip `theme` to
  # "dark" for the older dark-slab look (which adds a white plate behind the
  # logo for contrast). Everything is scoped by id and marked `!important` so a
  # wrapped app's theme/CSS cannot override it.
  theme  <- "neutral"
  accent <- "#d81f26"  # CSI red

  if (identical(theme, "dark")) {
    bar_bg        <- "#212529"
    bar_text      <- "#ffffff"
    navbar_shadow <- ""
    logo_plate    <- "
    #csi-navbar .navbar-brand img {
      background: #ffffff; padding: 4px 8px; border-radius: 6px;
    }"
    footer_border <- sprintf("border-top: 3px solid %s !important;", accent)
  } else {
    bar_bg        <- "#ffffff"
    bar_text      <- "#1f2937"
    navbar_shadow <- "box-shadow: 0 2px 4px rgba(0,0,0,.06), 0 1px 2px rgba(0,0,0,.04);"
    logo_plate    <- ""
    footer_border <- "border-top: 1px solid #e6e6e6 !important;"
  }

  tags$style(HTML(sprintf(
    "
    #csi-navbar {
      background-color: %1$s !important;
      border-bottom: 3px solid %3$s !important;  /* CSI-red brand accent */
      %4$s
      position: sticky;
      top: 0;
      z-index: 1030;
    }
    #csi-navbar .navbar-brand,
    #csi-navbar .navbar-brand:hover,
    #csi-navbar .navbar-nav .nav-link {
      color: %2$s !important;
    }
    %5$s
    #footer {
      background-color: %1$s !important;
      color: %2$s !important;
      %6$s
      z-index: 1030;
    }
    #footer p, #footer a { color: %2$s !important; }
    ",
    bar_bg, bar_text, accent, navbar_shadow, logo_plate, footer_border
  )))
}

navbar_ui <- function() {
  tags$nav(
    id = "csi-navbar",
    # Fallback classes for the default neutral theme; csi_chrome_styles() is the
    # authority (overrides via id + !important regardless of these).
    class = "navbar navbar-expand-lg navbar-light bg-white px-3",
    tags$div(
      class = "container-fluid",
      tags$a(
        class = "navbar-brand d-flex align-items-center",
        href = "#",
        tags$img(
          src = ifelse(
            package_state$INSTITUTE == "csipacific",
            "https://www.csipacific.ca/wp-content/uploads/2024/05/csi-pacific-logo-main.png",
            "https://csiontario.ca/wp-content/uploads/2022/03/logo-csi-ontario.png"
          ),
          height = "48px",
          style = "margin-right: 8px;"
        ),
        #tags$span(class = "h5 mb-0", "CSIP Apps")
      )
    )
  )
}

footer_ui <- function() {
  tags$footer(
    id = "footer",
    class = "mt-4 bg-dark text-white border-top border-light fixed-bottom",
    tags$div(
      class = "d-flex flex-wrap justify-content-between align-items-center py-3 container",
      tags$p(HTML(paste0("&copy; ", format(Sys.Date(), "%Y"), " ",
                   ifelse(package_state$INSTITUTE == "csipacific", "CSI Pacific", "CSI Ontario")
                   )), class = "col-md-4 mb-0"),
      tags$ul(class = "nav col-md-4 justify-content-end")
    )
  )
}


profile_card_server <- function(id, selected_profile_info) {
  moduleServer(id, function(input, output, session) {
    output$card <- renderUI({
      info <- selected_profile_info()
      if (is.null(info)) {
        return(div(class = "card shadow-sm border-0 p-3", "No profile selected."))
      }
      initials <- profile_initials(info$name)

      div(
        class = "card shadow-sm border-0",
        style = "max-width: 560px;",
        div(
          class = "row g-0 align-items-center",
          div(
            class = "col-auto p-3",
            div(
              initials,
              class = "d-flex align-items-center justify-content-center fw-semibold",
              style = paste(
                "width:64px;height:64px;border-radius:50%;",
                "background:#0d6efd;color:white;font-size:1.1rem;letter-spacing:0.02em;"
              )
            )
          ),
          div(
            class = "col ps-0",
            div(
              class = "card-body py-3",
              div(
                class = "d-flex flex-column flex-sm-row align-items-start align-items-sm-center gap-2",
                h5(class = "mb-1", info$name),
                span(class = "badge bg-secondary ms-0 ms-sm-2", info$role)
              ),
              div(
                class = "text-muted mt-1 d-flex align-items-center",
                tags$i(class = "bi bi-building me-2"),
                span(info$organization)
              )
            )
          )
        )
      )
    })
  })
}

profile_card_ui <- function(id) {
  ns <- NS(id)
  uiOutput(ns("card"))
}

profile_initials <- function(name) {
  parts <- strsplit(name %||% "", "\\s+")[[1]]
  parts <- parts[nzchar(parts)]
  if (length(parts) == 0) return("?")
  paste0(toupper(substr(parts, 1, 1)))[1:min(2, length(parts))] |>
    paste(collapse = "")
}

profile_extract_card_info <- function(p) {
  person <- p$person %||% list()
  first  <- person$first_name %||% ""
  last   <- person$last_name  %||% ""
  name   <- trimws(paste(first, last))
  if (!nzchar(name)) name <- "-"

  role <- "-"
  if (!is.null(p$current_nomination) &&
      !is.null(p$current_nomination$role) &&
      !is.null(p$current_nomination$role$verbose_name)) {
    role <- p$current_nomination$role$verbose_name
  }

  org <- "-"
  if (!is.null(p$current_nomination) &&
      !is.null(p$current_nomination$organization) &&
      !is.null(p$current_nomination$organization$name)) {
    org <- p$current_nomination$organization$name
  }

  list(
    name = name,
    role = role,
    organization = org
  )
}

profile_build_label <- function(p) {
  person <- p$person %||% list()
  first  <- person$first_name %||% ""
  last   <- person$last_name  %||% ""
  label  <- trimws(paste(first, last))
  if (!nzchar(label)) label <- paste("Profile", p$id %||% "")
  label
}

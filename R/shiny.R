
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
      class = "text-center small py-1 bg-warning-subtle text-dark border-bottom",
      style = "background:#fff3cd;",
      "SANDBOX MODE — not connected to the live warehouse"
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
      tags$link(rel=" shortcut icon", href="https://csiontario.ca/wp-content/uploads/2022/04/cropped-CSIO-Favicon-192x192.png")
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

    if (isTRUE(sandbox)) {

      # ---------------- Sandbox: simulate the redirect ----------------
      # Skip the OAuth handshake entirely and seed the token from the
      # environment; the shared observeEvent() below consumes it exactly
      # as it would a token obtained from a real login.
      .sandbox_seed_session(user_token)

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
    # developer's own and is used only to load the real `/me` identity; all
    # other data (orgs, athletes, warehouse) is served from the local sandbox.
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
        return(tags$p("Not authenticated — set CSIAPPS_ACCESS_TOKEN to emulate login in sandbox mode."))
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
        .sandbox_seed_session(user_token)
      } else {
        user_token(NULL)
        #session$reload()
        shinyjs::runjs("window.location.href = window.location.pathname;") # good enough fix
      }
    })

    # Call the app's server function normally so it keeps its own lexical
    # environment. Re-evaluating body() in the wrapper env severed the closure,
    # so helpers/values the server fn captured from its defining scope became
    # unreachable ("could not find ...") from inside its observers.
    app_specific_logic(input, output, session)

  }
}

# -------------------------------------------------------------------
# Navbar, footer, profile card, tabs
# -------------------------------------------------------------------

navbar_ui <- function() {
  tags$nav(
    class = "navbar navbar-expand-lg navbar-dark bg-dark px-3",
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
          height = "80px",
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
      tags$p(paste("\u00A9", format(Sys.Date(), "%Y"),
                   ifelse(package_state$INSTITUTE == "csipacific", "CSI Pacific", "CSI Ontario")
                   ), class = "col-md-4 mb-0"),
      tags$ul(class = "nav col-md-4 justify-content-end")
    )
  )
}

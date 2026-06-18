# ============================================================
# EXPORT TO STATSYNC FORMAT
# ============================================================


#' Quick export from RMarkdown chunk
#'
#' Designed to be called within an RMarkdown document. Automatically
#' collects all statsync objects in the environment and exports.
#'
#' @param envir Environment to search for statsync objects
#' @param file Output file
#' @export
sync_export_all <- function(envir = parent.frame(), file = NULL) {
  # Find all statsync objects
  obj_names <- ls(envir)
  collections <- list()
  tables <- list()
  
  for (nm in obj_names) {
    obj <- get(nm, envir = envir)
    if (inherits(obj, "statsync_collection")) {
      collections <- c(collections, list(obj))
    } else if (inherits(obj, "statsync_table")) {
      tables <- c(tables, list(obj))
    }
  }
  
  if (length(collections) == 0 && length(tables) == 0) {
    message("No statsync objects found in environment.")
    return(invisible(NULL))
  }
  
  do.call(sync_export, c(collections, tables, list(file = file)))
}

#' Start a local server for live sync with Word
#'
#' Launches a tiny HTTP server that the Word add-in can poll for updates.
#' Useful during interactive analysis.
#'
#' @param ... Raw statistical models or statsync objects
#' @param port Port number (default: 8877)
#' @param project_name Name for the project shown in the Word add-in sidebar
#'   (default: "StatSync Project")
#' @param open_browser Open browser to debug panel
#' @return Invisible server object. Also creates \code{sync_export()} and
#'   \code{sync_stop()} functions in the global environment.
#' @details
#' After calling \code{sync_serve()}, use \code{sync_export()} to push new
#' data to the server, and \code{sync_stop()} to stop the server.
#'
#' @examples
#' \dontrun{
#' model1 <- lm(mpg ~ wt + hp, data = mtcars)
#'
#' sync_serve(
#'   sync_stats(model1, label = "MPG Model"),
#'   project_name = "My Thesis Analysis"
#' )
#'
#' # Later, after re-fitting the model:
#' model2 <- lm(mpg ~ wt, data = mtcars)
#' sync_export(sync_stats(model2, label = "MPG Model"))
#' }
#' @export
sync_serve <- function(project_name = "StatSync Project", ..., port = 8877,
                       open_browser = FALSE, daemon = TRUE) {
  if (!requireNamespace("httpuv", quietly = TRUE)) {
    stop("Install httpuv: install.packages('httpuv')")
  }

  # Run silent self-diagnostics on startup
  tryCatch({
    suppressWarnings({
      # Test 1: T-test format
      t_res <- stats::t.test(1:10, y = 7:20, var.equal = TRUE)
      t_stats <- sync_stats(t_res)
      t_formatted <- t_stats$stats[[1]]$formatted
      if (!grepl("t\\{/i\\}\\(", t_formatted) || !grepl("d\\{/i\\} = ", t_formatted)) {
        warning("StatSync self-diagnostics: T-test formatting verification failed.")
      }
      
      # Test 2: Chi-square format
      chi_res <- stats::chisq.test(matrix(c(10, 20, 30, 40), nrow = 2))
      chi_stats <- sync_stats(chi_res)
      chi_formatted <- chi_stats$stats[[1]]$formatted
      if (!grepl("\u03C7\u00B2\\(", chi_formatted) || !grepl("N\\{/i\\} = 100", chi_formatted)) {
        warning("StatSync self-diagnostics: Chi-square formatting verification failed.")
      }
    })
  }, error = function(e) {
    warning("StatSync self-diagnostics encountered an error during startup: ", e$message)
  })
  
  proj_val <- tryCatch(force(project_name), error = function(e) NULL)
  
  if (is.character(proj_val) && length(proj_val) == 1) {
    actual_proj <- proj_val
    if (...length() > 0) {
      sync_export(...)
    }
  } else {
    actual_proj <- "StatSync Project"
    cl <- match.call(expand.dots = FALSE)
    export_call <- as.call(c(quote(sync_export), list(cl[[2]]), cl$...))
    eval(export_call, envir = parent.frame())
  }
  
  if (!identical(.statsync_state$project_name, actual_proj) || is.null(.statsync_state$data)) {
    sync_switch(actual_proj)
  }
  
  app <- list(
    call = function(req) {
      path <- req$PATH_INFO
      cors_headers <- list(
        "Access-Control-Allow-Origin" = "*",
        "Access-Control-Allow-Methods" = "GET, OPTIONS",
        "Access-Control-Allow-Headers" = "Content-Type",
        "Content-Type" = "application/json"
      )
      
      if (req$REQUEST_METHOD == "OPTIONS") {
        return(list(status = 200L, headers = cors_headers, body = ""))
      }
      
      if (path == "/stats" || path == "/") {
        response_data <- if (!is.null(.statsync_state$data)) .statsync_state$data else list(statistics = list(), tables = list())
        if (!is.null(.statsync_state$destroyed_projects) && length(.statsync_state$destroyed_projects) > 0) {
          response_data$destroyed_projects <- .statsync_state$destroyed_projects
        }
        body <- jsonlite::toJSON(response_data, auto_unbox = TRUE)
        return(list(status = 200L, headers = cors_headers, body = body))
      }
      
      if (path == "/status") {
        body <- jsonlite::toJSON(list(
          active = TRUE,
          last_update = format(.statsync_state$last_update),
          n_stats = if (!is.null(.statsync_state$data)) length(.statsync_state$data$statistics) else 0
        ), auto_unbox = TRUE)
        return(list(status = 200L, headers = cors_headers, body = body))
      }
      
      list(status = 404L, headers = cors_headers, body = '{"error": "Not found"}')
    }
  )
  
  if (!is.null(.statsync_state$server)) {
    httpuv::stopServer(.statsync_state$server)
    .statsync_state$server <- NULL
  }
  
  .statsync_state$server <- tryCatch({
    httpuv::startServer("127.0.0.1", port, app)
  }, error = function(e) {
    if (grepl("already in use", e$message) || grepl("Failed to create server", e$message)) {
      stop(sprintf("\n\n\u274c ERROR: Port %d is already in use by another StatSync server (or a background R session).\n\n1. Run `sync_stop()` to shut down the server in this session.\n2. If that fails, an old invisible R session crashed while holding the port. Run `sync_free_port()` to forcibly kill the orphaned process, or simply restart R.\n", port), call. = FALSE)
    } else {
      stop(e$message, call. = FALSE)
    }
  })
  
  message(sprintf(
    "\u2714 StatSync server running at http://localhost:%d\n  Project: %s\n  Use sync_export() to append/update new models.\n  Use sync_delete(\"model_name\") to remove models.\n  Use sync_stop() to stop the server.", port, actual_proj
  ))
  
  if (!daemon) {
    while(TRUE) {
      httpuv::service()
      Sys.sleep(0.01)
    }
  }
  
  invisible(.statsync_state$server)
}

#' Check StatSync server status
#'
#' Reports whether the StatSync server is currently running and
#' which project is active.
#'
#' @return A list with `status` ("online" or "offline") and `project` name.
#' @export
sync_check <- function() {
  status <- if (!is.null(.statsync_state$server)) "online" else "offline"
  proj <- .statsync_state$project_name %||% "None"
  
  message(sprintf("StatSync Server is %s.\nCurrent project: %s", toupper(status), proj))
  
  invisible(list(status = status, project = proj))
}

#' Switch active StatSync project
#'
#' Switches the current active project, automatically loading any previously
#' saved data for the new project from disk.
#'
#' @param project_name The name of the project to switch to
#' @return Invisible project name
#' @export
sync_switch <- function(project_name) {
  if (missing(project_name) || !is.character(project_name) || length(project_name) != 1) {
    stop("Please provide a valid project_name string.")
  }
  
  # Save current state before switching
  save_state_to_disk()
  
  .statsync_state$project_name <- project_name
  
  safe_name <- gsub("[^a-zA-Z0-9]", "_", project_name)
  file_path <- file.path(".statsync", paste0(safe_name, ".statsync.json"))
  
  if (file.exists(file_path)) {
    tryCatch({
      .statsync_state$data <- jsonlite::fromJSON(file_path, simplifyVector = TRUE, simplifyDataFrame = FALSE, simplifyMatrix = FALSE)
      message("\u2714 Switched to project: ", project_name, "\n  Resumed data from disk.")
    }, error = function(e) {
      warning("Failed to load project from disk: ", e$message)
      .statsync_state$data <- NULL
    })
  } else {
    .statsync_state$data <- NULL
  }
  
  if (is.null(.statsync_state$data)) {
    .statsync_state$data <- list(
      project = list(name = project_name),
      statistics = vector("list", 0),
      tables = vector("list", 0),
      generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
    )
    message("\u2714 Switched to new project: ", project_name)
  }
  
  save_state_to_disk()
  invisible(project_name)
}

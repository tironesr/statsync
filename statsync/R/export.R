# ============================================================
# EXPORT TO STATSYNC FORMAT
# ============================================================

#' Export statistics to a .statsync JSON file
#'
#' @param ... statsync_collection and/or statsync_table objects
#' @param file Output file path (default: auto-named in project dir)
#' @param project_name Name for the project
#' @param style Formatting style
#' @param overwrite Overwrite existing file
#' @return Invisible file path
#' @export
#' @examples
#' \dontrun{
#' model1 <- lm(mpg ~ wt + hp, data = mtcars)
#' ttest1 <- t.test(mpg ~ am, data = mtcars)
#'
#' sync_export(
#'   sync_stats(model1, id_prefix = "model1", label = "MPG Model"),
#'   sync_stats(ttest1, id_prefix = "ttest_am", label = "MPG by Transmission"),
#'   sync_regression_table(`Full Model` = model1),
#'   project_name = "MPG Analysis"
#' )
#' }
sync_export <- function(..., file = NULL, project_name = NULL,
                        style = "apa7", overwrite = TRUE) {
  
  # Use rlang to capture variable names for auto-naming
  quos <- rlang::enquos(...)
  dot_names <- names(quos)
  
  # Define parameters that should be passed to sync_stats instead of being treated as objects
  param_keys <- c("vars", "group_var", "digits", "conf_level", "label", "id_prefix")
  is_param <- !is.null(dot_names) & dot_names %in% param_keys
  
  # Separate objects from params
  object_quos <- quos[!is_param]
  param_quos <- quos[is_param]
  
  # Evaluate parameters once
  extra_args <- lapply(param_quos, rlang::eval_tidy)
  
  objects <- lapply(seq_along(object_quos), function(i) {
    obj <- rlang::eval_tidy(object_quos[[i]])
    # If already a statsync collection or table, pass it through
    if (inherits(obj, c("statsync_collection", "statsync_table"))) {
      return(obj)
    }
    # Otherwise, attempt to wrap it automatically in sync_stats()
    expr <- rlang::quo_get_expr(object_quos[[i]])
    nm <- names(object_quos)[i]
    if (is.null(nm) || nm == "") {
      nm <- if (is.symbol(expr)) as.character(expr) else deparse(expr)
      
      # Clean up newlines or excessive length from deparse
      if (length(nm) > 1) nm <- paste(nm, collapse = " ")
      if (nchar(nm) > 30) nm <- paste0(substr(nm, 1, 27), "...")
      
      # If it's something like iris$Sepal.Length, try to get just the last part
      if (grepl("\\$", nm)) {
        parts <- strsplit(nm, "\\$")[[1]]
        nm <- parts[length(parts)]
      }
    }
    tryCatch({
      # Build final argument list — ensuring each name exists only once
      call_args <- list(x = obj)
      
      # Set default naming if not already overridden in extra_args 
      # Note: extra_args keys take precedence
      if (!"id_prefix" %in% names(extra_args)) {
        call_args$id_prefix <- nm
      }
      if (!"label" %in% names(extra_args)) {
        call_args$label <- nm
      }
      
      # Add user overrides and other parameters
      for (k in names(extra_args)) {
        call_args[[k]] <- extra_args[[k]]
      }
      
      do.call(sync_stats, call_args)
    }, error = function(e) {
      warning("Auto-sync skipped '", nm, "': ", e$message)
      NULL
    })
  })
  
  # Remove nulls (failed wraps)
  objects <- Filter(Negate(is.null), objects)
  
  # Separate collections from tables
  collections <- Filter(function(x) inherits(x, "statsync_collection"),
                        objects)
  tables <- Filter(function(x) inherits(x, "statsync_table"), objects)
  
  # Flatten all statistics
  all_stats <- unlist(lapply(collections, function(c) c$stats),
                      recursive = FALSE)
  
  # Check for duplicate IDs
  ids <- sapply(all_stats, function(s) s$id)
  if (any(duplicated(ids))) {
    dups <- ids[duplicated(ids)]
    warning("Duplicate statistic IDs found: ",
            paste(dups, collapse = ", "),
            ". Later entries will be suffixed.")
    # Auto-fix
    for (i in seq_along(all_stats)) {
      if (sum(ids[1:i] == ids[i]) > 1) {
        count <- sum(ids[1:i] == ids[i])
        all_stats[[i]]$id <- paste0(all_stats[[i]]$id, "_", count)
      }
    }
  }
  
  # Determine source script hash
  script_hash <- tryCatch({
    src <- sys.frame(1)$ofile  # try to get calling script
    if (!is.null(src) && file.exists(src)) {
      tools::md5sum(src)
    } else {
      NA_character_
    }
  }, error = function(e) NA_character_)
  
  # Build the export object
  export_obj <- list(
    version = "1.0.0",
    project = list(
      name = project_name %||% "Untitled Analysis",
      r_version = paste0(R.version$major, ".", R.version$minor),
      hash = as.character(script_hash)
    ),
    generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    options = list(
      style = style,
      decimal_places = 2,
      leading_zero = TRUE,
      thousands_separator = FALSE
    ),
    statistics = lapply(all_stats, function(s) {
      list(
        id = s$id,
        label = s$label,
        group = s$group,
        type = s$type,
        formatted = s$formatted,
        formatted_parts = s$formatted_parts,
        raw = s$raw,
        context = s$context
      )
    }),
    tables = lapply(tables, function(t) {
      list(
        id = t$id,
        caption = t$caption,
        note = t$note,
        headers = t$headers,
        rows = t$rows,
        style = t$style
      )
    })
  )
  
  # Default file path
  if (is.null(file)) {
    dir_name <- ".statsync"
    if (!dir.exists(dir_name)) dir.create(dir_name, recursive = TRUE)
    safe_name <- gsub("[^a-zA-Z0-9]", "_",
                      project_name %||% "analysis")
    file <- file.path(dir_name, paste0(safe_name, ".statsync.json"))
  }
  
  json_str <- jsonlite::toJSON(export_obj, pretty = TRUE,
                               auto_unbox = TRUE, null = "null",
                               na = "null")
  writeLines(json_str, file)
  
  cli_msg <- paste0(
    "\u2714 Exported ", length(all_stats), " statistics and ",
    length(tables), " tables to:\n  ", normalizePath(file, mustWork = FALSE)
  )
  message(cli_msg)
  
  invisible(normalizePath(file, mustWork = FALSE))
}

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
#' @return Invisible server object. Also creates \code{sync_update()} and
#'   \code{sync_stop()} functions in the global environment.
#' @details
#' After calling \code{sync_serve()}, use \code{sync_update()} to push new
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
#' sync_update(sync_stats(model2, label = "MPG Model"))
#' }
#' @export
sync_serve <- function(..., port = 8877,
                       project_name = "StatSync Project",
                       open_browser = FALSE) {
  if (!requireNamespace("httpuv", quietly = TRUE)) {
    stop("Install httpuv: install.packages('httpuv')")
  }
  
  # Shared state
  state <- new.env(parent = emptyenv())
  state$data <- NULL
  state$last_update <- Sys.time()
  
  objects <- list(...)
  if (length(objects) > 0) {
    if (is.character(objects[[1]]) && length(objects) == 1) {
      # Fallback for old behaviour specifying file directly
      state$data <- jsonlite::fromJSON(objects[[1]], simplifyVector = TRUE, simplifyDataFrame = FALSE, simplifyMatrix = FALSE)
    } else {
      # Export to temp, read back
      tmp <- tempfile(fileext = ".statsync.json")
      sync_export(..., file = tmp, project_name = project_name)
      state$data <- jsonlite::fromJSON(tmp, simplifyVector = TRUE, simplifyDataFrame = FALSE, simplifyMatrix = FALSE)
    }
  }
  
  # Save project_name for use in update_fn closure
  saved_project_name <- project_name
  
  # Function to update server data from R console
  update_fn <- function(...) {
    tmp <- tempfile(fileext = ".statsync.json")
    sync_export(..., file = tmp, project_name = saved_project_name)
    new_data <- jsonlite::fromJSON(tmp, simplifyVector = TRUE, simplifyDataFrame = FALSE, simplifyMatrix = FALSE)
    
    if (is.null(state$data) || length(state$data$statistics) == 0) {
      state$data <- new_data
    } else {
      # Merge new data into existing data, overwriting those with the same group/label
      get_g <- function(x) {
        v <- x$group
        if (is.list(v)) v <- unlist(v)
        if (is.null(v) || length(v) == 0) "" else as.character(v[[1]])
      }
      get_id <- function(x) {
        v <- x$id
        if (is.list(v)) v <- unlist(v)
        if (is.null(v) || length(v) == 0) "" else as.character(v[[1]])
      }
      
      new_groups <- unique(vapply(new_data$statistics, get_g, character(1)))
      old_stats <- state$data$statistics
      old_stats_kept <- Filter(function(x) !(get_g(x) %in% new_groups), old_stats)
      state$data$statistics <- c(old_stats_kept, new_data$statistics)
      
      # Handle tables similarly by ID/caption
      if (length(new_data$tables) > 0) {
        new_tables <- unique(vapply(new_data$tables, get_id, character(1)))
        old_tables <- state$data$tables
        old_tables_kept <- Filter(function(x) !(get_id(x) %in% new_tables), old_tables)
        state$data$tables <- c(old_tables_kept, new_data$tables)
      }
    }
    
    state$last_update <- Sys.time()
    if (!is.null(state$data)) {
       state$data$generated_at <- format(state$last_update, "%Y-%m-%dT%H:%M:%S%z")
    }
    message("\u2714 Server data updated at ", state$last_update)
  }
  
  # Function to delete models from the server by label
  delete_fn <- function(...) {
    if (is.null(state$data)) {
      message("Server is empty. Nothing to delete.")
      return(invisible(NULL))
    }
    
    # Capture unquoted variable names as strings (like sync_export) or quoted
    quos <- rlang::enquos(...)
    labels_to_delete <- sapply(seq_along(quos), function(i) {
      expr <- rlang::quo_get_expr(quos[[i]])
      if (is.character(expr)) {
        return(expr)
      } else if (is.symbol(expr)) {
        return(as.character(expr))
      } else {
        return(as.character(expr)[1]) # fallback
      }
    })
    
    if (length(labels_to_delete) == 0) {
      message("Please provide one or more model labels to delete (e.g., sync_delete(model1) or sync_delete(\"model1\")).")
      return(invisible(NULL))
    }
    
    old_stats <- state$data$statistics
    get_g <- function(x) {
      v <- x$group; if (is.list(v)) v <- unlist(v)
      if (is.null(v) || length(v) == 0) "" else as.character(v[[1]])
    }
    get_id <- function(x) {
      v <- x$id; if (is.list(v)) v <- unlist(v)
      if (is.null(v) || length(v) == 0) "" else as.character(v[[1]])
    }
    state$data$statistics <- Filter(function(x) !(get_g(x) %in% labels_to_delete || get_id(x) %in% labels_to_delete), old_stats)
    
    old_tables <- state$data$tables
    state$data$tables <- Filter(function(x) !(get_id(x) %in% labels_to_delete), old_tables)
    
    state$last_update <- Sys.time()
    state$data$generated_at <- format(state$last_update, "%Y-%m-%dT%H:%M:%S%z")
    message(sprintf("\u2714 Deleted models. Server data updated at %s", state$last_update))
  }
  
  # Function to clear all models
  clear_fn <- function() {
    if (!is.null(state$data)) {
      # Use I() or empty list ensuring jsonlite drops to JSON array
      state$data$statistics <- vector("list", 0)
      state$data$tables <- vector("list", 0)
      state$last_update <- Sys.time()
      state$data$generated_at <- format(state$last_update, "%Y-%m-%dT%H:%M:%S%z")
      message("\u2714 Server data completely cleared at ", state$last_update)
    }
  }
  
  app <- list(
    call = function(req) {
      path <- req$PATH_INFO
      
      # CORS headers for Office Add-in
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
        body <- if (!is.null(state$data)) {
          jsonlite::toJSON(state$data, auto_unbox = TRUE)
        } else {
          '{"statistics": [], "tables": []}'
        }
        return(list(status = 200L, headers = cors_headers,
                    body = body))
      }
      
      if (path == "/status") {
        body <- jsonlite::toJSON(list(
          active = TRUE,
          last_update = format(state$last_update),
          n_stats = if (!is.null(state$data))
            length(state$data$statistics) else 0
        ), auto_unbox = TRUE)
        return(list(status = 200L, headers = cors_headers,
                    body = body))
      }
      
      list(status = 404L, headers = cors_headers,
           body = '{"error": "Not found"}')
    }
  )
  
  server <- tryCatch({
    httpuv::startServer("127.0.0.1", port, app)
  }, error = function(e) {
    if (grepl("already in use", e$message) || grepl("Failed to create server", e$message)) {
      stop(sprintf("\n\n\u274c ERROR: Port %d is already in use by another StatSync server.\n\nPlease run `sync_stop()` in the console to shut down the existing server before starting a new one.\n", port), call. = FALSE)
    } else {
      stop(e$message, call. = FALSE)
    }
  })
  
  message(sprintf(
    "\u2714 StatSync server running at http://localhost:%d\n  Project: %s\n  Use sync_update() to append/update new models.\n  Use sync_delete(\"model_name\") to remove models.\n  Use sync_stop() to stop the server.", port, project_name
  ))
  
  # Register in global namespace for easy access
  assign("sync_update", update_fn, envir = .GlobalEnv)
  assign("sync_delete", delete_fn, envir = .GlobalEnv)
  assign("sync_clear", clear_fn, envir = .GlobalEnv)
  assign("sync_stop", function() {
    httpuv::stopServer(server)
    message("Server stopped.")
  }, envir = .GlobalEnv)
  
  invisible(server)
}

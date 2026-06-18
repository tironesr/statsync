# Global package state for the sync server
.statsync_state <- new.env(parent = emptyenv())
.statsync_state$data <- NULL
.statsync_state$last_update <- Sys.time()
.statsync_state$server <- NULL
.statsync_state$project_name <- "StatSync Project"
.statsync_state$destroyed_projects <- character(0)

# Helper to automatically persist memory state to disk
save_state_to_disk <- function() {
  if (is.null(.statsync_state$data)) return(invisible(NULL))
  dir_name <- ".statsync"
  if (!dir.exists(dir_name)) dir.create(dir_name, recursive = TRUE, showWarnings = FALSE)
  safe_name <- gsub("[^a-zA-Z0-9]", "_", .statsync_state$project_name %||% "analysis")
  file_path <- file.path(dir_name, paste0(safe_name, ".statsync.json"))
  json_str <- jsonlite::toJSON(.statsync_state$data, pretty = TRUE, auto_unbox = TRUE, null = "null", na = "null")
  writeLines(json_str, file_path)
  invisible(file_path)
}

#' Export or update statistics in StatSync
#'
#' Pushes new or updated models to the active StatSync server memory,
#' automatically saving them to the background. Optionally exports the
#' entire session to a specific JSON file.
#'
#' This is the primary function for adding models to StatSync, whether
#' exporting for the first time, updating an existing model, or generating
#' manual file backups.
#'
#' @param ... Raw statistical models or statsync objects to export. If empty, exports the current session memory to `file`.
#' @param file Optional output file path to dump the entire session to a JSON file.
#' @param project_name Optional name for the project.
#' @param style Formatting style (default "apa7").
#' @param overwrite Overwrite existing file.
#' @param table Generate a regression table alongside statistics (for supported models)
#' @return Invisible file path if `file` is provided, otherwise invisible NULL.
#' @export
sync_export <- function(..., file = NULL, project_name = NULL,
                        style = "apa7", overwrite = TRUE) {
  
  if (!is.null(project_name)) {
    .statsync_state$project_name <- project_name
  }
  
  if (...length() > 0) {
    quos <- rlang::enquos(...)
    dot_names <- names(quos)
    if (is.null(dot_names)) dot_names <- rep("", length(quos))
    param_keys <- c("vars", "group_var", "digits", "conf_level", "label", "id_prefix", "table")
    is_param <- !is.null(dot_names) & dot_names %in% param_keys
    object_quos <- quos[!is_param]
    param_quos <- quos[is_param]
    extra_args <- lapply(param_quos, rlang::eval_tidy)
    
    objects <- lapply(seq_along(object_quos), function(i) {
      obj <- rlang::eval_tidy(object_quos[[i]])
      if (inherits(obj, c("statsync_collection", "statsync_table"))) return(obj)
      expr <- rlang::quo_get_expr(object_quos[[i]])
      nm <- names(object_quos)[i]
      if (is.null(nm) || nm == "") {
        nm <- if (is.symbol(expr)) as.character(expr) else deparse(expr)
        if (length(nm) > 1) nm <- paste(nm, collapse = " ")
        if (nchar(nm) > 30) nm <- paste0(substr(nm, 1, 27), "...")
        if (grepl("\\$", nm)) nm <- sub(".*\\$", "", nm)
      }
      call_args <- c(list(obj, label = nm), extra_args)
      do.call(sync_stats, call_args)
    })
    
    flat_objects <- list()
    for (obj in objects) {
      if (is.list(obj) && !inherits(obj, c("statsync_collection", "statsync_table"))) {
        for (sub in obj) if (inherits(sub, c("statsync_collection", "statsync_table"))) flat_objects <- c(flat_objects, list(sub))
      } else {
        flat_objects <- c(flat_objects, list(obj))
      }
    }
    objects <- flat_objects
  
    collections <- Filter(function(x) inherits(x, "statsync_collection"), objects)
    tables <- Filter(function(x) inherits(x, "statsync_table"), objects)
    all_stats <- unlist(lapply(collections, function(c) c$stats), recursive = FALSE)
    
    ids <- sapply(all_stats, function(s) s$id)
    if (any(duplicated(ids))) {
      used_ids <- character(0)
      for (i in seq_along(all_stats)) {
        orig_id <- all_stats[[i]]$id
        new_id <- orig_id
        count <- 1
        while (new_id %in% used_ids) {
          count <- count + 1
          new_id <- paste0(orig_id, "_", count)
        }
        all_stats[[i]]$id <- new_id
        used_ids <- c(used_ids, new_id)
      }
    }
  
    new_data <- list(
      version = "1.0.0",
      project = list(
        name = .statsync_state$project_name %||% "Untitled Analysis",
        r_version = paste0(R.version$major, ".", R.version$minor),
        hash = NA_character_
      ),
      generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
      options = list(style = style, decimal_places = 2, leading_zero = TRUE, thousands_separator = FALSE),
      statistics = lapply(all_stats, function(s) {
        list(id = s$id, label = s$label, group = s$group, type = s$type, formatted = s$formatted, formatted_parts = s$formatted_parts, raw = s$raw, context = s$context)
      }),
      tables = lapply(tables, function(t) {
        list(id = t$id, caption = t$caption, note = t$note, headers = t$headers, rows = t$rows, style = t$style)
      })
    )
    
    if (is.null(.statsync_state$data) || length(.statsync_state$data$statistics) == 0) {
      .statsync_state$data <- new_data
    } else {
      .statsync_state$data$project$name <- .statsync_state$project_name
      get_g <- function(x) {
        v <- x$group; if (is.list(v)) v <- unlist(v)
        if (is.null(v) || length(v) == 0) "" else as.character(v[[1]])
      }
      get_id <- function(x) {
        v <- x$id; if (is.list(v)) v <- unlist(v)
        if (is.null(v) || length(v) == 0) "" else as.character(v[[1]])
      }
      new_groups <- unique(vapply(new_data$statistics, get_g, character(1)))
      old_stats <- .statsync_state$data$statistics
      old_stats_kept <- Filter(function(x) !(get_g(x) %in% new_groups), old_stats)
      .statsync_state$data$statistics <- c(old_stats_kept, new_data$statistics)
      
      if (length(new_data$tables) > 0) {
        new_tables <- unique(vapply(new_data$tables, get_id, character(1)))
        old_tables <- .statsync_state$data$tables
        old_tables_kept <- Filter(function(x) !(get_id(x) %in% new_tables), old_tables)
        .statsync_state$data$tables <- c(old_tables_kept, new_data$tables)
      }
    }
    .statsync_state$last_update <- Sys.time()
    if (!is.null(.statsync_state$data)) {
       .statsync_state$data$generated_at <- format(.statsync_state$last_update, "%Y-%m-%dT%H:%M:%S%z")
    }
    if (!is.null(.statsync_state$server)) {
      message("\u2714 Server data updated at ", .statsync_state$last_update)
    } else {
      message("\u2714 Project data updated at ", .statsync_state$last_update, " (Server is offline)")
    }
  }
  
  if (is.null(file)) {
    save_state_to_disk()
    return(invisible(NULL))
  } else {
    if (is.null(.statsync_state$data)) {
      message("No data to export. Server is empty.")
      return(invisible(NULL))
    }
    
    json_str <- jsonlite::toJSON(.statsync_state$data, pretty = TRUE, auto_unbox = TRUE, null = "null", na = "null")
    writeLines(json_str, file)
    
    cli_msg <- paste0(
      "\u2714 Exported ", length(.statsync_state$data$statistics), " statistics and ",
      length(.statsync_state$data$tables), " tables to:\n  ", normalizePath(file, mustWork = FALSE)
    )
    message(cli_msg)
    return(invisible(normalizePath(file, mustWork = FALSE)))
  }
}

#' Delete models from the live server
#'
#' Removes specific models or tables from the active StatSync server by their
#' human-readable labels or IDs.
#'
#' @param ... Unquoted or quoted names of the model labels to delete (e.g., \code{sync_delete("model1")}).
#' @return Invisible NULL.
#' @export
sync_delete <- function(...) {
  if (is.null(.statsync_state$data) || length(.statsync_state$data$statistics) + length(.statsync_state$data$tables) == 0) {
    stop("Active project is empty. Nothing to delete.")
  }
  quos <- rlang::enquos(...)
  labels_to_delete <- sapply(seq_along(quos), function(i) {
    expr <- rlang::quo_get_expr(quos[[i]])
    if (is.character(expr)) return(expr)
    else if (is.symbol(expr)) return(as.character(expr))
    else return(as.character(expr)[1])
  })
  if (length(labels_to_delete) == 0) {
    message("Please provide one or more model labels to delete.")
    return(invisible(NULL))
  }
  get_g <- function(x) {
    v <- x$group; if (is.list(v)) v <- unlist(v)
    if (is.null(v) || length(v) == 0) "" else as.character(v[[1]])
  }
  get_id <- function(x) {
    v <- x$id; if (is.list(v)) v <- unlist(v)
    if (is.null(v) || length(v) == 0) "" else as.character(v[[1]])
  }
  
  existing_stats <- c(
    vapply(.statsync_state$data$statistics, get_g, character(1)),
    vapply(.statsync_state$data$statistics, get_id, character(1))
  )
  existing_tables <- vapply(.statsync_state$data$tables, get_id, character(1))
  all_existing <- c(existing_stats, existing_tables)
  
  missing_labels <- setdiff(labels_to_delete, all_existing)
  if (length(missing_labels) > 0) {
    stop("The following objects do not exist in the active project: ", paste(missing_labels, collapse = ", "))
  }
  
  .statsync_state$data$statistics <- Filter(function(x) !(get_g(x) %in% labels_to_delete || get_id(x) %in% labels_to_delete), .statsync_state$data$statistics)
  .statsync_state$data$tables <- Filter(function(x) !(get_id(x) %in% labels_to_delete), .statsync_state$data$tables)
  
  .statsync_state$last_update <- Sys.time()
  .statsync_state$data$generated_at <- format(.statsync_state$last_update, "%Y-%m-%dT%H:%M:%S%z")
  message(sprintf("\u2714 Deleted models. Server data updated at %s", .statsync_state$last_update))
  save_state_to_disk()
}

#' Clear all data from the live server
#'
#' Deletes all tracked statistics and tables from the global StatSync state,
#' ensuring that future exports or syncs start with a blank slate.
#'
#' @return Invisible NULL.
#' @export
sync_clear <- function() {
  if (!is.null(.statsync_state$data)) {
    .statsync_state$data$statistics <- vector("list", 0)
    .statsync_state$data$tables <- vector("list", 0)
    .statsync_state$last_update <- Sys.time()
    .statsync_state$data$generated_at <- format(.statsync_state$last_update, "%Y-%m-%dT%H:%M:%S%z")
    message("\u2714 Server data completely cleared at ", .statsync_state$last_update)
    save_state_to_disk()
  }
}

#' Stop the active StatSync server
#'
#' Shuts down the local HTTP server if one is currently running via
#' \code{sync_serve()}.
#'
#' @return Invisible NULL.
#' @export
sync_stop <- function() {
  if (!is.null(.statsync_state$server)) {
    httpuv::stopServer(.statsync_state$server)
    .statsync_state$server <- NULL
    message("\u25fc StatSync server stopped.")
  } else {
    message("No StatSync server is currently running.")
  }
  invisible(NULL)
}

#' Delete a StatSync project and its saved data
#'
#' Permanently removes a project's `.statsync.json` file from the disk.
#' If the project is currently active, it clears the live server's memory
#' and resets the active project name.
#'
#' @param project_name The name of the project to delete
#' @return Invisible NULL.
#' @export
sync_destroy <- function(project_name) {
  if (missing(project_name) || !is.character(project_name) || length(project_name) != 1) {
    stop("Please provide a valid project_name string.")
  }
  
  safe_name <- gsub("[^a-zA-Z0-9]", "_", project_name)
  file_path <- file.path(".statsync", paste0(safe_name, ".statsync.json"))
  
  if (!file.exists(file_path)) {
    stop(sprintf("\u274c Project '%s' does not exist on disk.", project_name))
  }
  
  unlink(file_path)
  message(sprintf("\u2714 Deleted project file: %s", file_path))
  
  if (identical(.statsync_state$project_name, project_name)) {
    .statsync_state$project_name <- "StatSync Project"
    .statsync_state$data <- NULL
    message("Active project memory cleared.")
  }
  
  .statsync_state$destroyed_projects <- unique(c(.statsync_state$destroyed_projects, project_name))
  message(sprintf("\u2714 Project '%s' will be removed from the Word Add-in.", project_name))
  
  invisible(NULL)
}

#' Forcibly free the StatSync port
#'
#' Kills any orphaned background processes that are holding the StatSync port (8877).
#' This is useful if `sync_serve()` says the port is already in use, but `sync_stop()` 
#' says no server is currently running (which happens when an R session crashes in the background).
#'
#' @return Invisible NULL.
#' @export
sync_free_port <- function() {
  port <- 8877
  os <- .Platform$OS.type
  
  if (os == "windows") {
    out <- suppressWarnings(system(sprintf("netstat -ano | findstr :%d", port), intern = TRUE))
    if (length(out) > 0) {
      pid <- tail(strsplit(trimws(out[1]), "\\s+")[[1]], 1)
      system(sprintf("taskkill /PID %s /F", pid), ignore.stdout = TRUE, ignore.stderr = TRUE)
      message(sprintf("\u2714 Successfully killed orphaned background process (PID %s) holding port %d.", pid, port))
    } else {
      message(sprintf("\u2139 Port %d is not currently in use.", port))
    }
  } else {
    out <- suppressWarnings(system(sprintf("lsof -t -i:%d", port), intern = TRUE))
    if (length(out) > 0) {
      pid <- out[1]
      system(sprintf("kill -9 %s", pid))
      message(sprintf("\u2714 Successfully killed orphaned background process (PID %s) holding port %d.", pid, port))
    } else {
      message(sprintf("\u2139 Port %d is not currently in use.", port))
    }
  }
  
  invisible(NULL)
}

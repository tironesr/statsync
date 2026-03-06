#' Report a test result inline in RMarkdown
#' @export
report <- function(x, ...) UseMethod("report")

#' @export
report.htest <- function(x, digits = 2, ...) {
  stats <- sync_stats(x, digits = digits)
  strip_markup(stats$stats[[1]]$formatted)
}

#' @export
report.lm <- function(x, term = NULL, digits = 2, ...) {
  stats <- sync_stats(x, digits = digits)
  
  if (is.null(term)) {
    strip_markup(stats$stats[[1]]$formatted)
  } else {
    match <- Filter(function(s) grepl(term, s$id, fixed = TRUE),
                    stats$stats)
    if (length(match) == 0) stop("Term '", term, "' not found")
    strip_markup(match[[1]]$formatted)
  }
}

#' @export
report.aov <- function(x, term, digits = 2, ...) {
  stats <- sync_stats(x, digits = digits)
  match <- Filter(function(s) grepl(term, s$id, fixed = TRUE),
                  stats$stats)
  if (length(match) == 0) stop("Term '", term, "' not found")
  strip_markup(match[[1]]$formatted)
}

#' Report descriptive statistics inline
#' @export
report_desc <- function(x, digits = 2) {
  if (is.numeric(x)) {
    strip_markup(fmt_mean_sd(mean(x, na.rm = TRUE),
                             sd(x, na.rm = TRUE), digits))
  } else {
    stop("Expected numeric vector")
  }
}
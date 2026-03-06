# ============================================================
# TABLE GENERATORS
# ============================================================

#' Create a regression table for export
#'
#' @param ... Named model objects (e.g., `Model1 = lm1, Model2 = lm2`)
#' @param conf_level Confidence level for intervals
#' @param stars Show significance stars
#' @param notes Table notes
#' @param digits Decimal places
#' @return A statsync_table object
#' @export
sync_regression_table <- function(..., conf_level = 0.95,
                                  stars = TRUE, notes = NULL,
                                  digits = 2) {
  models <- list(...)
  if (is.null(names(models))) {
    names(models) <- paste("Model", seq_along(models))
  }
  
  # Collect all terms across models
  all_coefs <- lapply(names(models), function(name) {
    df <- broom::tidy(models[[name]], conf.int = TRUE,
                      conf.level = conf_level)
    df$model <- name
    df
  })
  all_coefs <- dplyr::bind_rows(all_coefs)
  all_terms <- unique(all_coefs$term)
  
  # Build header
  headers <- list(
    list(label = "", italic = FALSE, span = 1)
  )
  for (name in names(models)) {
    headers <- c(headers, list(
      list(label = name, italic = FALSE, span = 3)
    ))
  }
  
  sub_headers <- list(list(label = "Predictor", italic = FALSE, span = 1))
  for (name in names(models)) {
    sub_headers <- c(sub_headers, list(
      list(label = "b", italic = TRUE, span = 1),
      list(label = "SE", italic = TRUE, span = 1),
      list(label = "p", italic = TRUE, span = 1)
    ))
  }
  
  # Build rows
  rows <- list()
  for (term in all_terms) {
    cells <- list(
      list(value = format_term_name(term), bold = FALSE,
           italic = FALSE, indent = 0)
    )
    
    for (name in names(models)) {
      row_data <- all_coefs[all_coefs$term == term &
                              all_coefs$model == name, ]
      
      if (nrow(row_data) == 0) {
        cells <- c(cells, list(
          list(value = ""),
          list(value = ""),
          list(value = "")
        ))
      } else {
        p_formatted <- format_decimal(row_data$p.value, 3,
                                      leading_zero = FALSE)
        est_formatted <- format_decimal(row_data$estimate, digits)
        
        if (stars) {
          est_formatted <- paste0(est_formatted,
                                  p_to_stars(row_data$p.value))
        }
        
        cells <- c(cells, list(
          list(value = est_formatted,
               stat_id = paste0(name, ".", term, ".estimate")),
          list(value = format_decimal(row_data$std.error, digits),
               stat_id = paste0(name, ".", term, ".se")),
          list(value = p_formatted,
               stat_id = paste0(name, ".", term, ".p"))
        ))
      }
    }
    
    rows <- c(rows, list(list(cells = cells, is_header = FALSE,
                              border_bottom = FALSE)))
  }
  
  # Model fit rows
  fit_row_r2 <- list(list(value = "R\u00B2", italic = TRUE, indent = 0))
  fit_row_adjr2 <- list(list(value = "Adjusted R\u00B2",
                             italic = TRUE, indent = 0))
  fit_row_n <- list(list(value = "N", italic = TRUE, indent = 0))
  
  for (name in names(models)) {
    gl <- broom::glance(models[[name]])
    fit_row_r2 <- c(fit_row_r2, list(
      list(value = format_decimal(gl$r.squared, 3,
                                  leading_zero = FALSE)),
      list(value = ""),
      list(value = "")
    ))
    fit_row_adjr2 <- c(fit_row_adjr2, list(
      list(value = format_decimal(gl$adj.r.squared, 3,
                                  leading_zero = FALSE)),
      list(value = ""),
      list(value = "")
    ))
    fit_row_n <- c(fit_row_n, list(
      list(value = as.character(gl$nobs)),
      list(value = ""),
      list(value = "")
    ))
  }
  
  rows <- c(rows, list(
    list(cells = fit_row_r2, is_header = FALSE, border_bottom = FALSE),
    list(cells = fit_row_adjr2, is_header = FALSE, border_bottom = FALSE),
    list(cells = fit_row_n, is_header = FALSE, border_bottom = TRUE)
  ))
  
  # Default note
  if (is.null(notes) && stars) {
    notes <- "* p < .05. ** p < .01. *** p < .001."
  }
  
  structure(
    list(
      id = paste0("reg_table_",
                  paste(names(models), collapse = "_")),
      caption = "Regression Results",
      note = notes,
      headers = list(headers, sub_headers),
      rows = rows,
      style = list(apa_table = TRUE, font_size = 10,
                   font_family = "Times New Roman")
    ),
    class = "statsync_table"
  )
}

#' Create a correlation matrix table
#' @export
sync_correlation_table <- function(data, vars = NULL, method = "pearson",
                                   digits = 2, caption = NULL) {
  if (is.null(vars)) vars <- names(data)[sapply(data, is.numeric)]
  subset_data <- data[, vars, drop = FALSE]
  
  n <- ncol(subset_data)
  var_labels <- vars
  
  # Compute correlations and p-values
  cor_mat <- cor(subset_data, use = "pairwise.complete.obs",
                 method = method)
  p_mat <- matrix(NA, n, n)
  for (i in 1:(n - 1)) {
    for (j in (i + 1):n) {
      test <- cor.test(subset_data[[i]], subset_data[[j]],
                       method = method)
      p_mat[i, j] <- test$p.value
      p_mat[j, i] <- test$p.value
    }
  }
  
  # Build headers
  headers <- c(
    list(list(label = "Variable", span = 1)),
    lapply(seq_along(var_labels), function(i) {
      list(label = as.character(i), span = 1)
    }),
    list(list(label = "M", italic = TRUE, span = 1),
         list(label = "SD", italic = TRUE, span = 1))
  )
  
  # Build rows
  rows <- list()
  for (i in seq_along(var_labels)) {
    cells <- list(
      list(value = paste0(i, ". ", var_labels[i]))
    )
    
    for (j in seq_along(var_labels)) {
      if (j >= i) {
        if (j == i) {
          cells <- c(cells, list(list(value = "\u2014")))  # em dash
        } else {
          r_val <- cor_mat[i, j]
          p_val <- p_mat[i, j]
          display <- paste0(
            format_decimal(r_val, digits, leading_zero = FALSE),
            p_to_stars(p_val)
          )
          cells <- c(cells, list(list(
            value = display,
            stat_id = paste0("cor.", vars[i], ".", vars[j])
          )))
        }
      } else {
        cells <- c(cells, list(list(value = "")))
      }
    }
    
    # M and SD columns
    m <- mean(subset_data[[i]], na.rm = TRUE)
    s <- sd(subset_data[[i]], na.rm = TRUE)
    cells <- c(cells, list(
      list(value = format_decimal(m, digits)),
      list(value = format_decimal(s, digits))
    ))
    
    rows <- c(rows, list(list(cells = cells)))
  }
  
  structure(
    list(
      id = "correlation_matrix",
      caption = caption %||% "Correlations, Means, and Standard Deviations",
      note = "* p < .05. ** p < .01. *** p < .001.",
      headers = list(headers),
      rows = rows,
      style = list(apa_table = TRUE, font_size = 10,
                   font_family = "Times New Roman")
    ),
    class = "statsync_table"
  )
}

# --- Helpers ---
format_term_name <- function(term) {
  term <- gsub("\\(Intercept\\)", "Intercept", term)
  term <- gsub(":", " \u00D7 ", term)  # multiplication sign for interactions
  term
}

p_to_stars <- function(p) {
  dplyr::case_when(
    is.na(p) ~ "",
    p < .001  ~ "***",
    p < .01   ~ "**",
    p < .05   ~ "*",
    TRUE      ~ ""
  )
}
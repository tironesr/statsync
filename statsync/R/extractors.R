# ============================================================
# UNIVERSAL STATISTIC EXTRACTORS
# ============================================================

#' Extract and format statistics from any supported model object
#'
#' @param x A fitted model, test result, or data frame
#' @param id_prefix Prefix for statistic IDs
#' @param label Optional human-readable label
#' @param style Formatting style ("apa7", "apa6")
#' @param digits Default decimal places
#' @param ... Additional arguments for specific methods
#' @return A statsync_collection object
#' @export
sync_stats <- function(x, id_prefix = NULL, label = NULL,
                       style = "apa7", digits = 2, ...) {
  if (is.null(id_prefix)) {
    id_prefix <- deparse(substitute(x))
    id_prefix <- gsub("[^a-zA-Z0-9]", "_", id_prefix)
  }
  
  UseMethod("sync_stats")
}

# --- t-test ---
#' @export
sync_stats.htest <- function(x, id_prefix = NULL, label = NULL,
                             style = "apa7", digits = 2, ...) {
  if (is.null(id_prefix)) {
    if (!is.null(label)) id_prefix <- tolower(gsub("[^a-zA-Z0-9]", "_", label))
    else id_prefix <- "test"
  }
  if (is.null(label)) label <- x$method
  
  # Safely extract numeric values — htest objects return named numerics
  safe_num <- function(val) {
    if (is.null(val)) return(NA_real_)
    as.numeric(val)[1]
  }
  
  # Detect test type
  test_type <- dplyr::case_when(
    grepl("t-test", x$method, ignore.case = TRUE) ~ "t_test",
    grepl("Chi-squared", x$method) ~ "chi_square",
    grepl("correlation", x$method, ignore.case = TRUE) ~ "correlation",
    grepl("Wilcoxon", x$method) ~ "wilcoxon",
    grepl("Fisher", x$method) ~ "fisher",
    TRUE ~ "htest"
  )
  
  stats <- list()
  
  if (test_type == "t_test") {
    t_val <- safe_num(x$statistic)
    df_val <- safe_num(x$parameter)
    p_val <- safe_num(x$p.value)
    est <- as.numeric(x$estimate)
    ci <- as.numeric(x$conf.int)
    
    # Calculate Cohen's d (approximate)
    cohens_d <- tryCatch({
      if (grepl("Two Sample|Welch", x$method)) {
        abs(t_val) * sqrt(2 / (df_val + 2))
      } else if (grepl("Paired", x$method)) {
        abs(t_val) / sqrt(df_val + 1)
      } else {
        abs(t_val) / sqrt(df_val)
      }
    }, error = function(e) NA_real_)
    
    stats[[1]] <- new_stat(
      id = paste0(id_prefix, ".result"),
      label = label,
      group = label,
      type = "t_test",
      formatted = fmt_t(t_val, df_val, p_val, cohens_d, digits),
      formatted_parts = list(
        t = format_decimal(t_val, digits),
        df = format_decimal(df_val,
                            if (df_val %% 1 == 0) 0 else 2),
        p = fmt_p(p_val, include_p = FALSE),
        d = if (!is.na(cohens_d)) format_decimal(cohens_d, digits) else NA,
        ci_lower = format_decimal(ci[1], digits),
        ci_upper = format_decimal(ci[2], digits)
      ),
      raw = list(
        statistic = t_val,
        df = df_val,
        p_value = p_val,
        estimate = est,
        conf_int = ci,
        cohens_d = cohens_d,
        method = x$method
      )
    )
    
  } else if (test_type == "chi_square") {
    chi_val <- safe_num(x$statistic)
    df_val  <- safe_num(x$parameter)
    p_val   <- safe_num(x$p.value)
    
    # Cramér's V
    v_val <- tryCatch({
      if (!is.null(x$observed)) {
        n <- sum(x$observed)
        k <- min(dim(x$observed)) - 1
        if (k > 0 && n > 0) {
          sqrt(chi_val / (n * k))
        } else {
          NA_real_
        }
      } else {
        NA_real_
      }
    }, error = function(e) NA_real_)
    
    stats[[1]] <- new_stat(
      id = paste0(id_prefix, ".result"),
      label = label,
      group = label,
      type = "chi_square",
      formatted = fmt_chi(chi_val, df_val, p_val, v_val, digits),
      formatted_parts = list(
        chi_sq = format_decimal(chi_val, digits),
        df = as.character(as.integer(df_val)),
        p = fmt_p(p_val, include_p = FALSE),
        cramers_v = if (!is.na(v_val))
          format_decimal(v_val, 3, leading_zero = FALSE) else NA
      ),
      raw = list(
        statistic = chi_val,
        df = df_val,
        p_value = p_val,
        cramers_v = v_val,
        n = if (!is.null(x$observed)) sum(x$observed) else NA
      )
    )
    
  } else if (test_type == "correlation") {
    r_val  <- safe_num(x$estimate)
    p_val  <- safe_num(x$p.value)
    df_val <- safe_num(x$parameter)
    ci <- if (!is.null(x$conf.int)) as.numeric(x$conf.int) else c(NA_real_, NA_real_)
    
    method <- if (grepl("Pearson", x$method)) "pearson"
    else if (grepl("Spearman", x$method)) "spearman"
    else "kendall"
    
    stats[[1]] <- new_stat(
      id = paste0(id_prefix, ".result"),
      label = label,
      group = label,
      type = "correlation",
      formatted = fmt_r(r_val, p_val,
                        df = df_val,
                        ci_lower = ci[1], ci_upper = ci[2],
                        method = method, digits = digits),
      formatted_parts = list(
        r = format_decimal(r_val, digits, leading_zero = FALSE),
        df = if (!is.na(df_val)) as.character(as.integer(df_val)) else NA,
        p = fmt_p(p_val, include_p = FALSE),
        ci_lower = format_decimal(ci[1], digits, leading_zero = FALSE),
        ci_upper = format_decimal(ci[2], digits, leading_zero = FALSE)
      ),
      raw = list(
        estimate = r_val,
        p_value = p_val,
        parameter = df_val,
        conf_int = ci,
        method = method
      )
    )
    
  } else {
    # Generic htest fallback
    stat_val <- safe_num(x$statistic)
    p_val    <- safe_num(x$p.value)
    param    <- safe_num(x$parameter)
    
    formatted_str <- paste0(
      names(x$statistic)[1], " = ", format_decimal(stat_val, digits)
    )
    if (!is.na(p_val)) {
      formatted_str <- paste0(formatted_str, ", ", fmt_p(p_val))
    }
    
    stats[[1]] <- new_stat(
      id = paste0(id_prefix, ".result"),
      label = label,
      group = label,
      type = "htest",
      formatted = formatted_str,
      formatted_parts = list(
        statistic = format_decimal(stat_val, digits),
        p = if (!is.na(p_val)) fmt_p(p_val, include_p = FALSE) else NA
      ),
      raw = list(
        statistic = stat_val,
        p_value = p_val,
        parameter = param,
        method = x$method
      )
    )
  }
  
  new_sync_collection(stats, label = label)
}
# --- Linear Model ---
#' @export
sync_stats.lm <- function(x, id_prefix = NULL, label = NULL,
                          style = "apa7", digits = 2,
                          conf_level = 0.95, ...) {
  if (is.null(id_prefix)) {
    if (!is.null(label)) id_prefix <- tolower(gsub("[^a-zA-Z0-9]", "_", label))
    else id_prefix <- "lm"
  }
  if (is.null(label)) label <- paste("Linear Model:", deparse(formula(x)))
  
  s <- summary(x)
  coef_df <- broom::tidy(x, conf.int = TRUE, conf.level = conf_level)
  glance_df <- broom::glance(x)
  
  # Residual degrees of freedom (for t-tests on coefficients)
  df_residual <- s$df[2]
  
  # ANOVA table for effect sizes
  anova_tab <- anova(x)
  ss_resid <- anova_tab["Residuals", "Sum Sq"]
  
  stats <- list()
  idx <- 1
  
  # Overall model F-test
  f_stat <- s$fstatistic
  f_p <- pf(f_stat["value"], f_stat["numdf"], f_stat["dendf"],
            lower.tail = FALSE)
  
  r_sq_sym     <- "{i}R{/i}\u00B2"
  r_sq_adj_sym <- "{i}R{/i}\u00B2adj"
  
  stats[[idx]] <- new_stat(
    id = paste0(id_prefix, ".omnibus"),
    label = paste(label, "- Overall Model"),
    group = label,
    type = "model_fit",
    formatted = paste0(
      fmt_f(f_stat["value"], f_stat["numdf"], f_stat["dendf"], f_p,
            digits = digits),
      ", ", r_sq_sym, " = ",
      format_decimal(glance_df$r.squared, 3, leading_zero = FALSE),
      ", ", r_sq_adj_sym, " = ",
      format_decimal(glance_df$adj.r.squared, 3, leading_zero = FALSE)
    ),
    formatted_parts = list(
      F_value = format_decimal(f_stat["value"], digits),
      df1 = as.character(f_stat["numdf"]),
      df2 = as.character(f_stat["dendf"]),
      p = fmt_p(f_p, include_p = FALSE),
      r_squared = format_decimal(glance_df$r.squared, 3,
                                 leading_zero = FALSE),
      adj_r_squared = format_decimal(glance_df$adj.r.squared, 3,
                                     leading_zero = FALSE),
      n = as.character(nobs(x)),
      df_residual = as.character(df_residual)
    ),
    raw = list(
      f_statistic = as.numeric(f_stat["value"]),
      df1 = as.numeric(f_stat["numdf"]),
      df2 = as.numeric(f_stat["dendf"]),
      p_value = as.numeric(f_p),
      r_squared = glance_df$r.squared,
      adj_r_squared = glance_df$adj.r.squared,
      aic = glance_df$AIC,
      bic = glance_df$BIC,
      n = nobs(x),
      df_residual = df_residual
    )
  )
  idx <- idx + 1
  
  # Individual coefficients
  for (i in seq_len(nrow(coef_df))) {
    row <- coef_df[i, ]
    term_clean <- gsub("[^a-zA-Z0-9]", "_", row$term)
    
    # Partial eta-squared for non-intercept terms
    p_eta_sq <- NA_real_
    if (row$term != "(Intercept)" && row$term %in% rownames(anova_tab)) {
      ss_term <- anova_tab[row$term, "Sum Sq"]
      p_eta_sq <- ss_term / (ss_term + ss_resid)
    }
    
    stats[[idx]] <- new_stat(
      id = paste0(id_prefix, ".", term_clean),
      label = paste(label, "-", row$term),
      group = label,
      type = "coefficient",
      formatted = fmt_coef(
        estimate = row$estimate,
        se = row$std.error,
        statistic = row$statistic,
        p = row$p.value,
        ci_lower = row$conf.low,
        ci_upper = row$conf.high,
        df_residual = df_residual,
        digits = digits
      ),
      formatted_parts = list(
        estimate = format_decimal(row$estimate, digits),
        se = format_decimal(row$std.error, digits),
        t = format_decimal(row$statistic, digits),
        df_residual = as.character(df_residual),
        t_with_df = fmt_t_regression(row$statistic, df_residual,
                                     digits = digits),
        p = fmt_p(row$p.value, include_p = FALSE),
        ci_lower = format_decimal(row$conf.low, digits),
        ci_upper = format_decimal(row$conf.high, digits),
        partial_eta_sq = if (!is.na(p_eta_sq))
          format_decimal(p_eta_sq, 3, leading_zero = FALSE) else NA
      ),
      raw = list(
        estimate = row$estimate,
        std_error = row$std.error,
        statistic = row$statistic,
        p_value = row$p.value,
        conf_low = row$conf.low,
        conf_high = row$conf.high,
        df_residual = df_residual,
        partial_eta_sq = p_eta_sq
      )
    )
    idx <- idx + 1
  }
  
  new_sync_collection(stats, label = label)
}

# --- Mixed Model (lmerTest / lme4) ---
#' @export
sync_stats.lmerModLmerTest <- function(x, id_prefix = NULL, label = NULL,
                                       style = "apa7", digits = 2,
                                       conf_level = 0.95, ...) {
  sync_stats_lmer_internal(x, id_prefix, label, style, digits, conf_level, ...)
}

#' @export
sync_stats.lmerMod <- function(x, id_prefix = NULL, label = NULL,
                               style = "apa7", digits = 2,
                               conf_level = 0.95, ...) {
  sync_stats_lmer_internal(x, id_prefix, label, style, digits, conf_level, ...)
}

sync_stats_lmer_internal <- function(x, id_prefix = NULL, label = NULL,
                                     style = "apa7", digits = 2,
                                     conf_level = 0.95, ...) {
  if (is.null(id_prefix)) {
    if (!is.null(label)) id_prefix <- tolower(gsub("[^a-zA-Z0-9]", "_", label))
    else id_prefix <- "lmer"
  }
  if (is.null(label)) label <- paste("Mixed Model:", deparse(formula(x)))
  
  if (!requireNamespace("broom.mixed", quietly = TRUE)) {
    warning("Package 'broom.mixed' is required for full lmer support. Install with install.packages('broom.mixed').")
    # Fallback to standard summary if broom.mixed is missing
    s <- summary(x)$coefficients
    coef_df <- as.data.frame(s)
    coef_df$term <- rownames(s)
    names(coef_df)[names(coef_df) == "Estimate"] <- "estimate"
    names(coef_df)[names(coef_df) == "Std. Error"] <- "std.error"
    names(coef_df)[names(coef_df) %in% c("t value", "statistic")] <- "statistic"
    names(coef_df)[names(coef_df) %in% c("Pr(>|t|)", "p.value")] <- "p.value"
    coef_df$conf.low <- NA_real_
    coef_df$conf.high <- NA_real_
  } else {
    coef_df <- broom.mixed::tidy(x, effects = "fixed", conf.int = TRUE, conf.level = conf_level)
    glance_df <- broom.mixed::glance(x)
  }
  
  stats <- list()
  idx <- 1
  
  # Semi-robust model fit
  if (exists("glance_df")) {
    stats[[idx]] <- new_stat(
      id = paste0(id_prefix, ".fit"),
      label = paste(label, "- Model Fit"),
      group = label,
      type = "model_fit",
      formatted = paste0(
        "AIC = ", format_decimal(glance_df$AIC, 1),
        ", BIC = ", format_decimal(glance_df$BIC, 1)
      ),
      formatted_parts = list(
        aic = format_decimal(glance_df$AIC, 1),
        bic = format_decimal(glance_df$BIC, 1),
        n = as.character(nobs(x))
      ),
      raw = list(
        aic = glance_df$AIC,
        bic = glance_df$BIC,
        n = nobs(x)
      )
    )
    idx <- idx + 1
  }
  
  for (i in seq_len(nrow(coef_df))) {
    row <- coef_df[i, ]
    term_clean <- gsub("[^a-zA-Z0-9]", "_", row$term)
    df_val <- if ("df" %in% names(row)) row$df else NA_real_
    
    stats[[idx]] <- new_stat(
      id = paste0(id_prefix, ".", term_clean),
      label = paste(label, "-", row$term),
      group = label,
      type = "coefficient",
      formatted = fmt_coef(
        estimate = row$estimate,
        se = row$std.error,
        statistic = row$statistic,
        p = row$p.value,
        ci_lower = row$conf.low,
        ci_upper = row$conf.high,
        df_residual = df_val,
        digits = digits
      ),
      formatted_parts = list(
        estimate = format_decimal(row$estimate, digits),
        se = format_decimal(row$std.error, digits),
        t = format_decimal(row$statistic, digits),
        df_residual = if(!is.na(df_val)) format_decimal(df_val, if(df_val %% 1 == 0) 0 else 2) else NA,
        p = if(!is.null(row$p.value)) fmt_p(row$p.value, include_p = FALSE) else NA,
        ci_lower = format_decimal(row$conf.low, digits),
        ci_upper = format_decimal(row$conf.high, digits)
      ),
      raw = list(
        estimate = row$estimate,
        std_error = row$std.error,
        statistic = row$statistic,
        p_value = if(is.null(row$p.value)) NA_real_ else row$p.value,
        df_residual = df_val,
        conf_low = row$conf.low,
        conf_high = row$conf.high
      )
    )
    idx <- idx + 1
  }
  
  new_sync_collection(stats, label = label)
}

# --- ANOVA ---
#' @export
sync_stats.aov <- function(x, id_prefix = NULL, label = NULL,
                           style = "apa7", digits = 2, ...) {
  if (is.null(id_prefix)) {
    if (!is.null(label)) id_prefix <- tolower(gsub("[^a-zA-Z0-9]", "_", label))
    else id_prefix <- "anova"
  }
  if (is.null(label)) label <- "ANOVA"
  
  s <- summary(x)
  tab <- s[[1]]
  
  ss_total <- sum(tab[, "Sum Sq"])
  ss_resid <- as.numeric(tab["Residuals", "Sum Sq"])
  df_resid <- as.numeric(tab["Residuals", "Df"])
  
  stats <- list()
  idx <- 1
  
  terms <- rownames(tab)[rownames(tab) != "Residuals"]
  
  for (term in terms) {
    row <- tab[term, ]
    term_clean <- gsub("[^a-zA-Z0-9]", "_", trimws(term))
    
    f_val  <- as.numeric(row["F value"])
    df1    <- as.numeric(row["Df"])
    p_val  <- as.numeric(row["Pr(>F)"])
    ss_val <- as.numeric(row["Sum Sq"])
    ms_val <- as.numeric(row["Mean Sq"])
    
    eta_sq         <- ss_val / ss_total
    partial_eta_sq <- ss_val / (ss_val + ss_resid)
    
    stats[[idx]] <- new_stat(
      id = paste0(id_prefix, ".", term_clean),
      label = paste(label, "-", trimws(term)),
      group = label,
      type = "f_test",
      formatted = fmt_f(
        f_val, as.integer(df1), as.integer(df_resid),
        p_val, partial_eta_sq, digits = digits
      ),
      formatted_parts = list(
        F_value = format_decimal(f_val, digits),
        df1 = as.character(as.integer(df1)),
        df2 = as.character(as.integer(df_resid)),
        p = fmt_p(p_val, include_p = FALSE),
        eta_sq = format_decimal(eta_sq, 3, leading_zero = FALSE),
        partial_eta_sq = format_decimal(partial_eta_sq, 3,
                                        leading_zero = FALSE)
      ),
      raw = list(
        f_value = f_val,
        df1 = df1,
        df2 = df_resid,
        p_value = p_val,
        sum_sq = ss_val,
        mean_sq = ms_val,
        eta_sq = eta_sq,
        partial_eta_sq = partial_eta_sq
      )
    )
    idx <- idx + 1
  }
  
  new_sync_collection(stats, label = label)
}

# --- Generic ANOVA Table (car::Anova, anova.lm, nested comparisons) ---
#' @export
sync_stats.anova <- function(x, id_prefix = NULL, label = NULL,
                             style = "apa7", digits = 2, ...) {
  if (is.null(id_prefix)) {
    if (!is.null(label)) id_prefix <- tolower(gsub("[^a-zA-Z0-9]", "_", label))
    else id_prefix <- "anova"
  }
  
  # Use broom::tidy for consistent column names and labels (formulas, etc.)
  df <- tryCatch(
    as.data.frame(broom::tidy(x)),
    error = function(e) as.data.frame(x)
  )
  
  if (is.null(label)) {
    # Detect if it's a model comparison (formulas often contain ~)
    if ("term" %in% names(df) && any(grepl("~", df$term))) {
      label <- "Model Comparison"
    } else {
      label <- "ANOVA Table"
    }
  }

  stats <- list()
  idx <- 1
  
  # Detect columns dynamically
  # Broom: statistic, p.value, df, df.residual
  # Standard: F value, Chisq, Df, Pr(>F)
  p_col <- grep("p.value|Pr\\(>", names(df), value = TRUE)[1]
  stat_col <- grep("statistic|F.value|F\\s*value|Chisq|LR.Chisq|Deviance", 
                   names(df), value = TRUE, ignore.case = TRUE)[1]
  
  # Check original object for F-test indicators because broom::tidy renames them
  orig_names <- names(as.data.frame(x))
  looks_like_f <- any(grepl("^F$|F\\s*value|F stat", orig_names, ignore.case = TRUE))
  
  df1_col <- grep("^df$|^Df$", names(df), value = TRUE)[1]
  # For df2, look for residuals in column or in a specific row
  df2_col <- grep("df.residual|DenDF|Res.Df|Resid.\\s*Df", 
                  names(df), value = TRUE, ignore.case = TRUE)[1]
  
  # Look ahead for residual Df in "Residuals" row if not in a column per row
  resid_df_fallback <- NA_real_
  if ("term" %in% names(df)) {
    res_idx <- grep("Residual", df$term, ignore.case = TRUE)
    if (length(res_idx) > 0 && !is.na(df1_col)) {
      resid_df_fallback <- df[res_idx[1], df1_col]
    }
  }

  terms <- if ("term" %in% names(df)) df$term else rownames(df)
  
  # Filter rows: must have a statistic and not be the "Residuals" row itself
  valid_indices <- which(!is.na(df[[stat_col]]))
  if ("term" %in% names(df)) {
    valid_indices <- valid_indices[!grepl("Residual", df$term[valid_indices], ignore.case = TRUE)]
  }

  for (i in valid_indices) {
    row <- df[i, ]
    term_name <- terms[i]
    term_clean <- gsub("[^a-zA-Z0-9]", "_", trimws(term_name))
    
    p_val <- row[[p_col]]
    stat_val <- row[[stat_col]]
    df1 <- row[[df1_col]]
    df2 <- if (!is.na(df2_col)) row[[df2_col]] else resid_df_fallback
    
    # Check if it's an F-test or Chi-square
    # F-tests typically report model Comparison p-values or specific F stats
    is_f <- looks_like_f || (!is.na(stat_col) && grepl("^F$", stat_col, ignore.case = TRUE))
    
    if (is_f && !is.na(df2)) {
      formatted_str <- fmt_f(stat_val, as.integer(df1), as.integer(df2), p_val, digits = digits)
    } else {
      # Fallback to chi-square style (common for LRT, Deviance, Wald Chisq)
      formatted_str <- fmt_chi(stat_val, df1, p_val, digits = digits)
      # If the column name explicitly says it's not chi-square, we can swap later
      # but APA usually uses chi-square symbol for likelihood ratio tests anyway
      if (!is.na(stat_col) && !grepl("Chi|Chisq", stat_col, ignore.case = TRUE)) {
         # formatted_str <- gsub("\u03C7\u00B2", "Stat", formatted_str)
      }
    }
    
    # Cleaner label if it's just a row number
    display_label <- term_name
    if (term_name == as.character(i)) {
      display_label <- paste("Step", i)
    }
    
    parts_list <- list(
      statistic = format_decimal(stat_val, digits)
    )
    
    if (is_f) {
      parts_list$F_value <- format_decimal(stat_val, digits)
      parts_list$df1 <- as.character(as.integer(df1))
      if (!is.na(df2)) parts_list$df2 <- as.character(as.integer(df2))
    } else {
      parts_list$chi_sq <- format_decimal(stat_val, digits)
      parts_list$df <- as.character(as.integer(df1))
    }
    
    if (!is.na(p_val)) {
      parts_list$p <- fmt_p(p_val, include_p = FALSE)
    }
    
    stats[[idx]] <- new_stat(
      id = paste0(id_prefix, ".", term_clean),
      label = display_label,
      group = label,
      type = if (is_f) "f_test" else "chi_square",
      formatted = formatted_str,
      formatted_parts = parts_list,
      raw = list(
        statistic = stat_val,
        df1 = df1,
        df2 = df2,
        p_value = p_val,
        method = stat_col
      )
    )
    idx <- idx + 1
  }
  
  new_sync_collection(stats, label = label)
}

# --- GLM (logistic, etc.) ---
#' @export
sync_stats.glm <- function(x, id_prefix = NULL, label = NULL,
                           style = "apa7", digits = 2,
                           conf_level = 0.95, ...) {
  if (is.null(id_prefix)) {
    if (!is.null(label)) id_prefix <- tolower(gsub("[^a-zA-Z0-9]", "_", label))
    else id_prefix <- "glm"
  }
  is_logistic <- family(x)$link == "logit"
  if (is.null(label)) label <- paste(
    if (is_logistic) "Logistic" else "Generalized Linear",
    "Model"
  )
  
  coef_df <- broom::tidy(x, conf.int = TRUE, conf.level = conf_level,
                         exponentiate = is_logistic)
  glance_df <- broom::glance(x)
  
  stats <- list()
  idx <- 1
  
  # Model fit
  aic_val <- as.numeric(glance_df$AIC)
  bic_val <- as.numeric(glance_df$BIC)
  dev_val <- as.numeric(glance_df$deviance)
  null_dev <- as.numeric(glance_df$null.deviance)
  
  stats[[idx]] <- new_stat(
    id = paste0(id_prefix, ".fit"),
    label = paste(label, "- Model Fit"),
    group = label,
    type = "model_fit",
    formatted = paste0(
      "AIC = ", format_decimal(aic_val, 1),
      ", BIC = ", format_decimal(bic_val, 1),
      ", Deviance = ", format_decimal(dev_val, digits)
    ),
    formatted_parts = list(
      aic = format_decimal(aic_val, 1),
      bic = format_decimal(bic_val, 1),
      deviance = format_decimal(dev_val, digits),
      null_deviance = format_decimal(null_dev, digits),
      n = as.character(nobs(x))
    ),
    raw = list(
      aic = aic_val,
      bic = bic_val,
      deviance = dev_val,
      null_deviance = null_dev,
      n = nobs(x)
    )
  )
  idx <- idx + 1
  
  # Coefficients
  for (i in seq_len(nrow(coef_df))) {
    row <- coef_df[i, ]
    term_clean <- gsub("[^a-zA-Z0-9]", "_", row$term)
    
    est_val  <- as.numeric(row$estimate)
    se_val   <- as.numeric(row$std.error)
    stat_val <- as.numeric(row$statistic)
    p_val    <- as.numeric(row$p.value)
    ci_lo    <- as.numeric(row$conf.low)
    ci_hi    <- as.numeric(row$conf.high)
    
    if (is_logistic) {
      fmt_str <- paste0(
        "OR = ", format_decimal(est_val, digits),
        ", ", fmt_ci(ci_lo, ci_hi, digits),
        ", ", fmt_p(p_val)
      )
    } else {
      fmt_str <- fmt_coef(est_val, se_val,
                          stat_val, p_val,
                          ci_lo, ci_hi,
                          digits = digits)
    }
    
    stats[[idx]] <- new_stat(
      id = paste0(id_prefix, ".", term_clean),
      label = paste(label, "-", row$term),
      group = label,
      type = if (is_logistic) "odds_ratio" else "coefficient",
      formatted = fmt_str,
      formatted_parts = list(
        estimate = format_decimal(est_val, digits),
        se = format_decimal(se_val, digits),
        statistic = format_decimal(stat_val, digits),
        p = fmt_p(p_val, include_p = FALSE),
        ci_lower = format_decimal(ci_lo, digits),
        ci_upper = format_decimal(ci_hi, digits)
      ),
      raw = list(
        estimate = est_val,
        std_error = se_val,
        statistic = stat_val,
        p_value = p_val,
        conf_low = ci_lo,
        conf_high = ci_hi,
        exponentiated = is_logistic
      )
    )
    idx <- idx + 1
  }
  
  new_sync_collection(stats, label = label)
}

# --- Descriptive Statistics from data frame ---
#' @export
sync_stats.data.frame <- function(x, id_prefix = NULL, label = NULL,
                                  style = "apa7", digits = 2,
                                  vars = NULL, group_var = NULL, ...) {
  
  if (is.null(id_prefix)) {
    id_prefix <- if (!is.null(label)) tolower(gsub("[^a-zA-Z0-9]", "_", label)) else "df"
  }
  
  # Default group label if none provided
  group_label <- label %||% "Descriptive Statistics"
  
  if (is.null(vars)) {
    vars <- names(x)[sapply(x, is.numeric)]
  }
  
  stats <- list()
  idx <- 1
  
  # Helper to add a stat
  add_stat <- function(values, var_name, card_name, stat_label, id_suffix = "") {
    vals <- na.omit(values)
    if (length(vals) == 0) return()
    
    m <- mean(vals)
    sd_val <- sd(vals)
    med <- median(vals)
    n <- length(vals)
    
    stats[[idx]] <<- new_stat(
      id = paste0(id_prefix, ".", var_name, id_suffix),
      label = stat_label,
      group = card_name,
      type = "descriptive",
      formatted = fmt_mean_sd(m, sd_val, digits),
      formatted_parts = list(
        mean = format_decimal(m, digits),
        sd = format_decimal(sd_val, digits),
        median = format_decimal(med, digits),
        min = format_decimal(min(vals), digits),
        max = format_decimal(max(vals), digits),
        n = as.character(n)
      ),
      raw = list(
        mean = m, sd = sd_val, median = med,
        min = min(vals), max = max(vals),
        n = n, n_missing = sum(is.na(values))
      )
    )
    idx <<- idx + 1
  }
  
  if (is.null(group_var)) {
    # One card for the whole data frame, items are variables
    for (v in vars) {
      add_stat(x[[v]], v, group_label, v)
    }
  } else {
    # Grouped: "Variable by Group" card per variable, items are group levels
    for (v in vars) {
      card_name <- paste0(v, " by ", group_var)
      groups <- unique(x[[group_var]])
      for (g in groups) {
        subset_df <- x[x[[group_var]] == g, ]
        if (nrow(subset_df) > 0) {
          id_safe <- gsub("[^a-zA-Z0-9]", "_", as.character(g))
          add_stat(subset_df[[v]], v, card_name, as.character(g), paste0(".", id_safe))
        }
      }
    }
  }
  
  new_sync_collection(stats, label = group_label)
}

# --- Atomic Vector support (numeric, etc.) ---
#' @export
sync_stats.numeric <- function(x, id_prefix = NULL, label = NULL, 
                               style = "apa7", digits = 2, ...) {
  # Try to guess a name
  nm <- id_prefix
  if (is.null(nm)) {
    nm <- deparse(substitute(x))
    if (length(nm) > 1) nm <- "values"
    # Cleaner name for iris$Sepal.Width
    if (grepl("\\$", nm)) {
      parts <- strsplit(nm, "\\$")[[1]]
      nm <- parts[length(parts)]
    }
    nm <- gsub("[^a-zA-Z0-9]", "_", nm)
  }
  
  df <- data.frame(x)
  names(df) <- nm
  
  sync_stats.data.frame(df, id_prefix = id_prefix %||% nm, label = label %||% nm, 
                         style = style, digits = digits, vars = nm, ...)
}

#' @export
sync_stats.default <- function(x, ...) {
  if (is.numeric(x)) {
    return(sync_stats.numeric(x, ...))
  }
  stop("No StatSync method for object of class ", class(x)[1])
}


# ============================================================
# INTERNAL DATA STRUCTURES
# ============================================================

new_stat <- function(id, label, group, type, formatted,
                     formatted_parts = list(), raw = list(),
                     context = list()) {
  structure(
    list(
      id = id,
      label = label,
      group = group,
      type = type,
      formatted = formatted,
      formatted_parts = formatted_parts,
      raw = raw,
      context = context
    ),
    class = "statsync_stat"
  )
}

new_sync_collection <- function(stats, label = NULL) {
  structure(
    list(
      stats = stats,
      label = label,
      created = Sys.time()
    ),
    class = "statsync_collection"
  )
}

#' Combine multiple sync collections
#' @export
`+.statsync_collection` <- function(a, b) {
  new_sync_collection(
    stats = c(a$stats, b$stats),
    label = paste(
      c(a$label, b$label),
      collapse = " + "
    )
  )
}

#' Print method for collections
#' @export
print.statsync_collection <- function(x, ...) {
  cat("StatSync Collection:", x$label %||% "Unnamed", "\n")
  cat("Statistics:", length(x$stats), "\n")
  cat(strrep("-", 60), "\n")
  for (s in x$stats) {
    cat(sprintf("  [%s] %s\n", s$id, strip_markup(s$formatted)))
  }
  invisible(x)
}
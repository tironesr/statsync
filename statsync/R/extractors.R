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
    ci <- if (!is.null(x$conf.int)) as.numeric(x$conf.int) else c(NA_real_, NA_real_)
    
    # Calculate Cohen's d (approximated for two-sample unequal n)
    cohens_d <- tryCatch({
      if (grepl("Welch", x$method)) {
        NA_real_
      } else if (grepl("Two Sample", x$method)) {
        abs(t_val) * 2 / sqrt(df_val)
      } else {
        abs(t_val) / sqrt(df_val + 1)
      }
    }, error = function(e) NA_real_)
    
    stats[[1]] <- new_stat(
      id = paste0(id_prefix, ".result"),
      label = label,
      group = label,
      type = "t_test",
      formatted = fmt_t(t_val, df_val, p_val, cohens_d, ci[1], ci[2], digits),
      formatted_parts = list(
        t = format_decimal(t_val, digits),
        df = format_decimal(df_val,
                            if (!is.na(df_val) && df_val %% 1 == 0) 0 else 2),
        p = fmt_p(p_val, include_p = FALSE),
        d = if (!is.na(cohens_d)) format_decimal(cohens_d, digits) else NA,
        ci_lower = if (!is.na(ci[1])) format_decimal(ci[1], digits) else NA,
        ci_upper = if (!is.na(ci[2])) format_decimal(ci[2], digits) else NA
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
    
    n_val <- tryCatch({
      if (!is.null(x$observed)) {
        sum(x$observed)
      } else {
        NA_integer_
      }
    }, error = function(e) NA_integer_)
    
    # Cramér's V
    v_val <- tryCatch({
      if (!is.na(n_val) && !is.null(dim(x$observed))) {
        k <- min(dim(x$observed)) - 1
        if (k > 0 && n_val > 0) {
          sqrt(chi_val / (n_val * k))
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
      formatted = fmt_chi(chi_val, df_val, p_val, n_val, v_val, digits),
      formatted_parts = list(
        chi_sq = format_decimal(chi_val, digits),
        df = as.character(as.integer(df_val)),
        n = if (!is.na(n_val)) as.character(n_val) else NA,
        p = fmt_p(p_val, include_p = FALSE),
        cramers_v = if (!is.na(v_val))
          format_decimal(v_val, 3, leading_zero = FALSE) else NA
      ),
      raw = list(
        statistic = chi_val,
        df = df_val,
        p_value = p_val,
        cramers_v = v_val,
        n = n_val,
        method = x$method
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
    
  } else if (test_type == "wilcoxon") {
    stat_val  <- safe_num(x$statistic)
    p_val     <- safe_num(x$p.value)
    stat_name <- if (!is.null(x$statistic) && length(x$statistic) > 0) names(x$statistic)[1] else "W"
    if (is.null(stat_name) || is.na(stat_name)) stat_name <- "W"
    
    formatted_str <- paste0("{i}", stat_name, "{/i} = ", format_decimal(stat_val, digits))
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
        method = x$method
      )
    )
    
  } else if (test_type == "fisher") {
    p_val  <- safe_num(x$p.value)
    or_val <- if (!is.null(x$estimate)) as.numeric(x$estimate) else NA_real_
    ci     <- if (!is.null(x$conf.int)) as.numeric(x$conf.int) else c(NA_real_, NA_real_)
    
    if (!is.na(or_val)) {
      formatted_str <- paste0("{i}OR{/i} = ", format_decimal(or_val, digits))
      if (!is.na(ci[1]) && !is.na(ci[2])) {
        formatted_str <- paste0(formatted_str, ", 95% CI [", format_decimal(ci[1], digits), ", ", format_decimal(ci[2], digits), "]")
      }
      if (!is.na(p_val)) {
        formatted_str <- paste0(formatted_str, ", ", fmt_p(p_val))
      }
    } else {
      formatted_str <- fmt_p(p_val)
    }
    
    stats[[1]] <- new_stat(
      id = paste0(id_prefix, ".result"),
      label = label,
      group = label,
      type = "htest",
      formatted = formatted_str,
      formatted_parts = list(
        p = if (!is.na(p_val)) fmt_p(p_val, include_p = FALSE) else NA,
        odds_ratio = if (!is.na(or_val)) format_decimal(or_val, digits) else NA,
        ci_lower = if (!is.na(ci[1])) format_decimal(ci[1], digits) else NA,
        ci_upper = if (!is.na(ci[2])) format_decimal(ci[2], digits) else NA
      ),
      raw = list(
        p_value = p_val,
        odds_ratio = or_val,
        conf_int = ci,
        method = x$method
      )
    )
    
  } else {
    # Generic htest fallback
    stat_val <- safe_num(x$statistic)
    p_val    <- safe_num(x$p.value)
    param    <- safe_num(x$parameter)
    
    stat_name <- if (!is.null(x$statistic) && length(x$statistic) > 0) names(x$statistic)[1] else "statistic"
    if (is.null(stat_name) || is.na(stat_name) || stat_name == "") stat_name <- "statistic"
    
    formatted_str <- paste0(
      "{i}", stat_name, "{/i} = ", format_decimal(stat_val, digits)
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
                          conf_level = 0.95, table = FALSE, ...) {
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
  
  # Overall model F-test (if available)
  r_sq_sym     <- "{i}R{/i}\u00B2"
  r_sq_adj_sym <- "{i}R{/i}\u00B2{sub}adj{/sub}"

  if (!is.null(s$fstatistic)) {
    f_stat <- s$fstatistic
    f_p <- pf(f_stat["value"], f_stat["numdf"], f_stat["dendf"],
              lower.tail = FALSE)
    formatted_omnibus <- paste0(
      fmt_f(f_stat["value"], f_stat["numdf"], f_stat["dendf"], f_p,
            digits = digits),
      ", ", r_sq_sym, " = ",
      format_decimal(glance_df$r.squared, 3, leading_zero = FALSE),
      ", ", r_sq_adj_sym, " = ",
      format_decimal(glance_df$adj.r.squared, 3, leading_zero = FALSE)
    )
    parts_list <- list(
      F_value = format_decimal(f_stat["value"], digits),
      df1 = as.character(f_stat["numdf"]),
      df2 = as.character(f_stat["dendf"]),
      p = fmt_p(f_p, include_p = FALSE)
    )
    raw_list <- list(
      f_statistic = as.numeric(f_stat["value"]),
      df1 = as.numeric(f_stat["numdf"]),
      df2 = as.numeric(f_stat["dendf"]),
      p_value = as.numeric(f_p)
    )
  } else {
    formatted_omnibus <- paste0(
      r_sq_sym, " = ",
      format_decimal(glance_df$r.squared, 3, leading_zero = FALSE),
      ", ", r_sq_adj_sym, " = ",
      format_decimal(glance_df$adj.r.squared, 3, leading_zero = FALSE)
    )
    parts_list <- list()
    raw_list <- list()
  }

  parts_list$r_squared <- format_decimal(glance_df$r.squared, 3, leading_zero = FALSE)
  parts_list$adj_r_squared <- format_decimal(glance_df$adj.r.squared, 3, leading_zero = FALSE)
  parts_list$n <- as.character(nobs(x))
  parts_list$df_residual <- as.character(df_residual)

  raw_list$r_squared <- glance_df$r.squared
  raw_list$adj_r_squared <- glance_df$adj.r.squared
  raw_list$aic <- glance_df$AIC
  raw_list$bic <- glance_df$BIC
  raw_list$n <- nobs(x)
  raw_list$df_residual <- df_residual

  stats[[idx]] <- new_stat(
    id = paste0(id_prefix, ".omnibus"),
    label = paste(label, "- Overall Model"),
    group = label,
    type = "model_fit",
    formatted = formatted_omnibus,
    formatted_parts = parts_list,
    raw = raw_list
  )
  idx <- idx + 1
  
  # Individual coefficients
  for (i in seq_len(nrow(coef_df))) {
    row <- coef_df[i, ]
    term_clean <- gsub("[^a-zA-Z0-9]", "_", row$term)
    
    # Partial eta-squared for non-intercept terms
    p_eta_sq <- NA_real_
    if (row$term != "(Intercept)") {
      p_eta_sq <- (row$statistic^2) / (row$statistic^2 + df_residual)
    }
    
    # Standardized estimate (beta) post-hoc
    std_estimate <- NA_real_
    tryCatch({
      y_var <- model.response(model.frame(x))
      sd_y <- sd(y_var, na.rm = TRUE)
      
      X <- model.matrix(x)
      sd_X <- apply(X, 2, sd, na.rm = TRUE)
      
      if (row$term != "(Intercept)" && row$term %in% names(sd_X)) {
        std_estimate <- row$estimate * (sd_X[row$term] / sd_y)
      }
    }, error = function(e) NULL)
    
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
        std_estimate = if (!is.na(std_estimate)) format_decimal(std_estimate, digits) else NA,
        se = format_decimal(row$std.error, digits),
        t = format_decimal(row$statistic, digits),
        df_residual = as.character(df_residual),
        t_with_df = fmt_t_regression(row$statistic, df_residual,
                                     digits = digits),
        p = fmt_p(row$p.value, include_p = FALSE),
        ci_lower = if (!is.na(row$conf.low)) format_decimal(row$conf.low, digits) else NA,
        ci_upper = if (!is.na(row$conf.high)) format_decimal(row$conf.high, digits) else NA,
        partial_eta_sq = if (!is.na(p_eta_sq))
          format_decimal(p_eta_sq, 3, leading_zero = FALSE) else NA
      ),
      raw = list(
        estimate = row$estimate,
        std_estimate = std_estimate,
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
  
  collection <- new_sync_collection(stats, label = label)
  if (table) {
    tbl <- sync_regression_table(x, caption = paste("Regression Table:", label))
    tbl$id <- paste0("reg_table_", collection$id)
    return(list(collection, tbl))
  }
  collection
}

# --- Mixed Model (lmerTest / lme4) ---
#' @export
sync_stats.lmerModLmerTest <- function(x, id_prefix = NULL, label = NULL,
                                       style = "apa7", digits = 2,
                                       conf_level = 0.95, table = FALSE, ...) {
  collection <- sync_stats_lmer_internal(x, id_prefix, label, style, digits, conf_level, ...)
  if (table) {
    tbl <- sync_regression_table(x, caption = paste("Mixed Model Regression Table:", label))
    tbl$id <- paste0("reg_table_", collection$id)
    return(list(collection, tbl))
  }
  collection
}

#' @export
sync_stats.lmerMod <- function(x, id_prefix = NULL, label = NULL,
                               style = "apa7", digits = 2,
                               conf_level = 0.95, table = FALSE, ...) {
  collection <- sync_stats_lmer_internal(x, id_prefix, label, style, digits, conf_level, ...)
  if (table) {
    tbl <- sync_regression_table(x, caption = paste("Mixed Model Regression Table:", label))
    tbl$id <- paste0("reg_table_", collection$id)
    return(list(collection, tbl))
  }
  collection
}

sync_stats_lmer_internal <- function(x, id_prefix = NULL, label = NULL,
                                     style = "apa7", digits = 2,
                                     conf_level = 0.95, ...) {
  if (is.null(id_prefix)) {
    if (!is.null(label)) id_prefix <- tolower(gsub("[^a-zA-Z0-9]", "_", label))
    else id_prefix <- "lmer"
  }
  if (is.null(label)) label <- paste("Mixed Model:", deparse(formula(x)))
  
  glance_df <- NULL
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
  if (!is.null(glance_df)) {
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
        p = if(!is.null(row$p.value) && !is.na(row$p.value)) fmt_p(row$p.value, include_p = FALSE) else NA,
        ci_lower = if(!is.na(row$conf.low)) format_decimal(row$conf.low, digits) else NA,
        ci_upper = if(!is.na(row$conf.high)) format_decimal(row$conf.high, digits) else NA
      ),
      raw = list(
        estimate = row$estimate,
        std_error = row$std.error,
        statistic = row$statistic,
        p_value = if(is.null(row$p.value) || is.na(row$p.value)) NA_real_ else row$p.value,
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
  
  df1_col <- grep("^df$|^Df$|NumDF", names(df), value = TRUE, ignore.case = TRUE)[1]
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

  # If no statistic column is found, we cannot extract statistics
  if (is.na(stat_col)) {
    return(new_sync_collection(list(), label = label))
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
    
    p_val <- if (!is.na(p_col)) row[[p_col]] else NA_real_
    stat_val <- row[[stat_col]]
    df1 <- if (!is.na(df1_col)) row[[df1_col]] else NA_real_
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
                           conf_level = 0.95, table = FALSE, ...) {
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
        "{i}OR{/i} = ", format_decimal(est_val, digits),
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
  
  collection <- new_sync_collection(stats, label = label)
  if (table) {
    tbl <- sync_regression_table(x, caption = paste("Logistic Regression Table:", label))
    tbl$id <- paste0("reg_table_", collection$id)
    return(list(collection, tbl))
  }
  collection
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
sync_stats.aovlist <- function(x, id_prefix = NULL, label = NULL,
                               style = "apa7", digits = 2, ...) {
  if (is.null(id_prefix)) {
    if (!is.null(label)) id_prefix <- tolower(gsub("[^a-zA-Z0-9]", "_", label))
    else id_prefix <- "anova"
  }
  if (is.null(label)) label <- "ANOVA"

  # x is a list of aov models (strata)
  collections <- lapply(names(x), function(stratum_name) {
    stratum_model <- x[[stratum_name]]
    # Skip if empty or no terms
    if (is.null(stratum_model) || length(coef(stratum_model)) == 0) return(NULL)
    
    stratum_id <- paste0(id_prefix, "_", tolower(gsub("[^a-zA-Z0-9]", "_", stratum_name)))
    stratum_label <- paste0(label, " (", stratum_name, ")")
    
    tryCatch({
      sync_stats(stratum_model, id_prefix = stratum_id, label = stratum_label,
                 style = style, digits = digits, ...)
    }, error = function(e) NULL)
  })
  
  collections <- Filter(Negate(is.null), collections)
  
  if (length(collections) == 0) {
    return(new_sync_collection(list(), label = label))
  }
  
  res <- collections[[1]]
  if (length(collections) > 1) {
    for (i in 2:length(collections)) {
      res <- res + collections[[i]]
    }
  }
  res$label <- label
  res
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

# --- emmeans ---
#' @export
sync_stats.emmGrid <- function(x, id_prefix = NULL, label = NULL,
                               style = "apa7", digits = 2, ...) {
  if (is.null(id_prefix)) {
    if (!is.null(label)) id_prefix <- tolower(gsub("[^a-zA-Z0-9]", "_", label))
    else id_prefix <- "emmeans"
  }
  if (is.null(label)) label <- "Estimated Marginal Means"
  
  df <- as.data.frame(summary(x))
  stats <- list()
  idx <- 1
  
  is_z <- "z.ratio" %in% names(df)
  stat_col <- if (is_z) "z.ratio" else "t.ratio"
  
  for (i in seq_len(nrow(df))) {
    row <- df[i, ]
    contrast_name <- if ("contrast" %in% names(row)) row$contrast else paste("Row", i)
    contrast_clean <- gsub("[^a-zA-Z0-9]", "_", contrast_name)
    
    stat_val <- as.numeric(row[[stat_col]])
    p_val <- as.numeric(row$p.value)
    
    if (is_z) {
      fmt <- paste0("{i}z{/i} = ", format_decimal(stat_val, digits), ", ", fmt_p(p_val))
      parts <- list(z = format_decimal(stat_val, digits), p = fmt_p(p_val, include_p = FALSE))
    } else {
      df_val <- as.numeric(row$df)
      fmt <- fmt_t(stat_val, df_val, p_val, digits = digits)
      parts <- list(t = format_decimal(stat_val, digits), df = as.character(df_val), p = fmt_p(p_val, include_p = FALSE))
    }
    
    stats[[idx]] <- new_stat(
      id = paste0(id_prefix, ".", contrast_clean),
      label = paste(label, "-", contrast_name),
      group = label,
      type = "htest",
      formatted = fmt,
      formatted_parts = parts,
      raw = as.list(row)
    )
    idx <- idx + 1
  }
  
  new_sync_collection(stats, label = label)
}

# --- afex ANOVA ---
#' @export
sync_stats.afex_aov <- function(x, id_prefix = NULL, label = NULL,
                                style = "apa7", digits = 2, ...) {
  if (is.null(id_prefix)) id_prefix <- "afex"
  if (is.null(label)) label <- "Repeated Measures ANOVA"
  
  tab <- x$anova_table
  class(tab) <- c("anova", "data.frame")
  
  stats <- list()
  idx <- 1
  
  for (i in seq_len(nrow(tab))) {
    row <- tab[i, ]
    term <- rownames(tab)[i]
    term_clean <- gsub("[^a-zA-Z0-9]", "_", term)
    
    f_val <- row[["F"]]
    df1 <- row[["num Df"]]
    df2 <- row[["den Df"]]
    p_val <- row[["Pr(>F)"]]
    
    eta_sq <- if ("ges" %in% names(row)) row[["ges"]] else if ("pes" %in% names(row)) row[["pes"]] else NA_real_
    
    fmt <- fmt_f(f_val, df1, df2, p_val, eta_sq, partial = TRUE, digits = digits)
    
    stats[[idx]] <- new_stat(
      id = paste0(id_prefix, ".", term_clean),
      label = paste(label, "-", term),
      group = label,
      type = "anova_test",
      formatted = fmt,
      formatted_parts = list(
        F_value = format_decimal(f_val, digits),
        df1 = as.character(df1),
        df2 = as.character(df2),
        p = fmt_p(p_val, include_p = FALSE),
        eta_squared = if (!is.na(eta_sq)) format_decimal(eta_sq, 3, leading_zero = FALSE) else NA
      ),
      raw = as.list(row)
    )
    idx <- idx + 1
  }
  
  new_sync_collection(stats, label = label)
}

# --- aovlist (Base R Repeated Measures) ---
#' @export
sync_stats.aovlist <- function(x, id_prefix = NULL, label = NULL,
                               style = "apa7", digits = 2, ...) {
  if (is.null(id_prefix)) id_prefix <- "aovlist"
  if (is.null(label)) label <- "Repeated Measures ANOVA"
  
  stats <- list()
  idx <- 1
  
  for (strat_name in names(x)) {
    if (strat_name == "(Intercept)") next
    strat_model <- x[[strat_name]]
    
    tab <- summary(strat_model)[[1]]
    
    for (i in seq_len(nrow(tab))) {
      term <- trimws(rownames(tab)[i])
      if (term == "Residuals") next
      
      term_clean <- gsub("[^a-zA-Z0-9]", "_", paste0(strat_name, "_", term))
      
      f_val <- tab[i, "F value"]
      df1 <- tab[i, "Df"]
      df2 <- tab["Residuals", "Df"]
      p_val <- tab[i, "Pr(>F)"]
      
      if (is.na(f_val)) next
      
      ss_effect <- tab[i, "Sum Sq"]
      ss_resid <- tab["Residuals", "Sum Sq"]
      eta_sq <- ss_effect / (ss_effect + ss_resid)
      
      fmt <- fmt_f(f_val, df1, df2, p_val, eta_sq, partial = TRUE, digits = digits)
      
      stats[[idx]] <- new_stat(
        id = paste0(id_prefix, ".", term_clean),
        label = paste(label, "-", term, "(", strat_name, ")"),
        group = label,
        type = "anova_test",
        formatted = fmt,
        formatted_parts = list(
          F_value = format_decimal(f_val, digits),
          df1 = as.character(df1),
          df2 = as.character(df2),
          p = fmt_p(p_val, include_p = FALSE),
          eta_squared = format_decimal(eta_sq, 3, leading_zero = FALSE)
        ),
        raw = list(
          f_statistic = f_val,
          df1 = df1,
          df2 = df2,
          p_value = p_val,
          eta_squared = eta_sq
        )
      )
      idx <- idx + 1
    }
  }
  
  new_sync_collection(stats, label = label)
}

# --- lavaan SEM ---
#' @export
sync_stats.lavaan <- function(x, id_prefix = NULL, label = NULL,
                              style = "apa7", digits = 2, ...) {
  if (is.null(id_prefix)) id_prefix <- "lavaan"
  if (is.null(label)) label <- "Structural Equation Model"
  
  stats <- list()
  idx <- 1
  
  fit <- lavaan::fitMeasures(x)
  
  chi_val <- fit["chisq"]
  df_val <- fit["df"]
  p_val <- fit["pvalue"]
  cfi_val <- fit["cfi"]
  rmsea_val <- fit["rmsea"]
  srmr_val <- fit["srmr"]
  
  fmt_fit <- paste0(
    "\u03C7\u00B2(", df_val, ") = ", format_decimal(chi_val, digits), ", ",
    fmt_p(p_val), ", CFI = ", format_decimal(cfi_val, 3, leading_zero = FALSE),
    ", RMSEA = ", format_decimal(rmsea_val, 3, leading_zero = FALSE),
    ", SRMR = ", format_decimal(srmr_val, 3, leading_zero = FALSE)
  )
  
  stats[[idx]] <- new_stat(
    id = paste0(id_prefix, ".fit"),
    label = paste(label, "- Global Fit"),
    group = label,
    type = "model_fit",
    formatted = fmt_fit,
    formatted_parts = list(
      chi_sq = format_decimal(chi_val, digits),
      df = as.character(df_val),
      p = fmt_p(p_val, include_p = FALSE),
      cfi = format_decimal(cfi_val, 3, leading_zero = FALSE),
      rmsea = format_decimal(rmsea_val, 3, leading_zero = FALSE),
      srmr = format_decimal(srmr_val, 3, leading_zero = FALSE)
    ),
    raw = as.list(fit)
  )
  idx <- idx + 1
  
  ests <- lavaan::parameterEstimates(x, standardized = TRUE)
  ests <- ests[ests$op %in% c("~", "~~") & ests$lhs != ests$rhs, ]
  
  for (i in seq_len(nrow(ests))) {
    row <- ests[i, ]
    term_clean <- paste0(row$lhs, "_", switch(row$op, "~" = "on", "~~" = "with"), "_", row$rhs)
    term_label <- paste(row$lhs, row$op, row$rhs)
    
    z_val <- row$z
    p_val <- row$pvalue
    est_val <- row$est
    std_val <- row$std.all
    
    if (is.na(z_val)) next
    
    fmt_param <- paste0(
      "{i}\u03B2{/i} = ", format_decimal(std_val, digits), ", ",
      "{i}z{/i} = ", format_decimal(z_val, digits), ", ",
      fmt_p(p_val)
    )
    
    stats[[idx]] <- new_stat(
      id = paste0(id_prefix, ".", term_clean),
      label = paste(label, "-", term_label),
      group = label,
      type = "coefficient",
      formatted = fmt_param,
      formatted_parts = list(
        beta = format_decimal(std_val, digits),
        b = format_decimal(est_val, digits),
        z = format_decimal(z_val, digits),
        p = fmt_p(p_val, include_p = FALSE)
      ),
      raw = as.list(row)
    )
    idx <- idx + 1
  }
  
  new_sync_collection(stats, label = label)
}
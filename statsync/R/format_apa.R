# ============================================================
# APA-STYLE FORMATTING ENGINE
# With italic markup tags for Word rendering
#
# Tags:  {i}text{/i}  = italic
#        {b}text{/b}  = bold (reserved for future use)
#
# The plain-text version (for console/RMarkdown) strips tags.
# The Word add-in parses and applies them.
# ============================================================

#' Format a p-value in APA style
#'
#' @param p Numeric p-value
#' @param digits Decimal places (default 3)
#' @param include_p Include "p = " prefix
#' @param markup Include italic markup tags
#' @return Character string
#' @export
#' @examples
#' fmt_p(0.043)   # "{i}p{/i} = .043"
#' fmt_p(0.0003)  # "{i}p{/i} < .001"
fmt_p <- function(p, digits = 3, include_p = TRUE, markup = TRUE) {
  if (is.na(p)) return(NA_character_)
  
  threshold <- 10^(-digits)
  
  p_sym <- if (markup) "{i}p{/i}" else "p"
  prefix <- if (include_p) paste0(p_sym, " ") else ""
  
  if (p < threshold) {
    paste0(prefix, "< ", format_decimal(threshold, digits, leading_zero = FALSE))
  } else if (p > .999) {
    paste0(prefix, "> .999")
  } else {
    paste0(prefix, "= ", format_decimal(p, digits, leading_zero = FALSE))
  }
}

#' Format a decimal number
#'
#' @param x Numeric value
#' @param digits Number of decimal places
#' @param leading_zero Include leading zero for values between -1 and 1
#' @return Character string
#' @export
format_decimal <- function(x, digits = 2, leading_zero = TRUE) {
  if (is.na(x)) return(NA_character_)
  
  formatted <- formatC(x, digits = digits, format = "f")
  
  if (!leading_zero) {
    formatted <- sub("^0\\.", ".", formatted)
    formatted <- sub("^-0\\.", "-.", formatted)
  }
  
  formatted
}

#' Format a confidence interval
#'
#' @param lower Lower bound
#' @param upper Upper bound
#' @param digits Decimal places
#' @param level Confidence level (for labeling)
#' @param bracket_type "square" or "round"
#' @param markup Include italic markup tags
#' @return Character string
#' @export
fmt_ci <- function(lower, upper, digits = 2, level = 95,
                   bracket_type = "square", markup = TRUE) {
  open  <- if (bracket_type == "square") "[" else "("
  close <- if (bracket_type == "square") "]" else ")"
  
  paste0(level, "% CI ",
         open,
         format_decimal(lower, digits), ", ",
         format_decimal(upper, digits),
         close)
}

#' Format a t-test result (standalone t-test)
#'
#' @param t_value t statistic
#' @param df Degrees of freedom
#' @param p P-value
#' @param d Cohen's d (optional)
#' @param digits Decimal places for statistics
#' @param markup Include italic markup tags
#' @return Character string
#' @export
fmt_t <- function(t_value, df, p, d = NULL, digits = 2, markup = TRUE) {
  t_sym <- if (markup) "{i}t{/i}" else "t"
  d_sym <- if (markup) "{i}d{/i}" else "d"
  
  df_fmt <- if (df %% 1 == 0) format_decimal(df, 0) else format_decimal(df, 2)
  
  base <- paste0(
    t_sym, "(", df_fmt, ") = ",
    format_decimal(t_value, digits), ", ",
    fmt_p(p, markup = markup)
  )
  
  if (!is.null(d) && !is.na(d)) {
    paste0(base, ", ", d_sym, " = ", format_decimal(d, digits))
  } else {
    base
  }
}

#' Format a t-test result from a regression coefficient
#'
#' Includes df in parentheses after t, per APA guidelines for
#' reporting individual regression coefficients.
#'
#' @param t_value t statistic
#' @param df_residual Residual degrees of freedom from the model
#' @param p P-value
#' @param digits Decimal places
#' @param markup Include italic markup tags
#' @return Character string like "t(28) = -9.56"
#' @export
fmt_t_regression <- function(t_value, df_residual, p = NULL,
                             digits = 2, markup = TRUE) {
  t_sym <- if (markup) "{i}t{/i}" else "t"
  
  result <- paste0(
    t_sym, "(", df_residual, ") = ",
    format_decimal(t_value, digits)
  )
  
  if (!is.null(p)) {
    result <- paste0(result, ", ", fmt_p(p, markup = markup))
  }
  
  result
}

#' Format an F-test result
#'
#' @param f_value F statistic
#' @param df1 Numerator degrees of freedom
#' @param df2 Denominator degrees of freedom
#' @param p P-value
#' @param eta_sq Eta-squared or partial eta-squared
#' @param partial Whether eta_sq is partial
#' @param digits Decimal places
#' @param markup Include italic markup tags
#' @return Character string
#' @export
fmt_f <- function(f_value, df1, df2, p, eta_sq = NULL,
                  partial = TRUE, digits = 2, markup = TRUE) {
  f_sym <- if (markup) "{i}F{/i}" else "F"
  
  base <- paste0(
    f_sym, "(", df1, ", ", df2, ") = ",
    format_decimal(f_value, digits), ", ",
    fmt_p(p, markup = markup)
  )
  
  if (!is.null(eta_sq) && !is.na(eta_sq)) {
    if (partial) {
      # η²p — eta is Greek so not italicized, but subscript p is
      eta_label <- if (markup) "\u03B7\u00B2{i}p{/i}" else "\u03B7\u00B2p"
    } else {
      eta_label <- "\u03B7\u00B2"
    }
    paste0(base, ", ", eta_label, " = ",
           format_decimal(eta_sq, 3, leading_zero = FALSE))
  } else {
    base
  }
}

#' Format a chi-square test result
#'
#' @param chi_value Chi-square statistic
#' @param df Degrees of freedom
#' @param p P-value
#' @param v Cramér's V (optional)
#' @param digits Decimal places
#' @param markup Include italic markup tags
#' @return Character string
#' @export
fmt_chi <- function(chi_value, df, p, v = NULL, digits = 2, markup = TRUE) {
  # χ² is not italicized (Greek letter)
  # but V in Cramér's V is italic
  v_sym <- if (markup) "{i}V{/i}" else "V"
  
  base <- paste0(
    "\u03C7\u00B2(", df, ") = ",
    format_decimal(chi_value, digits), ", ",
    fmt_p(p, markup = markup)
  )
  
  if (!is.null(v) && !is.na(v)) {
    paste0(base, ", ", v_sym, " = ",
           format_decimal(v, 3, leading_zero = FALSE))
  } else {
    base
  }
}

#' Format a correlation
#'
#' @param r Correlation coefficient
#' @param p P-value (optional)
#' @param df Degrees of freedom (optional)
#' @param ci_lower Lower bound of CI (optional)
#' @param ci_upper Upper bound of CI (optional)
#' @param method "pearson", "spearman", or "kendall"
#' @param digits Decimal places
#' @param markup Include italic markup tags
#' @return Character string
#' @export
fmt_r <- function(r, p = NULL, df = NULL, ci_lower = NULL, ci_upper = NULL,
                  method = "pearson", digits = 2, markup = TRUE) {
  # r is italic for Pearson, rs for Spearman
  # τ (tau) is Greek so not italic for Kendall
  symbol <- switch(method,
                   pearson  = if (markup) "{i}r{/i}" else "r",
                   spearman = if (markup) "{i}r{/i}{i}s{/i}" else "rs",
                   kendall  = "\u03C4",  # tau, not italicized
                   if (markup) "{i}r{/i}" else "r"
  )
  
  parts <- symbol
  
  if (!is.null(df)) {
    parts <- paste0(parts, "(", df, ")")
  }
  
  parts <- paste0(parts, " = ",
                  format_decimal(r, digits, leading_zero = FALSE))
  
  if (!is.null(ci_lower) && !is.null(ci_upper)) {
    parts <- paste0(parts, ", ",
                    fmt_ci(ci_lower, ci_upper, digits, markup = markup))
  }
  
  if (!is.null(p)) {
    parts <- paste0(parts, ", ", fmt_p(p, markup = markup))
  }
  
  parts
}

#' Format a regression coefficient
#'
#' @param estimate Coefficient estimate
#' @param se Standard error (optional)
#' @param statistic t-statistic (optional)
#' @param p P-value (optional)
#' @param ci_lower Lower CI bound (optional)
#' @param ci_upper Upper CI bound (optional)
#' @param df_residual Residual df for t-test (optional, new parameter)
#' @param standardized If TRUE, uses β instead of b
#' @param digits Decimal places
#' @param markup Include italic markup tags
#' @return Character string
#' @export
fmt_coef <- function(estimate, se = NULL, statistic = NULL, p = NULL,
                     ci_lower = NULL, ci_upper = NULL,
                     df_residual = NULL,
                     standardized = FALSE, digits = 2, markup = TRUE) {
  if (standardized) {
    # β is Greek, not italicized per APA
    symbol <- "\u03B2"
  } else {
    # b is italic
    symbol <- if (markup) "{i}b{/i}" else "b"
  }
  
  se_sym <- if (markup) "{i}SE{/i}" else "SE"
  t_sym  <- if (markup) "{i}t{/i}" else "t"
  
  parts <- paste0(symbol, " = ", format_decimal(estimate, digits))
  
  if (!is.null(se)) {
    parts <- paste0(parts, ", ", se_sym, " = ", format_decimal(se, digits))
  }
  
  if (!is.null(ci_lower) && !is.null(ci_upper)) {
    parts <- paste0(parts, ", ",
                    fmt_ci(ci_lower, ci_upper, digits, markup = markup))
  }
  
  if (!is.null(statistic)) {
    if (!is.null(df_residual)) {
      # Include df in parentheses: t(28) = -9.56
      parts <- paste0(parts, ", ",
                      t_sym, "(", df_residual, ") = ",
                      format_decimal(statistic, digits))
    } else {
      # No df: t = -9.56
      parts <- paste0(parts, ", ",
                      t_sym, " = ",
                      format_decimal(statistic, digits))
    }
  }
  
  if (!is.null(p)) {
    parts <- paste0(parts, ", ", fmt_p(p, markup = markup))
  }
  
  parts
}

#' Format mean and standard deviation
#'
#' @param mean Mean value
#' @param sd Standard deviation
#' @param digits Decimal places
#' @param markup Include italic markup tags
#' @return Character string
#' @export
fmt_mean_sd <- function(mean, sd, digits = 2, markup = TRUE) {
  m_sym  <- if (markup) "{i}M{/i}" else "M"
  sd_sym <- if (markup) "{i}SD{/i}" else "SD"
  
  paste0(m_sym, " = ", format_decimal(mean, digits),
         ", ", sd_sym, " = ", format_decimal(sd, digits))
}

#' Format mean and standard error
#'
#' @param mean Mean value
#' @param se Standard error
#' @param digits Decimal places
#' @param markup Include italic markup tags
#' @return Character string
#' @export
fmt_mean_se <- function(mean, se, digits = 2, markup = TRUE) {
  m_sym  <- if (markup) "{i}M{/i}" else "M"
  se_sym <- if (markup) "{i}SE{/i}" else "SE"
  
  paste0(m_sym, " = ", format_decimal(mean, digits),
         ", ", se_sym, " = ", format_decimal(se, digits))
}

#' Strip markup tags for plain text output
#'
#' Removes {i}{/i} and {b}{/b} tags for console/RMarkdown use.
#'
#' @param x Character string with markup tags
#' @return Character string without tags
#' @export
strip_markup <- function(x) {
  if (is.na(x)) return(NA_character_)
  x <- gsub("\\{i\\}", "", x)
  x <- gsub("\\{/i\\}", "", x)
  x <- gsub("\\{b\\}", "", x)
  x <- gsub("\\{/b\\}", "", x)
  x
}
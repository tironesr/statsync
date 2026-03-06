// ============================================================
// APA DEFAULT FIELD CONFIGURATIONS
//
// Defines which fields are available and which are checked
// by default for each statistical test type.
// ============================================================

export interface FieldOption {
  key: string;           // matches formatted_parts key
  label: string;         // human-readable label
  apaDefault: boolean;   // checked by default per APA 7
  category: "core" | "effect_size" | "ci" | "model_fit";
}

export interface TestTypeConfig {
  label: string;
  icon: string;
  fields: FieldOption[];
  // How to assemble checked fields into a formatted string
  assemblyOrder: string[];
}

export const FIELD_CONFIGS: Record<string, TestTypeConfig> = {
  t_test: {
    label: "t-test",
    icon: "📊",
    fields: [
      { key: "t", label: "Test statistic (t)", apaDefault: true, category: "core" },
      { key: "df", label: "Degrees of freedom", apaDefault: true, category: "core" },
      { key: "p", label: "p-value", apaDefault: true, category: "core" },
      { key: "d", label: "Cohen's d", apaDefault: true, category: "effect_size" },
      { key: "ci_lower", label: "95% CI (lower)", apaDefault: false, category: "ci" },
      { key: "ci_upper", label: "95% CI (upper)", apaDefault: false, category: "ci" },
    ],
    assemblyOrder: ["t", "df", "p", "d", "ci_lower"],
  },

  f_test: {
    label: "F-test / ANOVA",
    icon: "📈",
    fields: [
      { key: "F_value", label: "Test statistic (F)", apaDefault: true, category: "core" },
      { key: "df1", label: "df numerator", apaDefault: true, category: "core" },
      { key: "df2", label: "df denominator", apaDefault: true, category: "core" },
      { key: "p", label: "p-value", apaDefault: true, category: "core" },
      { key: "partial_eta_sq", label: "Partial η²", apaDefault: true, category: "effect_size" },
      { key: "eta_sq", label: "η² (non-partial)", apaDefault: false, category: "effect_size" },
    ],
    assemblyOrder: ["F_value", "df1", "df2", "p", "partial_eta_sq"],
  },

  coefficient: {
    label: "Regression Coefficient",
    icon: "📉",
    fields: [
      { key: "estimate", label: "Estimate (b)", apaDefault: true, category: "core" },
      { key: "se", label: "Standard error", apaDefault: true, category: "core" },
      { key: "ci_lower", label: "95% CI", apaDefault: true, category: "ci" },
      { key: "t", label: "Test statistic (t)", apaDefault: true, category: "core" },
      { key: "df_residual", label: "Degrees of freedom", apaDefault: true, category: "core" },
      { key: "p", label: "p-value", apaDefault: true, category: "core" },
      { key: "partial_eta_sq", label: "Partial η²", apaDefault: false, category: "effect_size" },
    ],
    assemblyOrder: ["estimate", "se", "ci_lower", "t", "df_residual", "p", "partial_eta_sq"],
  },

  model_fit: {
    label: "Model Fit",
    icon: "🎯",
    fields: [
      { key: "F_value", label: "F statistic", apaDefault: true, category: "core" },
      { key: "df1", label: "df numerator", apaDefault: true, category: "core" },
      { key: "df2", label: "df denominator", apaDefault: true, category: "core" },
      { key: "p", label: "p-value", apaDefault: true, category: "core" },
      { key: "r_squared", label: "R²", apaDefault: true, category: "effect_size" },
      { key: "adj_r_squared", label: "Adjusted R²", apaDefault: true, category: "effect_size" },
      { key: "aic", label: "AIC", apaDefault: false, category: "model_fit" },
      { key: "bic", label: "BIC", apaDefault: false, category: "model_fit" },
      { key: "n", label: "Sample size (N)", apaDefault: false, category: "core" },
    ],
    assemblyOrder: ["F_value", "df1", "df2", "p", "r_squared", "adj_r_squared", "aic", "bic", "n"],
  },

  correlation: {
    label: "Correlation",
    icon: "🔗",
    fields: [
      { key: "r", label: "Correlation (r)", apaDefault: true, category: "core" },
      { key: "df", label: "Degrees of freedom", apaDefault: true, category: "core" },
      { key: "p", label: "p-value", apaDefault: true, category: "core" },
      { key: "ci_lower", label: "95% CI", apaDefault: false, category: "ci" },
    ],
    assemblyOrder: ["r", "df", "p", "ci_lower"],
  },

  chi_square: {
    label: "Chi-Square",
    icon: "📋",
    fields: [
      { key: "chi_sq", label: "χ² statistic", apaDefault: true, category: "core" },
      { key: "df", label: "Degrees of freedom", apaDefault: true, category: "core" },
      { key: "p", label: "p-value", apaDefault: true, category: "core" },
      { key: "cramers_v", label: "Cramér's V", apaDefault: true, category: "effect_size" },
    ],
    assemblyOrder: ["chi_sq", "df", "p", "cramers_v"],
  },

  odds_ratio: {
    label: "Odds Ratio",
    icon: "⚖️",
    fields: [
      { key: "estimate", label: "Odds Ratio (OR)", apaDefault: true, category: "core" },
      { key: "ci_lower", label: "95% CI", apaDefault: true, category: "ci" },
      { key: "p", label: "p-value", apaDefault: true, category: "core" },
      { key: "se", label: "Standard error", apaDefault: false, category: "core" },
      { key: "statistic", label: "z statistic", apaDefault: false, category: "core" },
    ],
    assemblyOrder: ["estimate", "ci_lower", "p", "se", "statistic"],
  },

  descriptive: {
    label: "Descriptive Statistics",
    icon: "📊",
    fields: [
      { key: "mean", label: "Mean (M)", apaDefault: true, category: "core" },
      { key: "sd", label: "Standard deviation (SD)", apaDefault: true, category: "core" },
      { key: "median", label: "Median", apaDefault: false, category: "core" },
      { key: "min", label: "Minimum", apaDefault: false, category: "core" },
      { key: "max", label: "Maximum", apaDefault: false, category: "core" },
      { key: "n", label: "Sample size (n)", apaDefault: false, category: "core" },
    ],
    assemblyOrder: ["mean", "sd", "n", "median", "min", "max"],
  },
};

/**
  * Get field config for a stat type, with fallback to generic.
*/
export function getFieldConfig(statType: string): TestTypeConfig {
  return FIELD_CONFIGS[statType] || {
    label: statType,
    icon: "📌",
    fields: [],
    assemblyOrder: [],
  };
}
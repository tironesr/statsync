// ============================================================
// FORMAT ASSEMBLER
//
// Builds formatted output strings based on which fields
// the user has checked in the UI.
// ============================================================

import { StatisticEntry } from "../models/types";
import { FieldOption } from "../models/field-configs";

/**
 * Assemble a formatted string from selected fields and a stat entry.
 */
export function assembleFormatted(
  stat: StatisticEntry,
  selectedFields: string[],
  assemblyOrder: string[]
): string {
  const parts = stat.formatted_parts;
  if (!parts) return stat.formatted;

  // Sort selected fields by assembly order
  const ordered = assemblyOrder.filter((key) => selectedFields.includes(key));

  const pieces: string[] = [];

  for (const key of ordered) {
    const value = parts[key];
    if (value === null || value === undefined || value === "NA") continue;

    switch (key) {
      // --- t-test ---
      case "t":
        if (selectedFields.includes("df") && parts["df"]) {
          pieces.push(`{i}t{/i}(${parts["df"]}) = ${value}`);
        } else if (selectedFields.includes("df_residual") && parts["df_residual"]) {
          pieces.push(`{i}t{/i}(${parts["df_residual"]}) = ${value}`);
        } else {
          pieces.push(`{i}t{/i} = ${value}`);
        }
        break;

      // Skip df if already included with t
      case "df":
        if (!selectedFields.includes("t") && !selectedFields.includes("F_value")) {
          pieces.push(`df = ${value}`);
        }
        break;

      case "df_residual":
        // Only standalone if t not selected
        if (!selectedFields.includes("t")) {
          pieces.push(`df = ${value}`);
        }
        // Otherwise it's embedded in the t(df) format
        break;

      // --- F-test ---
      case "F_value":
        if (selectedFields.includes("df1") && selectedFields.includes("df2") &&
          parts["df1"] && parts["df2"]) {
          pieces.push(`{i}F{/i}(${parts["df1"]}, ${parts["df2"]}) = ${value}`);
        } else {
          pieces.push(`{i}F{/i} = ${value}`);
        }
        break;

      case "df1":
      case "df2":
        // Skip — included with F if both selected
        if (!selectedFields.includes("F_value")) {
          pieces.push(`df${key.slice(-1)} = ${value}`);
        }
        break;

      // --- p-value ---
      case "p":
        pieces.push(`{i}p{/i} ${value}`);
        break;

      // --- Coefficient ---
      case "estimate":
        if (stat.type === "odds_ratio") {
          pieces.push(`OR = ${value}`);
        } else {
          pieces.push(`{i}b{/i} = ${value}`);
        }
        break;

      case "se":
        pieces.push(`{i}SE{/i} = ${value}`);
        break;

      // --- CI — combine lower and upper ---
      case "ci_lower":
        if (parts["ci_upper"] && selectedFields.includes("ci_lower")) {
          pieces.push(`95% CI [${parts["ci_lower"]}, ${parts["ci_upper"]}]`);
        }
        break;

      case "ci_upper":
        // Handled with ci_lower
        break;

      // --- Effect sizes ---
      case "r":
        if (selectedFields.includes("df") && parts["df"]) {
          pieces.push(`{i}r{/i}(${parts["df"]}) = ${value}`);
        } else {
          pieces.push(`{i}r{/i} = ${value}`);
        }
        break;

      case "d":
        pieces.push(`{i}d{/i} = ${value}`);
        break;

      case "r_squared":
        pieces.push(`{i}R{/i}² = ${value}`);
        break;

      case "adj_r_squared":
        pieces.push(`{i}R{/i}²adj = ${value}`);
        break;

      case "partial_eta_sq":
        pieces.push(`η²{i}p{/i} = ${value}`);
        break;

      case "eta_sq":
        pieces.push(`η² = ${value}`);
        break;

      case "chi_sq":
        if (selectedFields.includes("df") && parts["df"]) {
          pieces.push(`χ²(${parts["df"]}) = ${value}`);
        } else {
          pieces.push(`χ² = ${value}`);
        }
        break;

      case "cramers_v":
        pieces.push(`{i}V{/i} = ${value}`);
        break;

      // --- Descriptive ---
      case "mean":
        pieces.push(`{i}M{/i} = ${value}`);
        break;

      case "sd":
        pieces.push(`{i}SD{/i} = ${value}`);
        break;

      case "median":
        pieces.push(`Mdn = ${value}`);
        break;

      case "min":
        pieces.push(`Min = ${value}`);
        break;

      case "max":
        pieces.push(`Max = ${value}`);
        break;

      case "n":
        pieces.push(`{i}N{/i} = ${value}`);
        break;

      case "statistic":
        if (stat.type === "f_test") {
          pieces.push(`{i}F{/i} = ${value}`);
        } else if (stat.type === "chi_square") {
          pieces.push(`χ² = ${value}`);
        } else if (stat.type === "t_test" || stat.type === "coefficient") {
          pieces.push(`{i}t{/i} = ${value}`);
        } else {
          pieces.push(`{i}z{/i} = ${value}`);
        }
        break;

      default:
        pieces.push(`${key} = ${value}`);
        break;
    }
  }

  return pieces.join(", ");
}
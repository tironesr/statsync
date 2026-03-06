// ============================================================
// TYPE DEFINITIONS — mirrors the JSON schema
// ============================================================

export interface StatSyncProject {
  version: string;
  project: {
    name: string;
    r_script?: string;
    hash?: string;
  };
  generated_at: string;
  options: FormatOptions;
  statistics: StatisticEntry[];
  tables: TableEntry[];
}

export interface FormatOptions {
  style: "apa7" | "apa6" | "vancouver" | "custom";
  decimal_places: number;
  leading_zero: boolean;
  thousands_separator: boolean;
}

export interface StatisticEntry {
  id: string;
  label: string;
  group: string;
  type: StatType;
  formatted: string;
  formatted_parts: Record<string, string | null>;
  raw: Record<string, any>;
  context?: {
    model_call?: string;
    r_object?: string;
    line_number?: number;
  };
}

export type StatType =
  | "t_test"
  | "f_test"
  | "chi_square"
  | "correlation"
  | "coefficient"
  | "model_fit"
  | "mean_diff"
  | "odds_ratio"
  | "descriptive"
  | "custom";

export interface TableEntry {
  id: string;
  caption: string;
  note?: string;
  headers: TableHeader[][];
  rows: TableRow[];
  style: TableStyle;
}

export interface TableHeader {
  label: string;
  italic?: boolean;
  span?: number;
}

export interface TableRow {
  cells: TableCell[];
  is_header?: boolean;
  border_bottom?: boolean;
}

export interface TableCell {
  value: string;
  stat_id?: string;
  bold?: boolean;
  italic?: boolean;
  indent?: number;
}

export interface TableStyle {
  apa_table: boolean;
  font_size: number;
  font_family: string;
}

// Tracks which statistics are linked in the document
export interface LinkedStat {
  stat_id: string;
  bookmark_name: string;
  insert_mode: "full" | "part";
  part_key?: string;
  last_value: string;
  last_synced: string;
}

export interface DocumentLinks {
  file_source: string;
  links: LinkedStat[];
}
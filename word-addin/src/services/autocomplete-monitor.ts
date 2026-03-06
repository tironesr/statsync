// ============================================================
// AUTOCOMPLETE MONITOR
//
// Polls the Word document cursor position and detects when the
// user types {{ to open an autocomplete search. As the user
// continues typing after {{, the suggestions filter by label
// substring match. Selecting a suggestion replaces everything
// from {{ to the cursor with the formatted statistic.
// ============================================================

import { StatisticEntry } from "../models/types";
import { getFieldConfig } from "../models/field-configs";

export interface AutocompleteSuggestion {
  stat: StatisticEntry;
  /** The full trigger text to replace (from {{ to cursor, e.g. "{{Trans") */
  matchedText: string;
  /** Display label for the suggestion */
  displayLabel: string;
  /** Short formatted preview */
  preview: string;
  /** Icon for the stat type */
  icon: string;
}

export type SuggestionsCallback = (
  suggestions: AutocompleteSuggestion[],
  triggerText: string
) => void;

export class AutocompleteMonitor {
  private pollInterval: number | null = null;
  private callbacks: SuggestionsCallback[] = [];
  private statistics: StatisticEntry[] = [];
  private lastTrigger: string | null = null;
  private ignoredPrefix: string | null = null;
  private isPolling: boolean = false;

  /** Poll interval in ms */
  private static readonly POLL_MS = 500;

  /**
   * Update the statistics pool that the monitor matches against.
   */
  setStatistics(stats: StatisticEntry[]): void {
    this.statistics = stats;
  }

  /**
   * Register a callback for when suggestions change.
   */
  onSuggestions(callback: SuggestionsCallback): void {
    this.callbacks.push(callback);
  }

  /**
   * Start polling the document cursor.
   */
  start(): void {
    if (this.pollInterval !== null) return;

    this.pollInterval = window.setInterval(() => {
      this.poll();
    }, AutocompleteMonitor.POLL_MS);
  }

  /**
   * Stop polling.
   */
  stop(): void {
    if (this.pollInterval !== null) {
      window.clearInterval(this.pollInterval);
      this.pollInterval = null;
    }
  }

  /**
   * Force-dismiss: clear suggestions immediately.
   */
  dismiss(): void {
    this.lastTrigger = null;
    this.notifyCallbacks([], "");
  }

  /**
   * Inform monitor to ignore the current active trigger text.
   * Useful when user manually dismisses the popup via ESC.
   */
  ignoreCurrent(): void {
    this.ignoredPrefix = this.lastTrigger;
  }

  /**
   * Poll the Word document for the text before the cursor.
   */
  private async poll(): Promise<void> {
    // Prevent overlapping polls
    if (this.isPolling) return;
    if (this.statistics.length === 0) return;

    this.isPolling = true;

    try {
      const result = await this.getTextBeforeCursor();

      // No open {{ found — dismiss any active popup
      if (!result) {
        if (this.lastTrigger !== null) {
          this.lastTrigger = null;
          this.ignoredPrefix = null;
          this.notifyCallbacks([], "");
        }
        this.isPolling = false;
        return;
      }

      // If user dismissed this exact trigger logic, don't reopen
      if (this.ignoredPrefix !== null && result.fullMatch.startsWith(this.ignoredPrefix)) {
        this.lastTrigger = result.fullMatch; // prevent dupe checks
        this.isPolling = false;
        return;
      }

      // If it's a new trigger, clear ignored state
      if (this.ignoredPrefix !== null && !result.fullMatch.startsWith(this.ignoredPrefix)) {
        this.ignoredPrefix = null;
      }

      // Deduplicate: don't re-fire if same trigger
      if (result.fullMatch === this.lastTrigger) {
        this.isPolling = false;
        return;
      }
      this.lastTrigger = result.fullMatch;

      const suggestions = this.matchStatistics(
        result.searchQuery,
        result.fullMatch
      );
      this.notifyCallbacks(suggestions, result.fullMatch);
    } catch {
      // Silently ignore polling errors (e.g., Word context lost)
    } finally {
      this.isPolling = false;
    }
  }

  /**
   * Read the text before the cursor and look for an open {{ pattern.
   *
   * Detects {{ followed by optional search text (with no closing }}).
   * For example:
   *   "some text {{" → searchQuery="", fullMatch="{{"
   *   "some text {{Trans" → searchQuery="Trans", fullMatch="{{Trans"
   *   "some text {{Transmission Test}}" → null (closed bracket, not active)
   */
  private async getTextBeforeCursor(): Promise<{
    searchQuery: string;
    fullMatch: string;
  } | null> {
    return new Promise((resolve) => {
      Word.run(async (context) => {
        const selection = context.document.getSelection();

        // Get the paragraph containing the cursor
        const paragraph = selection.paragraphs.getFirst();
        paragraph.load("text");

        // Get the range from paragraph start to cursor
        const rangeBeforeCursor = paragraph
          .getRange(Word.RangeLocation.start)
          .expandTo(selection.getRange(Word.RangeLocation.start));
        rangeBeforeCursor.load("text");

        await context.sync();

        const textBefore = rangeBeforeCursor.text || "";

        // Look for an open {{ that hasn't been closed with }}
        // Match {{ followed by any text that does NOT contain }}
        const match = textBefore.match(/\{\{([^}]*)$/);

        if (match) {
          resolve({
            searchQuery: match[1].trim(),
            fullMatch: match[0], // everything from {{ to end
          });
        } else {
          resolve(null);
        }
      }).catch(() => {
        resolve(null);
      });
    });
  }

  /**
   * Match statistics by label.
   * - Empty query: return all statistics
   * - Non-empty query: filter by case-insensitive substring match on label
   */
  private matchStatistics(
    searchQuery: string,
    fullMatch: string
  ): AutocompleteSuggestion[] {
    const query = searchQuery.toLowerCase();
    const suggestions: AutocompleteSuggestion[] = [];

    for (const stat of this.statistics) {
      const labelLower = stat.label.toLowerCase();

      // If no query yet (just typed {{), show all; otherwise filter
      if (query.length === 0 || labelLower.includes(query)) {
        const config = getFieldConfig(stat.type);

        suggestions.push({
          stat,
          matchedText: fullMatch,
          displayLabel: stat.label,
          preview: this.stripMarkup(stat.formatted),
          icon: config.icon,
        });
      }
    }

    // Sort: exact matches first, then starts-with, then contains
    if (query.length > 0) {
      suggestions.sort((a, b) => {
        const aLabel = a.stat.label.toLowerCase();
        const bLabel = b.stat.label.toLowerCase();

        const aExact = aLabel === query ? 0 : 1;
        const bExact = bLabel === query ? 0 : 1;
        if (aExact !== bExact) return aExact - bExact;

        const aStarts = aLabel.startsWith(query) ? 0 : 1;
        const bStarts = bLabel.startsWith(query) ? 0 : 1;
        return aStarts - bStarts;
      });
    }

    return suggestions;
  }

  private stripMarkup(text: string): string {
    return text.replace(/\{\/?(i|b)\}/g, "");
  }

  private notifyCallbacks(
    suggestions: AutocompleteSuggestion[],
    triggerText: string
  ): void {
    this.callbacks.forEach((cb) => cb(suggestions, triggerText));
  }

  dispose(): void {
    this.stop();
    this.callbacks = [];
    this.statistics = [];
  }
}

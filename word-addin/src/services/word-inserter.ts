import {
  StatisticEntry,
  TableEntry,
  LinkedStat,
  DocumentLinks,
} from "../models/types";
import { assembleFormatted } from "./format-assembler";
import { getFieldConfig } from "../models/field-configs";

// Represents a segment of text with formatting
interface TextSegment {
  text: string;
  italic: boolean;
  bold: boolean;
}

export class WordInserter {
  private links: DocumentLinks = { file_source: "", links: [] };

  /**
   * Parse markup tags into formatted segments.
   * Handles {i}...{/i} for italic and {b}...{/b} for bold.
   */
  parseMarkup(input: string): TextSegment[] {
    const segments: TextSegment[] = [];
    let remaining = input;
    let currentItalic = false;
    let currentBold = false;

    // Regex to find the next tag
    const tagRegex = /\{(\/?)([ib])\}/;

    while (remaining.length > 0) {
      const match = tagRegex.exec(remaining);

      if (!match) {
        // No more tags — rest is plain text
        if (remaining.length > 0) {
          segments.push({
            text: remaining,
            italic: currentItalic,
            bold: currentBold,
          });
        }
        break;
      }

      // Text before the tag
      if (match.index > 0) {
        segments.push({
          text: remaining.substring(0, match.index),
          italic: currentItalic,
          bold: currentBold,
        });
      }

      // Process the tag
      const isClosing = match[1] === "/";
      const tagType = match[2];

      if (tagType === "i") {
        currentItalic = !isClosing;
      } else if (tagType === "b") {
        currentBold = !isClosing;
      }

      // Move past the tag
      remaining = remaining.substring(match.index + match[0].length);
    }

    // Merge adjacent segments with same formatting
    const merged: TextSegment[] = [];
    for (const seg of segments) {
      if (seg.text.length === 0) continue;

      const last = merged[merged.length - 1];
      if (last && last.italic === seg.italic && last.bold === seg.bold) {
        last.text += seg.text;
      } else {
        merged.push({ ...seg });
      }
    }

    return merged;
  }

  /**
   * Strip markup tags for plain text.
   */
  stripMarkup(input: string): string {
    return input.replace(/\{\/?(i|b)\}/g, "");
  }

  /**
   * Insert a formatted statistic at the cursor with proper italics.
   */
  async insertStatistic(
    stat: StatisticEntry,
    mode: "full" | "part" = "full",
    partKey?: string
  ): Promise<void> {
    await Word.run(async (context) => {
      const range = context.document.getSelection();

      const rawText =
        mode === "full"
          ? stat.formatted
          : stat.formatted_parts[partKey!] || stat.formatted;

      const segments = this.parseMarkup(rawText);
      const plainText = this.stripMarkup(rawText);

      // Insert a content control first
      const cc = range.insertContentControl();
      cc.tag = `statsync:${stat.id}${mode === "part" ? ":" + partKey : ""}`;
      cc.title = stat.label;
      cc.appearance = Word.ContentControlAppearance.hidden;
      cc.color = "#4CAF50";

      // Clear the content control and insert formatted segments
      cc.clear();

      for (const segment of segments) {
        // Insert inline text directly into the content control
        const insertedRange = cc.insertText(segment.text, Word.InsertLocation.end);

        // Apply formatting
        insertedRange.font.italic = segment.italic;
        insertedRange.font.bold = segment.bold;
        insertedRange.font.name = "Times New Roman";
        insertedRange.font.size = 12;
      }

      // Move cursor to the end of the inserted content control so user can keep typing
      cc.getRange(Word.RangeLocation.after).select();

      await context.sync();

      // Track the link
      this.links.links.push({
        stat_id: stat.id,
        bookmark_name: cc.tag,
        insert_mode: mode,
        part_key: partKey,
        last_value: plainText,
        last_synced: new Date().toISOString(),
      });
    });
  }

  /**
   * Insert a publication-ready table at the cursor.
   */
  async insertTable(tableData: TableEntry): Promise<void> {
    await Word.run(async (context) => {
      const range = context.document.getSelection();
      const body = context.document.body;

      const allHeaders = tableData.headers.flat();
      const numCols = tableData.rows[0]?.cells.length || allHeaders.length;
      const numHeaderRows = tableData.headers.length;
      const numDataRows = tableData.rows.length;
      const totalRows = numHeaderRows + numDataRows;

      // Insert caption (APA style)
      if (tableData.caption) {
        const captionPara = range.insertParagraph(
          "",
          Word.InsertLocation.before
        );
        const tableLabel = captionPara.insertText(
          "Table ",
          Word.InsertLocation.end
        );
        tableLabel.font.bold = true;
        tableLabel.font.italic = false;
        tableLabel.font.name = "Times New Roman";

        const captionText = captionPara.insertText(
          `\n${tableData.caption}`,
          Word.InsertLocation.end
        );
        captionText.font.italic = true;
        captionText.font.bold = false;
        captionText.font.name = "Times New Roman";

        captionPara.spaceAfter = 6;
      }

      // Create the table
      const table = body.insertTable(
        totalRows,
        numCols,
        Word.InsertLocation.end,
        [[]]
      );

      const fontSize = tableData.style?.font_size || 10;
      const fontFamily = tableData.style?.font_family || "Times New Roman";

      table.font.size = fontSize;
      table.font.name = fontFamily;
      table.alignment = Word.Alignment.centered;

      // APA borders
      if (tableData.style?.apa_table) {
        table.getBorder(Word.BorderLocation.all).type = Word.BorderType.none;
        // Top and bottom heavy borders would be set here
        // Word JS API has limited border control
      }

      // Fill header rows
      for (
        let headerIdx = 0;
        headerIdx < tableData.headers.length;
        headerIdx++
      ) {
        const headerRow = tableData.headers[headerIdx];
        let colIdx = 0;
        for (const header of headerRow) {
          if (colIdx < numCols) {
            const cell = table.getCell(headerIdx, colIdx);

            // Parse header for italic markup
            const segments = this.parseMarkup(header.label);
            cell.value = ""; // clear default

            for (const segment of segments) {
              const r = cell.body.insertText(
                segment.text,
                Word.InsertLocation.end
              );
              r.font.bold = true;
              r.font.italic = segment.italic || (header.italic ?? false);
              r.font.name = fontFamily;
              r.font.size = fontSize;
            }

            cell.horizontalAlignment = Word.Alignment.centered;
            colIdx += header.span || 1;
          }
        }
      }

      // Fill data rows
      for (let rowIdx = 0; rowIdx < tableData.rows.length; rowIdx++) {
        const rowData = tableData.rows[rowIdx];
        const tableRowIdx = numHeaderRows + rowIdx;

        for (
          let cellIdx = 0;
          cellIdx < rowData.cells.length && cellIdx < numCols;
          cellIdx++
        ) {
          const cellData = rowData.cells[cellIdx];
          const cell = table.getCell(tableRowIdx, cellIdx);

          // Parse cell content for markup
          const segments = this.parseMarkup(cellData.value || "");
          cell.value = ""; // clear

          for (const segment of segments) {
            const r = cell.body.insertText(
              segment.text,
              Word.InsertLocation.end
            );
            r.font.italic = segment.italic || (cellData.italic ?? false);
            r.font.bold = segment.bold || (cellData.bold ?? false);
            r.font.name = fontFamily;
            r.font.size = fontSize;
          }

          if (cellData.indent) {
            cell.body.paragraphs.getFirst().leftIndent =
              cellData.indent * 12;
          }

          if (cellIdx > 0) {
            cell.horizontalAlignment = Word.Alignment.centered;
          }

          // Track linked cells
          if (cellData.stat_id) {
            this.links.links.push({
              stat_id: cellData.stat_id,
              bookmark_name: `table:${tableData.id}:${tableRowIdx}:${cellIdx}`,
              insert_mode: "part",
              last_value: this.stripMarkup(cellData.value || ""),
              last_synced: new Date().toISOString(),
            });
          }
        }
      }

      // Table note
      if (tableData.note) {
        const noteParaRange = table.insertParagraph(
          "",
          Word.InsertLocation.after
        );

        const noteLabel = noteParaRange.insertText(
          "Note. ",
          Word.InsertLocation.end
        );
        noteLabel.font.italic = true;
        noteLabel.font.size = fontSize - 1;
        noteLabel.font.name = fontFamily;

        const noteText = noteParaRange.insertText(
          tableData.note,
          Word.InsertLocation.end
        );
        noteText.font.italic = false;
        noteText.font.size = fontSize - 1;
        noteText.font.name = fontFamily;
      }

      await context.sync();
    });
  }

  /**
   * Update all linked statistics in the document.
   */
  async updateAllLinks(
    getStatistic: (id: string) => StatisticEntry | undefined
  ): Promise<{ updated: number; failed: number; unchanged: number }> {
    const result = { updated: 0, failed: 0, unchanged: 0 };

    await Word.run(async (context) => {
      const contentControls = context.document.contentControls;
      contentControls.load("items");
      await context.sync();

      for (const cc of contentControls.items) {
        cc.load("tag,title,text");
      }
      await context.sync();

      for (const cc of contentControls.items) {
        if (!cc.tag?.startsWith("statsync:")) continue;

        const tagParts = cc.tag.replace("statsync:", "").split(":");
        const statId = tagParts[0];
        const partKey = tagParts[1];

        const stat = getStatistic(statId);
        if (!stat) {
          if (cc.text.trim() === "[Removed from Model]") {
            result.unchanged++;
          } else {
            cc.clear();
            const r = cc.insertText("[Removed from Model]", Word.InsertLocation.end);
            r.font.color = "red";
            r.font.bold = true;
            r.font.italic = false;
            r.font.name = "Times New Roman";
            r.font.size = 12;
            result.updated++;
          }
          continue;
        }

        let rawText = stat.formatted;
        if (partKey) {
          rawText = stat.formatted_parts[partKey] || stat.formatted;
        } else {
          // Check if custom format config exists in Word Document Settings
          const customFieldsStr = Office.context.document.settings.get(`statsync_format_${statId}`);
          if (customFieldsStr) {
            try {
              const fields = JSON.parse(customFieldsStr);
              const config = getFieldConfig(stat.type);
              rawText = assembleFormatted(stat, fields, config.assemblyOrder);
            } catch (e) {
              console.error("Failed to assemble custom format:", e);
              rawText = stat.formatted;
            }
          }
        }

        const newPlainText = this.stripMarkup(rawText);

        if (cc.text.trim() === newPlainText.trim()) {
          result.unchanged++;
          continue;
        }

        // Re-insert with formatting
        cc.clear();
        const segments = this.parseMarkup(rawText);

        for (const segment of segments) {
          const insertedRange = cc.insertText(segment.text, Word.InsertLocation.end);

          insertedRange.font.italic = segment.italic;
          insertedRange.font.bold = segment.bold;
          insertedRange.font.name = "Times New Roman";
          insertedRange.font.size = 12;
        }

        result.updated++;
      }

      await context.sync();
    });

    return result;
  }

  /**
   * Replace the trigger text before the cursor with a formatted statistic.
   * Used by inline autocomplete: deletes the typed model name and inserts
   * the full APA-formatted content control in its place.
   */
  async replaceTextAndInsert(
    triggerText: string,
    stat: StatisticEntry,
    mode: "full" | "part" = "full",
    partKey?: string
  ): Promise<void> {
    await Word.run(async (context) => {
      const selection = context.document.getSelection();

      // Get the paragraph containing the cursor
      const paragraph = selection.paragraphs.getFirst();
      paragraph.load("text");

      // Get range from paragraph start to cursor
      const rangeBeforeCursor = paragraph
        .getRange(Word.RangeLocation.start)
        .expandTo(selection.getRange(Word.RangeLocation.start));
      rangeBeforeCursor.load("text");

      await context.sync();

      const textBefore = rangeBeforeCursor.text || "";

      // Find the trigger text at the end of the text before cursor
      const triggerIndex = textBefore.lastIndexOf(triggerText);
      if (triggerIndex === -1) {
        // Fallback: just insert at cursor
        await this.insertStatistic(stat, mode, partKey);
        return;
      }

      // Search for the trigger text in the paragraph and delete it
      const searchResults = paragraph.search(triggerText, {
        matchCase: true,
        matchWholeWord: false,
      });
      searchResults.load("items");
      await context.sync();

      // Find the last occurrence (closest to cursor)
      if (searchResults.items.length > 0) {
        const targetRange = searchResults.items[searchResults.items.length - 1];

        // Build the formatted text
        const rawText =
          mode === "full"
            ? stat.formatted
            : stat.formatted_parts[partKey!] || stat.formatted;

        const segments = this.parseMarkup(rawText);
        const plainText = this.stripMarkup(rawText);

        // Replace the trigger text with a content control
        const cc = targetRange.insertContentControl();
        cc.tag = `statsync:${stat.id}${mode === "part" ? ":" + partKey : ""}`;
        cc.title = stat.label;
        cc.appearance = Word.ContentControlAppearance.hidden;
        cc.color = "#4CAF50";

        cc.clear();

        for (const segment of segments) {
          const insertedRange = cc.insertText(segment.text, Word.InsertLocation.end);

          insertedRange.font.italic = segment.italic;
          insertedRange.font.bold = segment.bold;
          insertedRange.font.name = "Times New Roman";
          insertedRange.font.size = 12;
        }

        // Move cursor to the end of the inserted content control so user can keep typing
        cc.getRange(Word.RangeLocation.after).select();

        await context.sync();

        // Track the link
        this.links.links.push({
          stat_id: stat.id,
          bookmark_name: cc.tag,
          insert_mode: mode,
          part_key: partKey,
          last_value: plainText,
          last_synced: new Date().toISOString(),
        });
      } else {
        // Fallback: if search didn't find it, insert at cursor
        await context.sync();
      }
    });
  }

  getLinks(): DocumentLinks {
    return this.links;
  }
}
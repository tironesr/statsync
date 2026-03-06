// ============================================================
// STATSYNC DIALOG — Insert Statistic Popup
// ============================================================

import "./dialog.css";
import { getFieldConfig } from "../models/field-configs";
import { assembleFormatted } from "../services/format-assembler";
import { StatisticEntry } from "../models/types";

interface GroupData {
    groupName: string;
    icon: string;
    stats: StatisticEntry[];
}

const TYPE_ICONS: Record<string, string> = {
    t_test: "📊",
    f_test: "📈",
    coefficient: "📉",
    model_fit: "🎯",
    correlation: "🔗",
    chi_square: "📋",
    odds_ratio: "⚖️",
    descriptive: "📊",
};

let allGroups: GroupData[] = [];

// Navigation and State
let currentView: "list" | "config" = "list";
let currentNavIndex = -1;
let currentStatForConfig: StatisticEntry | null = null;
let currentCheckedFields = new Set<string>();

Office.onReady(() => {
    initialize();
});

function initialize(): void {
    const raw = localStorage.getItem("statsync_dialog_data");
    if (!raw) {
        showEmpty("No statistics available");
        return;
    }

    const stats: StatisticEntry[] = JSON.parse(raw);
    const groupMap = new Map<string, StatisticEntry[]>();
    for (const stat of stats) {
        const group = stat.group || "Ungrouped";
        if (!groupMap.has(group)) groupMap.set(group, []);
        groupMap.get(group)!.push(stat);
    }

    allGroups = [];
    groupMap.forEach((groupStats, groupName) => {
        const primaryType = groupStats[0].type;
        allGroups.push({
            groupName,
            icon: TYPE_ICONS[primaryType] || "📌",
            stats: groupStats,
        });
    });

    allGroups.sort((a, b) => a.groupName.localeCompare(b.groupName));

    renderGroups(allGroups);

    const searchInput = document.getElementById("search-input") as HTMLInputElement;
    const searchClear = document.getElementById("search-clear")!;

    searchInput.addEventListener("input", () => {
        const query = searchInput.value.trim().toLowerCase();
        searchClear.style.display = query.length > 0 ? "block" : "none";

        if (query.length === 0) {
            renderGroups(allGroups);
        } else {
            const filtered = allGroups.filter((g) =>
                g.groupName.toLowerCase().includes(query) ||
                g.stats.some(s => s.label.toLowerCase().includes(query))
            );
            renderGroups(filtered);
        }
    });

    searchClear.addEventListener("click", () => {
        searchInput.value = "";
        searchClear.style.display = "none";
        renderGroups(allGroups);
        searchInput.focus();
    });

    const prefill = localStorage.getItem("statsync_dialog_prefill") || "";
    if (prefill.length > 0) {
        searchInput.value = prefill;
        searchClear.style.display = "block";
        const filtered = allGroups.filter((g) =>
            g.groupName.toLowerCase().includes(prefill.toLowerCase())
        );
        renderGroups(filtered);
    }

    searchInput.focus();

    // Dialog event listeners for Config view
    document.getElementById("config-back")!.addEventListener("click", closeConfigView);
    document.getElementById("config-btn-insert")!.addEventListener("click", () => {
        if (currentStatForConfig) {
            insertConfiguredStat(currentStatForConfig, currentCheckedFields);
        }
    });

    setupKeyboardNav();
}

// ============================================================
// KEYBOARD NAVIGATION
// ============================================================

function getVisibleNavItems(): HTMLElement[] {
    return Array.from(document.querySelectorAll('.dialog-group-header, .dialog-single-stat, .dialog-substat')).filter(el => {
        if (el.classList.contains('dialog-substat')) {
            const parent = el.closest('.dialog-group');
            return parent && parent.classList.contains('expanded');
        }
        return true;
    }) as HTMLElement[];
}

function updateSelection(items: HTMLElement[]) {
    items.forEach(el => el.classList.remove('selected'));
    if (currentNavIndex >= 0 && currentNavIndex < items.length) {
        const el = items[currentNavIndex];
        el.classList.add('selected');
        el.scrollIntoView({ block: 'nearest' });
    }
}

function setupKeyboardNav(): void {
    document.addEventListener("keydown", (e) => {
        if (currentView === "config") {
            if (e.key === "Escape") {
                e.preventDefault();
                closeConfigView();
            } else if (e.key === "Enter") {
                e.preventDefault();
                if (currentStatForConfig) insertConfiguredStat(currentStatForConfig, currentCheckedFields);
            }
            return;
        }

        // List View Navigation
        if (e.key === "ArrowDown") {
            e.preventDefault();
            const items = getVisibleNavItems();
            if (items.length === 0) return;
            currentNavIndex = (currentNavIndex + 1) % items.length;
            updateSelection(items);
        } else if (e.key === "ArrowUp") {
            e.preventDefault();
            const items = getVisibleNavItems();
            if (items.length === 0) return;
            currentNavIndex = (currentNavIndex - 1 + items.length) % items.length;
            updateSelection(items);
        } else if (e.key === "Enter") {
            e.preventDefault();
            const items = getVisibleNavItems();
            if (items[currentNavIndex]) items[currentNavIndex].click();
        } else if (e.key === "ArrowRight") {
            const items = getVisibleNavItems();
            const el = items[currentNavIndex];
            if (el) {
                if (el.classList.contains('dialog-single-stat') || el.classList.contains('dialog-substat')) {
                    e.preventDefault();
                    const statId = el.getAttribute("data-stat-id");
                    const stat = findStatById(statId);
                    if (stat) openConfigView(stat);
                } else if (el.classList.contains('dialog-group-header')) {
                    e.preventDefault();
                    const groupEl = el.closest('.dialog-group');
                    if (groupEl && !groupEl.classList.contains('expanded')) {
                        groupEl.classList.add('expanded');
                    }
                }
            }
        } else if (e.key === "ArrowLeft") {
            const items = getVisibleNavItems();
            const el = items[currentNavIndex];
            if (el && el.classList.contains('dialog-group-header')) {
                e.preventDefault();
                const groupEl = el.closest('.dialog-group');
                if (groupEl && groupEl.classList.contains('expanded')) {
                    groupEl.classList.remove('expanded');
                }
            }
        } else if (e.key === "Escape") {
            e.preventDefault();
            sendMessage({ action: "cancel" });
        }
    });
}

function findStatById(id: string | null): StatisticEntry | undefined {
    if (!id) return undefined;
    for (const g of allGroups) {
        for (const s of g.stats) {
            if (s.id === id) return s;
        }
    }
    return undefined;
}

// ============================================================
// CONFIG VIEW
// ============================================================

function openConfigView(stat: StatisticEntry): void {
    currentStatForConfig = stat;
    currentView = "config";

    document.getElementById("view-list")!.style.display = "none";
    document.getElementById("view-config")!.style.display = "flex";

    document.getElementById("config-stat-name")!.textContent = `${stat.group} - ${stat.label}`;

    const config = getFieldConfig(stat.type);
    currentCheckedFields = new Set<string>();
    config.fields.forEach(f => {
        if (f.apaDefault) currentCheckedFields.add(f.key);
    });

    renderConfigChecklist();
    updateConfigPreview();
}

function closeConfigView(): void {
    currentView = "list";
    currentStatForConfig = null;
    document.getElementById("view-config")!.style.display = "none";
    document.getElementById("view-list")!.style.display = "flex";

    // Refocus search so scrolling/typing works naturally again
    document.getElementById("search-input")?.focus();
}

function renderConfigChecklist(): void {
    if (!currentStatForConfig) return;
    const config = getFieldConfig(currentStatForConfig.type);
    const container = document.getElementById("config-fields-list")!;
    container.innerHTML = "";

    config.fields.forEach(field => {
        const item = document.createElement("div");
        item.style.display = "flex";
        item.style.alignItems = "center";
        item.style.gap = "8px";

        const checkbox = document.createElement("input");
        checkbox.type = "checkbox";
        checkbox.id = `cfg-field-${field.key}`;
        checkbox.checked = currentCheckedFields.has(field.key);
        checkbox.style.cursor = "pointer";

        checkbox.addEventListener("change", () => {
            if (checkbox.checked) {
                currentCheckedFields.add(field.key);
                if (field.key === "ci_lower") currentCheckedFields.add("ci_upper");
                if (field.key === "ci_upper") currentCheckedFields.add("ci_lower");
            } else {
                currentCheckedFields.delete(field.key);
                if (field.key === "ci_lower") currentCheckedFields.delete("ci_upper");
                if (field.key === "ci_upper") currentCheckedFields.delete("ci_lower");
            }
            renderConfigChecklist(); // Re-render to keep paired checkboxes in sync
            updateConfigPreview();
        });

        const label = document.createElement("label");
        label.htmlFor = checkbox.id;
        label.textContent = field.label;
        label.style.fontSize = "13px";
        label.style.cursor = "pointer";
        label.style.flex = "1";

        const valueSpan = document.createElement("span");
        valueSpan.style.fontSize = "12px";
        valueSpan.style.color = "#5f6368";
        valueSpan.style.fontFamily = "Consolas, monospace";

        let rawValue = currentStatForConfig!.formatted_parts?.[field.key];
        valueSpan.textContent = (rawValue && rawValue !== "NA") ? stripMarkup(String(rawValue)) : "—";

        item.appendChild(checkbox);
        item.appendChild(label);
        item.appendChild(valueSpan);
        container.appendChild(item);
    });
}

function updateConfigPreview(): void {
    if (!currentStatForConfig) return;
    const config = getFieldConfig(currentStatForConfig.type);
    const previewEl = document.getElementById("config-preview-text")!;

    if (currentCheckedFields.size === 0) {
        previewEl.innerHTML = '<span style="color: #80868b;">Select fields to preview</span>';
        return;
    }

    const customStr = assembleFormatted(currentStatForConfig, [...currentCheckedFields], config.assemblyOrder);
    previewEl.innerHTML = markupToHtml(customStr);
}

function insertConfiguredStat(stat: StatisticEntry, fields: Set<string>): void {
    const config = getFieldConfig(stat.type);
    const customStr = assembleFormatted(stat, [...fields], config.assemblyOrder);
    // Write to localStorage as a reliable side-channel — the parent reads this
    // because messageParent may auto-close the dialog before the message handler fires
    localStorage.setItem("statsync_dialog_custom_formatted", customStr);
    localStorage.setItem("statsync_dialog_custom_fields", JSON.stringify([...fields]));
    sendMessage({ action: "select", statId: stat.id, customFormatted: customStr });
}

// ============================================================
// RENDERING GROUPS
// ============================================================

function renderGroups(groups: GroupData[]): void {
    const container = document.getElementById("dialog-list")!;
    container.innerHTML = "";
    currentNavIndex = -1;

    if (groups.length === 0) {
        showEmpty("No matching statistics");
        return;
    }

    groups.forEach((group, groupIdx) => {
        if (group.stats.length === 1) {
            const stat = group.stats[0];
            const item = document.createElement("div");
            item.className = "dialog-single-stat";
            item.setAttribute("data-stat-id", stat.id);

            item.innerHTML = `
        <span class="dialog-group-icon">${group.icon}</span>
        <div class="dialog-group-info">
          <div class="dialog-group-label">${escapeHtml(group.groupName)}</div>
          <div class="dialog-group-meta">${escapeHtml(stripMarkup(stat.formatted))}</div>
        </div>
      `;

            item.addEventListener("click", () => {
                // If clicking directly, insert default APA
                selectStat(stat);
            });

            container.appendChild(item);
        } else {
            const groupEl = document.createElement("div");
            groupEl.className = "dialog-group";
            // Expand by default if searching, otherwise leave collapsed unless previously expanded
            if ((document.getElementById("search-input") as HTMLInputElement).value.trim().length > 0) {
                groupEl.classList.add("expanded");
            }

            const header = document.createElement("div");
            header.className = "dialog-group-header";
            header.innerHTML = `
        <span class="dialog-group-icon">${group.icon}</span>
        <div class="dialog-group-info">
          <div class="dialog-group-label">${escapeHtml(group.groupName)}</div>
          <div class="dialog-group-meta">${group.stats.length} statistics</div>
        </div>
        <span class="dialog-group-badge">${group.stats.length}</span>
        <span class="dialog-group-chevron">▶</span>
      `;

            header.addEventListener("click", () => {
                groupEl.classList.toggle("expanded");
            });
            groupEl.appendChild(header);

            const substats = document.createElement("div");
            substats.className = "dialog-substats";

            group.stats.forEach((stat) => {
                const subItem = document.createElement("div");
                subItem.className = "dialog-substat";
                subItem.setAttribute("data-stat-id", stat.id);

                let shortLabel = stat.label
                    .replace(group.groupName + " - ", "")
                    .replace(group.groupName + " -", "");

                subItem.innerHTML = `
          <span class="dialog-substat-label">${escapeHtml(shortLabel)}</span>
          <span class="dialog-substat-preview">${escapeHtml(stripMarkup(stat.formatted))}</span>
        `;

                subItem.addEventListener("click", (e) => {
                    e.stopPropagation();
                    selectStat(stat);
                });

                substats.appendChild(subItem);
            });

            groupEl.appendChild(substats);
            container.appendChild(groupEl);
        }
    });
}

function selectStat(stat: StatisticEntry): void {
    // Clear any leftover custom formatted string — this is a default insert
    localStorage.removeItem("statsync_dialog_custom_formatted");
    localStorage.removeItem("statsync_dialog_custom_fields");
    sendMessage({
        action: "select",
        statId: stat.id,
    });
}

function sendMessage(data: { action: string; statId?: string; customFormatted?: string }): void {
    Office.context.ui.messageParent(JSON.stringify(data));
}

function showEmpty(message: string): void {
    const container = document.getElementById("dialog-list")!;
    container.innerHTML = `
    <div class="dialog-empty">
      <div class="dialog-empty-icon">🔍</div>
      <div class="dialog-empty-text">${escapeHtml(message)}</div>
    </div>
  `;
}

function stripMarkup(text: string): string {
    return text.replace(/\{\/?(i|b)\}/g, "");
}

function markupToHtml(text: string): string {
    if (!text) return "";
    return escapeHtml(text)
        .replace(/\{i\}/g, "<em>")
        .replace(/\{\/i\}/g, "</em>")
        .replace(/\{b\}/g, "<strong>")
        .replace(/\{\/b\}/g, "</strong>");
}

function escapeHtml(text: string): string {
    const div = document.createElement("div");
    div.textContent = text;
    let escaped = div.innerHTML;
    escaped = escaped.replace(/\{i\}/g, "{i}").replace(/\{\/i\}/g, "{/i}");
    escaped = escaped.replace(/\{b\}/g, "{b}").replace(/\{\/b\}/g, "{/b}");
    return escaped;
}

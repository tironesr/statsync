// ============================================================
// STATSYNC TASK PANE — MAIN CONTROLLER
// ============================================================

import "./taskpane.css";

import { StatSyncReader } from "../services/statsync-reader";
import { WordInserter } from "../services/word-inserter";
import { assembleFormatted } from "../services/format-assembler";
import { getFieldConfig, FieldOption } from "../models/field-configs";
import { StatSyncProject, StatisticEntry, TableEntry } from "../models/types";
import { AutocompleteMonitor } from "../services/autocomplete-monitor";

let reader: StatSyncReader;
let inserter: WordInserter;
let autocompleteMonitor: AutocompleteMonitor;

// Track the state of each model card's UI
interface CardState {
  selectedCoefId: string;
  checkedFields: Set<string>;
}
const cardStates = new Map<string, CardState>();

// Active type filter
let activeTypeFilter: string | null = null;

// Auto-sync polling
let isAutoSyncPaused: boolean = false;
let isConnected: boolean = false;

Office.onReady((info) => {
  if (info.host === Office.HostType.Word) {
    initialize();
  }
});

function initialize(): void {
  reader = new StatSyncReader();
  inserter = new WordInserter();
  autocompleteMonitor = new AutocompleteMonitor();

  setupEventHandlers();
  setupAutocomplete();

  reader.onUpdate(async (data, isLive) => {
    // 1. Update the isConnected state to match the reader's live status
    isConnected = isLive;

    // 2. Only update UI and Document automatically if not paused AND we are currently live
    // (If not live, we treat as paused/offline mode)
    if (!isAutoSyncPaused && isConnected) {
      renderAll(data);
      updateStatus(data, false);

      // Feed statistics to autocomplete monitor
      const statsArray = Array.isArray(data.statistics) ? data.statistics : [];
      autocompleteMonitor.setStatistics(statsArray);
      autocompleteMonitor.start();

      try {
        const res = await inserter.updateAllLinks((id) => reader.getStatistic(id));
        if (res.updated > 0 || res.failed > 0) {
          showUpdateResult(res);
        }
      } catch (e) {
        console.error("Auto sync error", e);
      }
    } else {
      // If paused OR disconnected, just update the UI state to show current data as cached
      renderAll(data);
      updateStatus(data, !isConnected || isAutoSyncPaused);

      // Show/Hide manual sync button based on isLive & isAutoSyncPaused
      const btnManualSync = document.getElementById("btn-manual-sync");
      if (btnManualSync) {
        btnManualSync.style.display = (!isConnected || isAutoSyncPaused) ? "block" : "none";
      }

      const btnLive = document.getElementById("btn-connect-server");
      if (btnLive) {
        if (isConnected) {
          btnLive.innerHTML = '<span class="live-dot"></span> Live';
          btnLive.className = "btn btn-success";
        } else {
          btnLive.innerHTML = '<span class="live-dot"></span> Offline';
          btnLive.className = "btn btn-live";
        }
      }
    }
  });

  // Load from cache initially for offline support
  const initialData = reader.getData();
  if (initialData) {
    renderAll(initialData);
    updateStatus(initialData, true); // true = show offline/cached state
    showPanels();
  }
}

// ============================================================
// EVENT HANDLERS
// ============================================================

function setupEventHandlers(): void {
  // File load
  const btnLoad = document.getElementById("btn-load-file") as HTMLButtonElement;
  btnLoad.onclick = (e) => {
    e.preventDefault();
    e.stopPropagation();
    document.getElementById("file-input")!.click();
  };

  const fileInput = document.getElementById("file-input") as HTMLInputElement;
  fileInput.onchange = async (e) => {
    const input = e.target as HTMLInputElement;
    if (input.files && input.files[0]) {
      try {
        await reader.loadFromFile(input.files[0]);
        showPanels();
        setStatus("✓ File loaded successfully", "success");
      } catch (err) {
        setStatus(`Error: ${err}`, "error");
      }
      // Reset input value so the same file can be selected again
      input.value = "";
    }
  };

  // Server connection — clicking Live directly attempts connection
  const btnLive = document.getElementById("btn-connect-server") as HTMLButtonElement;
  const serverConfig = document.getElementById("server-config")!;
  const btnServerGo = document.getElementById("btn-server-go") as HTMLButtonElement;
  const serverUrlInput = document.getElementById("server-url") as HTMLInputElement;

  async function attemptServerConnection(): Promise<void> {
    const url = serverUrlInput.value || "http://localhost:8877";
    btnLive.innerHTML = '<span class="live-dot" style="background: var(--warning)"></span> Connecting...';
    btnLive.disabled = true;
    setStatus("Connecting to R server...", "info");

    try {
      const connected = await reader.connectToServer(url);
      if (connected) {
        reader.startPolling(500);
        showPanels();
        setStatus("Connected to R (live)", "success");
        btnLive.innerHTML = '<span class="live-dot"></span> Live';
        btnLive.className = "btn btn-success";
        serverConfig.style.display = "none";
        isConnected = true;
      } else {
        setStatus("Failed to connect. Is sync_serve() running in R?", "error");
        btnLive.innerHTML = '<span class="live-dot"></span> Live';
        btnLive.className = "btn btn-live";
        serverConfig.style.display = "flex";
        isConnected = false;
      }
    } catch (err) {
      setStatus(`Connection error: ${err}`, "error");
      btnLive.innerHTML = '<span class="live-dot"></span> Live';
      btnLive.className = "btn btn-live";
      serverConfig.style.display = "flex";
      isConnected = false;
    } finally {
      btnLive.disabled = false;
    }
  }

  btnLive.onclick = async (e) => {
    e.preventDefault();
    e.stopPropagation();
    // If already connected, toggle config panel for URL changes
    if (isConnected) {
      const isVisible = serverConfig.style.display === "flex";
      serverConfig.style.display = isVisible ? "none" : "flex";
      return;
    }
    await attemptServerConnection();
  };

  btnServerGo.onclick = async (e) => {
    e.preventDefault();
    e.stopPropagation();
    await attemptServerConnection();
  };

  // Search
  const searchInput = document.getElementById("search-input") as HTMLInputElement;
  const searchClear = document.getElementById("search-clear")!;

  searchInput.addEventListener("input", () => {
    const query = searchInput.value;
    searchClear.style.display = query.length > 0 ? "block" : "none";
    // Show models panel only when actively searching
    const modelsPanel = document.getElementById("models-panel")!;
    modelsPanel.style.display = query.length > 0 ? "block" : "none";
    filterModels();
  });

  searchClear.addEventListener("click", () => {
    searchInput.value = "";
    searchClear.style.display = "none";
    document.getElementById("models-panel")!.style.display = "none";
    filterModels();
  });

  // Pause Auto Sync
  const btnPauseSync = document.getElementById("btn-pause-sync") as HTMLButtonElement;
  const btnManualSync = document.getElementById("btn-manual-sync") as HTMLButtonElement;

  btnPauseSync.onclick = (e) => {
    e.preventDefault();
    isAutoSyncPaused = !isAutoSyncPaused;

    if (isAutoSyncPaused) {
      btnPauseSync.textContent = "▶ Resume Automatic Syncing";
      btnPauseSync.classList.remove("btn-outline");
      btnPauseSync.classList.add("btn-primary");
      btnManualSync.style.display = "block"; // Show manual sync button
      setStatus("Auto-sync paused", "warning");
    } else {
      btnPauseSync.textContent = "⏸ Pause Automatic Syncing";
      btnPauseSync.classList.remove("btn-primary");
      btnPauseSync.classList.add("btn-outline");
      btnManualSync.style.display = "none"; // Hide manual sync button
      setStatus("Connected to R (live)", "success");
    }
  };

  btnManualSync.onclick = async (e) => {
    e.preventDefault();
    btnManualSync.disabled = true;
    const originalText = btnManualSync.innerHTML;
    btnManualSync.innerHTML = '🔄 Syncing...';

    try {
      // 1. Fetch latest directly to ensure we're fresh before syncing
      if (isConnected) {
        await reader.refresh();
      }

      const data = reader.getData();

      // 2. Update the sidebar UI immediately
      if (data) {
        renderAll(data);
        updateStatus(data);
      }

      // 3. Update the Word document
      const res = await inserter.updateAllLinks((id) => reader.getStatistic(id));
      showUpdateResult(res);
      setStatus(`✓ Manual sync complete: ${res.updated} updated`, "success");
    } catch (err) {
      console.error("Manual sync failed", err);
      setStatus(`Manual sync failed: ${err}`, "error");
    } finally {
      btnManualSync.innerHTML = originalText;
      btnManualSync.disabled = false;
    }
  };
}

// ============================================================
// AUTOCOMPLETE
// ============================================================

let dialog: Office.Dialog | null = null;
let currentReplaceText = "";

function setupAutocomplete(): void {
  // We no longer use the taskpane-based autocomplete popup
  // Connect monitor to trigger the Office dialog instead
  autocompleteMonitor.onSuggestions((suggestions, triggerText) => {
    // Check if we should open the dialog
    if (triggerText && !dialog) {
      openAutocompleteDialog(triggerText);
    }
  });
}

function openAutocompleteDialog(triggerText: string): void {
  currentReplaceText = triggerText;
  autocompleteMonitor.stop(); // pause polling while dialog is open

  // Share statistics data with the dialog via localStorage
  // The dialog will read this on init
  const allStats = reader.getData()?.statistics || [];
  localStorage.setItem("statsync_dialog_data", JSON.stringify(allStats));

  // Pass the typed search query (everything after {{)
  const queryMatch = triggerText.match(/\{\{([^}]*)/);
  const query = queryMatch ? queryMatch[1].trim() : "";
  localStorage.setItem("statsync_dialog_prefill", query);

  // Open the dialog
  const url = new URL("dialog.html", window.location.href).href;

  Office.context.ui.displayDialogAsync(
    url,
    { height: 65, width: 40, displayInIframe: true },
    (asyncResult) => {
      if (asyncResult.status === Office.AsyncResultStatus.Failed) {
        console.error("Failed to open dialog:", asyncResult.error.message);
        autocompleteMonitor.start(); // Resume monitor
        return;
      }

      dialog = asyncResult.value;
      dialog.addEventHandler(Office.EventType.DialogMessageReceived, handleDialogMessage);
      dialog.addEventHandler(Office.EventType.DialogEventReceived, handleDialogEvent);
    }
  );
}

function handleDialogEvent(arg: any): void {
  // Handles dialog closed by user (e.g. X button)
  console.log("Dialog closed by event:", arg);

  // Defer cleanup to avoid racing with handleDialogMessage
  setTimeout(() => {
    if (dialog) {
      dialog = null;
    }
    autocompleteMonitor.ignoreCurrent();
    autocompleteMonitor.dismiss();
    setTimeout(() => {
      autocompleteMonitor.start();
    }, 500);
  }, 300);
}

async function handleDialogMessage(arg: any): Promise<void> {
  const data = JSON.parse(arg.message);

  if (data.action === "cancel") {
    if (dialog) { dialog.close(); }
    dialog = null;
    autocompleteMonitor.ignoreCurrent();
    autocompleteMonitor.dismiss();
    setTimeout(() => { autocompleteMonitor.start(); }, 1000);
    return;
  }

  if (data.action === "select" && data.statId) {
    if (dialog) { dialog.close(); }
    dialog = null;

    const stat = reader.getStatistic(data.statId);
    if (stat) {
      const statToInsert: StatisticEntry = { ...stat };

      // Read customFormatted from localStorage as a reliable side-channel.
      // The dialog writes it there before calling messageParent, so it
      // survives even if the dialog auto-closes and events race.
      const storedCustom = localStorage.getItem("statsync_dialog_custom_formatted");
      if (storedCustom && storedCustom.length > 0) {
        statToInsert.formatted = storedCustom;
        localStorage.removeItem("statsync_dialog_custom_formatted");
      } else if (data.customFormatted && data.customFormatted.length > 0) {
        statToInsert.formatted = data.customFormatted;
      }

      // Read custom fields to save to document settings so updates rebuild the custom format
      const storedFields = localStorage.getItem("statsync_dialog_custom_fields");
      if (storedFields) {
        Office.context.document.settings.set(`statsync_format_${stat.id}`, storedFields);
        Office.context.document.settings.saveAsync();
        localStorage.removeItem("statsync_dialog_custom_fields");
      } else {
        Office.context.document.settings.remove(`statsync_format_${stat.id}`);
        Office.context.document.settings.saveAsync();
      }

      try {
        await inserter.replaceTextAndInsert(
          currentReplaceText,
          statToInsert,
          "full"
        );
        setStatus(`✓ Inserted: ${stat.label}`, "success");
      } catch (err) {
        console.error("Autocomplete insert failed:", err);
        setStatus(`Insert failed: ${err}`, "error");
      }
    }

    autocompleteMonitor.dismiss();
    setTimeout(() => {
      autocompleteMonitor.start();
    }, 1000);
  }
}

// ============================================================
// RENDERING
// ============================================================

function showPanels(): void {
  document.getElementById("search-panel")!.style.display = "block";
  // Models panel stays hidden until user searches or clicks a filter
  document.getElementById("models-panel")!.style.display = "none";
  document.getElementById("update-panel")!.style.display = "block";
}

function renderAll(data: StatSyncProject): void {
  renderFilterChips(data);
  renderModelCards(data);
}

/**
 * Render type filter chips based on what test types exist in the data.
 */
function renderFilterChips(data: StatSyncProject): void {
  const container = document.getElementById("filter-chips")!;
  container.innerHTML = "";

  const types = new Set<string>();
  const statsArray = Array.isArray(data.statistics) ? data.statistics : [];
  for (const stat of statsArray) {
    types.add(stat.type);
  }

  // "All" chip
  const allChip = document.createElement("button");
  allChip.className = `filter-chip ${activeTypeFilter === null ? "active" : ""}`;
  allChip.textContent = "All";
  allChip.addEventListener("click", () => {
    activeTypeFilter = activeTypeFilter === null ? "none" : null;
    renderFilterChips(data);
    // Show models panel when a filter chip is clicked
    document.getElementById("models-panel")!.style.display = "block";
    filterModels();
  });
  container.appendChild(allChip);

  types.forEach((type) => {
    const config = getFieldConfig(type);
    const chip = document.createElement("button");
    chip.className = `filter-chip ${activeTypeFilter === type ? "active" : ""}`;
    chip.textContent = `${config.icon} ${config.label}`;
    chip.addEventListener("click", () => {
      activeTypeFilter = activeTypeFilter === type ? "none" : type;
      renderFilterChips(data);
      // Show models panel when a filter chip is clicked
      document.getElementById("models-panel")!.style.display = "block";
      filterModels();
    });
    container.appendChild(chip);
  });
}

/**
 * Render model cards grouped by model/group name.
 */
function renderModelCards(data: StatSyncProject): void {
  const container = document.getElementById("models-list")!;
  container.innerHTML = "";

  const groups = reader.getStatisticsByGroup();

  if (groups.size === 0) {
    container.innerHTML = `
      <div class="empty-state">
        <div class="empty-state-icon">📭</div>
        <div class="empty-state-text">No statistics loaded</div>
      </div>
    `;
    return;
  }

  let totalStats = 0;
  groups.forEach((stats, groupName) => {
    totalStats += stats.length;
    const card = createModelCard(groupName, stats);
    container.appendChild(card);
  });

  document.getElementById("stat-count")!.textContent = `${totalStats} stats`;
}

/**
 * Create a single model card with coefficient selector and field checklist.
 */
function createModelCard(groupName: string, stats: StatisticEntry[]): HTMLElement {
  const card = document.createElement("div");
  card.className = "model-card";
  card.dataset.group = groupName.toLowerCase();
  card.dataset.types = [...new Set(stats.map((s) => s.type))].join(",");

  // Determine primary type for icon/config
  const primaryType = stats[0].type;
  const config = getFieldConfig(primaryType);

  // Determine subtitle
  const statTypes = [...new Set(stats.map((s) => s.type))];
  const subtitle = stats.length === 1
    ? config.label
    : `${stats.length} statistics · ${statTypes.map((t) => getFieldConfig(t).label).join(", ")}`;

  // ---- Header ----
  const header = document.createElement("div");
  header.className = "model-card-header";
  header.innerHTML = `
    <span class="model-card-chevron">▶</span>
    <span class="model-card-icon">${config.icon}</span>
    <div class="model-card-info">
      <div class="model-card-title">${escapeHtml(groupName)}</div>
      <div class="model-card-subtitle">${subtitle}</div>
    </div>
    <span class="model-card-badge">${stats.length}</span>
  `;

  header.addEventListener("click", () => {
    card.classList.toggle("expanded");
  });
  card.appendChild(header);

  // ---- Body ----
  const body = document.createElement("div");
  body.className = "model-card-body";

  // Initialize card state if not exists
  if (!cardStates.has(groupName)) {
    const defaultFields = new Set<string>();
    const defaultConfig = getFieldConfig(stats[0].type);
    defaultConfig.fields.forEach((f) => {
      if (f.apaDefault) defaultFields.add(f.key);
    });

    cardStates.set(groupName, {
      selectedCoefId: stats[0].id,
      checkedFields: defaultFields,
    });
  }

  const state = cardStates.get(groupName)!;

  // ---- Coefficient Selector (if multiple stats in group) ----
  if (stats.length > 1) {
    const selectorDiv = document.createElement("div");
    selectorDiv.className = "coef-selector";

    const selectorLabel = document.createElement("label");
    selectorLabel.textContent = "Select Statistic";
    selectorDiv.appendChild(selectorLabel);

    const select = document.createElement("select");
    select.className = "coef-select";

    stats.forEach((stat) => {
      const option = document.createElement("option");
      option.value = stat.id;
      // Clean up the label: remove the group prefix
      let displayLabel = stat.label.replace(groupName + " - ", "").replace(groupName + " -", "");
      option.textContent = `${getFieldConfig(stat.type).icon} ${displayLabel}`;
      if (stat.id === state.selectedCoefId) option.selected = true;
      select.appendChild(option);
    });

    select.addEventListener("change", () => {
      state.selectedCoefId = select.value;

      // Update field config for the new stat type
      const newStat = stats.find((s) => s.id === select.value)!;
      const newConfig = getFieldConfig(newStat.type);

      // Reset to APA defaults for new type
      state.checkedFields = new Set<string>();
      newConfig.fields.forEach((f) => {
        if (f.apaDefault) state.checkedFields.add(f.key);
      });

      // Re-render the body contents
      renderCardBody(body, groupName, stats, state);
    });

    selectorDiv.appendChild(select);
    body.appendChild(selectorDiv);
  }

  renderCardBody(body, groupName, stats, state);
  card.appendChild(body);

  return card;
}

/**
 * Render the preview inside a card body.
 */
function renderCardBody(
  body: HTMLElement,
  groupName: string,
  stats: StatisticEntry[],
  state: CardState
): void {
  // Remove existing preview (keep the selector dropdown)
  const existingPreview = body.querySelector(".preview-box");
  if (existingPreview) existingPreview.remove();

  const selectedStat = stats.find((s) => s.id === state.selectedCoefId) || stats[0];
  const typeConfig = getFieldConfig(selectedStat.type);

  // ---- Preview ----
  const previewBox = document.createElement("div");
  previewBox.className = "preview-box";
  previewBox.innerHTML = `
    <div class="preview-label">Preview</div>
    <div class="preview-text"></div>
  `;
  body.appendChild(previewBox);

  // Show the formatted output for the selected stat
  const previewText = previewBox.querySelector(".preview-text")!;
  previewText.innerHTML = markupToHtml(selectedStat.formatted);
}



/**
 * Filter model cards by search text and type filter.
 */
function filterModels(): void {
  const query = (document.getElementById("search-input") as HTMLInputElement).value.toLowerCase();
  const cards = document.querySelectorAll(".model-card") as NodeListOf<HTMLElement>;

  let visibleCount = 0;

  cards.forEach((card) => {
    const group = card.dataset.group || "";
    const types = card.dataset.types || "";

    const matchesSearch = query === "" || group.includes(query);
    const matchesType = activeTypeFilter === null || types.includes(activeTypeFilter);

    const visible = matchesSearch && matchesType && activeTypeFilter !== "none";
    card.style.display = visible ? "block" : "none";
    if (visible) visibleCount++;
  });

  // Update count
  const countEl = document.getElementById("stat-count");
  if (countEl) {
    const total = cards.length;
    countEl.textContent = query || (activeTypeFilter && activeTypeFilter !== "none")
      ? `${visibleCount}/${total} shown`
      : `${total} models`;
  }
}

// Tables disabled by user request

// ============================================================
// HELPERS
// ============================================================

function setStatus(message: string, type: string = "info"): void {
  document.getElementById("status")!.textContent = message;
}

function updateStatus(data: StatSyncProject, isOfflineOrPaused: boolean = false): void {
  const statsArray = Array.isArray(data.statistics) ? data.statistics : [];

  const statusMsg = !isConnected
    ? `🔴 Offline (${statsArray.length} cached)`
    : (isAutoSyncPaused ? `⏸ Paused (${statsArray.length} stats)` : `${statsArray.length} statistics`);

  setStatus(statusMsg);

  const projectNameEl = document.getElementById("project-name")!;
  projectNameEl.textContent = data.project?.name || "—";
  if (!isConnected) projectNameEl.innerHTML += " <small>(Offline)</small>";

  document.getElementById("last-sync")!.textContent = !isConnected ? "Last Sync: " + new Date(data.generated_at || Date.now()).toLocaleTimeString() : new Date().toLocaleTimeString();
}

function showUpdateResult(
  result: { updated: number; failed: number; unchanged: number } | null,
  error?: string
): void {
  const div = document.getElementById("update-result")!;
  div.style.display = "block";

  if (error) {
    div.className = "update-result error";
    div.textContent = error;
  } else if (result) {
    div.className = "update-result success";
    div.innerHTML = `✅ ${result.updated} updated · ⏸ ${result.unchanged} unchanged${result.failed > 0 ? ` · ❌ ${result.failed} failed` : ""
      }`;
  }

  setTimeout(() => {
    div.style.display = "none";
  }, 4000);
}

function markupToHtml(text: string): string {
  if (!text) return "";
  return escapeHtml(text)
    .replace(/\{i\}/g, "<em>")
    .replace(/\{\/i\}/g, "</em>")
    .replace(/\{b\}/g, "<strong>")
    .replace(/\{\/b\}/g, "</strong>");
}

function stripMarkup(text: string): string {
  return text.replace(/\{\/?(i|b)\}/g, "");
}

function escapeHtml(text: string): string {
  const div = document.createElement("div");
  div.textContent = text;
  // Get the escaped text but preserve our markup tags
  let escaped = div.innerHTML;
  // The {i} tags got escaped too, restore them
  escaped = escaped.replace(/\{i\}/g, "{i}").replace(/\{\/i\}/g, "{/i}");
  escaped = escaped.replace(/\{b\}/g, "{b}").replace(/\{\/b\}/g, "{/b}");
  return escaped;
}

function flashButton(btn: HTMLElement, text: string, isError: boolean): void {
  const original = btn.textContent;
  btn.textContent = text;
  btn.style.background = isError ? "var(--error)" : "var(--accent)";
  btn.style.color = "white";
  btn.style.borderColor = isError ? "var(--error)" : "var(--accent)";
  setTimeout(() => {
    btn.textContent = original;
    btn.style.background = "";
    btn.style.color = "";
    btn.style.borderColor = "";
  }, 1500);
}
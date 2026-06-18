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
let docDir: string | null = null;

// Track the state of each model card's UI
interface CardState {
  selectedCoefId: string;
  checkedFields: Set<string>;
}
const cardStates = new Map<string, CardState>();

// Active type filter (none = cold start, null = 'All')
let activeTypeFilter: string | null = "none";

// Auto-sync polling
let isAutoSyncPaused: boolean = false;
let isConnected: boolean = false;
let isManualSyncing: boolean = false;
let isSyncing: boolean = false;
let lastProjectName: string | null = null;
let linkedProjectName: string | null = null;
let hasSyncedThisConnection: boolean = false;

// Autocomplete State
let dialog: Office.Dialog | null = null;
let currentReplaceText = "";
let lastKnownGroups = new Set<string>();
let resultHideTimer: any = null;

Office.onReady((info) => {
  if (info.host === Office.HostType.Word) {
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", () => {
        initialize().catch((err) => console.error("Initialization failed:", err));
      });
    } else {
      initialize().catch((err) => console.error("Initialization failed:", err));
    }
  }
});

async function getDocumentDirectory(): Promise<string | null> {
  return new Promise((resolve) => {
    try {
      Office.context.document.getFilePropertiesAsync((result) => {
        if (result.status === Office.AsyncResultStatus.Succeeded && result.value && result.value.url) {
          const url = result.value.url;
          try {
            const decodedUrl = decodeURIComponent(url);
            const standardized = decodedUrl.replace(/\\/g, "/");
            const lastSlash = standardized.lastIndexOf("/");
            if (lastSlash !== -1) {
              let dir = standardized.substring(0, lastSlash);
              dir = dir.replace(/^file:\/\/\//i, "").replace(/^file:\/\//i, "");
              resolve(dir);
              return;
            }
          } catch (e) {
            console.error("Failed to parse document URL:", e);
          }
        }
        resolve(null);
      });
    } catch (e) {
      console.warn("Failed to get document file properties:", e);
      resolve(null);
    }
  });
}

function populateProjectDropdown(): void {
  const select = document.getElementById("project-select") as HTMLSelectElement;
  if (!select) return;

  // Clear existing options, keep placeholder
  select.innerHTML = '<option value="">-- Select or link a project --</option>';

  const projects = reader.getCachedProjects();
  projects.forEach((proj) => {
    const opt = document.createElement("option");
    opt.value = proj;
    opt.textContent = proj;
    if (proj === linkedProjectName) {
      opt.selected = true;
    }
    select.appendChild(opt);
  });

  const btnRemoveProject = document.getElementById("btn-remove-project") as HTMLButtonElement;
  if (btnRemoveProject) {
    btnRemoveProject.style.display = select.value ? "block" : "none";
  }
}

async function attemptServerConnection(urlToConnect?: string): Promise<void> {
  const btnLive = document.getElementById("btn-connect-server") as HTMLButtonElement;
  const serverConfig = document.getElementById("server-config")!;
  const serverUrlInput = document.getElementById("server-url") as HTMLInputElement;
  
  const url = urlToConnect || (serverUrlInput ? serverUrlInput.value : "") || "http://localhost:8877";
  
  if (btnLive) {
    btnLive.innerHTML = '<span class="live-dot" style="background: var(--warning)"></span> Connecting...';
    btnLive.disabled = true;
  }
  setStatus("Connecting to R server...", "info");

  try {
    const connected = await reader.connectToServer(url);
    if (connected) {
      reader.startPolling(500);
      showPanels();
      setStatus("Connected to R (live)", "success");
      if (btnLive) {
        btnLive.innerHTML = '<span class="live-dot"></span> Live';
        btnLive.className = "btn btn-success";
      }
      if (serverConfig) serverConfig.style.display = "none";
      isConnected = true;
      
      // Persist settings
      reader.saveConnectionSettings(url, "live");
    } else {
      setStatus("Failed to connect. Is sync_serve() running in R?", "error");
      if (btnLive) {
        btnLive.innerHTML = '<span class="live-dot"></span> Offline';
        btnLive.className = "btn btn-live";
      }
      if (serverConfig) serverConfig.style.display = "flex";
      isConnected = false;
      
      // Persist connection mode as offline
      reader.saveConnectionSettings(url, "offline");
    }
  } catch (err) {
    setStatus(`Connection error: ${err}`, "error");
    if (btnLive) {
      btnLive.innerHTML = '<span class="live-dot"></span> Offline';
      btnLive.className = "btn btn-live";
    }
    if (serverConfig) serverConfig.style.display = "flex";
    isConnected = false;
    
    reader.saveConnectionSettings(url, "offline");
  } finally {
    if (btnLive) btnLive.disabled = false;
  }
}

async function initialize(): Promise<void> {
  // --- Service Worker Registration for Offline Mode ---
  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.register('./sw.js')
      .then((reg) => console.log('StatSync Offline Worker registered', reg))
      .catch((err) => console.warn('Offline Worker failed:', err));
  }

  reader = new StatSyncReader();
  inserter = new WordInserter();
  autocompleteMonitor = new AutocompleteMonitor();

  setupAutocomplete();

  // Load project binding from Word document memory or directory mapping
  try {
    docDir = await getDocumentDirectory();
    if (docDir) {
      linkedProjectName = reader.getDirectoryMapping(docDir);
    }
    
    if (!linkedProjectName) {
      linkedProjectName = Office.context.document.settings.get("StatSyncLinkedProject");
    }
    
    if (linkedProjectName) {
      reader.loadFromCache(linkedProjectName);
    }
  } catch (e) {
    console.warn("Failed to load document settings/directory mapping:", e);
  }

  setupEventHandlers();
  populateProjectDropdown();

  reader.onUpdate(async (data, isLive) => {
    // 1. Update internal connection state
    const wasOffline = !isConnected && isLive;
    isConnected = isLive;
    if (!isConnected) hasSyncedThisConnection = false; // Reset for next connect

    // 2. Project Memory & Binding
    const incomingProject = data.project?.name || "Untitled";
    if (docDir && incomingProject !== "Untitled") {
      reader.setDirectoryMapping(docDir, incomingProject);
    }

    if (!linkedProjectName && incomingProject !== "Untitled") {
      // First project seen, link it to this document
      linkedProjectName = incomingProject;
      Office.context.document.settings.set("StatSyncLinkedProject", incomingProject);
      Office.context.document.settings.saveAsync();
    } else if (linkedProjectName && linkedProjectName !== incomingProject) {
      // BLOCKER: This document belongs to a different project
      setStatus(`⚠️ Linked to '${linkedProjectName}', current is '${incomingProject}'`, "error");
      updateStatus(data, true);
      const btnManualSync = document.getElementById("btn-manual-sync") as HTMLElement;
      if (btnManualSync) btnManualSync.style.display = "none"; // Hide sync button to prevent wrong data
      populateProjectDropdown();
      return; // Skip data processing
    }

    populateProjectDropdown();

    // 3. ALWAYS feed stats to monitor for {{ autocomplete
    const statsArray = Array.isArray(data.statistics) ? data.statistics : [];
    autocompleteMonitor.setStatistics(statsArray);
    autocompleteMonitor.start();

    // 3. Status Bar: Update state (Live, Offline, or Paused)
    updateStatus(data, !isConnected || isAutoSyncPaused);

    // 4. Update the "Live/Offline" button visibility and style
    const btnLive = document.getElementById("btn-connect-server");
    if (btnLive) {
      if (isConnected) {
        btnLive.innerHTML = isAutoSyncPaused ? '<span class="live-dot"></span> Live (Paused)' : '<span class="live-dot"></span> Live';
        btnLive.className = isAutoSyncPaused ? "btn btn-success paused" : "btn btn-success";
      } else {
        btnLive.innerHTML = '<span class="live-dot"></span> Offline';
        btnLive.className = "btn btn-live";
      }
    }

    // 5. Manage Manual Sync Button
    const btnManualSync = document.getElementById("btn-manual-sync") as HTMLElement;
    if (btnManualSync) {
      btnManualSync.style.display = (isAutoSyncPaused || !isConnected) ? "block" : "none";
    }

    // 6. MAIN SYNC LOGIC: Only proceed if NOT paused and NOT manual syncing
    if (isAutoSyncPaused || isManualSyncing) {
      return;
    }

    // Helper for group comparison
    const getCurrentGroups = (d: StatSyncProject) => {
      const s = new Set<string>();
      if (d.statistics) d.statistics.forEach(st => s.add(st.group || "Ungrouped"));
      return s;
    };
    const newGroups = getCurrentGroups(data);

    // Track structural changes (Added / Deleted)
    let added = 0;
    newGroups.forEach(g => { if (!lastKnownGroups.has(g)) added++; });
    let deleted = 0;
    lastKnownGroups.forEach(g => { if (!newGroups.has(g)) deleted++; });

    // AUTO-OPEN: If we have data and were in the 'none' state, show everything
    if (activeTypeFilter === "none" && newGroups.size > 0) {
      activeTypeFilter = null; // null = 'All'
    }

    // Update reference for next time
    lastKnownGroups = newGroups;

    // 7. Update the sidebar UI immediately
    renderAll(data);

    if (isSyncing) {
      console.log("Document sync already in progress, skipping...");
      return;
    }

    isSyncing = true;

    // 8. Doc Sync Logic: Update Word document tags
    try {
      let docRes = { updated: 0, failed: 0, unchanged: 0 };

      // AUTO-UPDATE ON LOAD: If we just established a live connection, perform a full sync
      if (isConnected && (!hasSyncedThisConnection || wasOffline)) {
        hasSyncedThisConnection = true;
        docRes = await inserter.updateAllLinks((id) => reader.getStatistic(id), (id) => reader.getTable(id));
        showUpdateResult(docRes, undefined, added, deleted);
      } else if (isConnected && !isAutoSyncPaused) {
        // Normal auto-sync while working
        docRes = await inserter.updateAllLinks((id) => reader.getStatistic(id), (id) => reader.getTable(id));
        showUpdateResult(docRes, undefined, added, deleted);
      } else {
        // Show existing structural changes only
        showUpdateResult(null, undefined, added, deleted);
      }
    } catch (e) {
      console.error("Sync update failed:", e);
    } finally {
      isSyncing = false;
    }
  });

  // Load from cache initially for offline support
  const initialData = reader.getData();
  if (initialData) {
    const s = new Set<string>();
    if (initialData.statistics) initialData.statistics.forEach(st => s.add(st.group || "Ungrouped"));
    lastKnownGroups = s;

    renderAll(initialData);
    updateStatus(initialData, true); // true = show offline/cached state
    showPanels();

    // Ensure autocomplete works even on cold-start offline
    const statsArray = Array.isArray(initialData.statistics) ? initialData.statistics : [];
    autocompleteMonitor.setStatistics(statsArray);
    autocompleteMonitor.start();
  }

  // Update button state initially to Offline on cold start
  const btnLiveInit = document.getElementById("btn-connect-server");
  if (btnLiveInit) {
    btnLiveInit.innerHTML = '<span class="live-dot"></span> Offline';
    btnLiveInit.className = "btn btn-live";
  }

  // Auto-connect if connection settings are "live"
  const connSettings = reader.getConnectionSettings();
  const serverUrlInput = document.getElementById("server-url") as HTMLInputElement;
  if (serverUrlInput && connSettings.url) {
    serverUrlInput.value = connSettings.url;
  }
  if (connSettings.mode === "live") {
    attemptServerConnection(connSettings.url);
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

  // Project selector dropdown dropdown
  const select = document.getElementById("project-select") as HTMLSelectElement;
  const btnRemoveProject = document.getElementById("btn-remove-project") as HTMLButtonElement;

  if (select) {
    select.onchange = () => {
      const selected = select.value;
      if (btnRemoveProject) {
        btnRemoveProject.style.display = selected ? "block" : "none";
      }

      if (selected) {
        linkedProjectName = selected;
        Office.context.document.settings.set("StatSyncLinkedProject", selected);
        Office.context.document.settings.saveAsync();

        if (docDir) {
          reader.setDirectoryMapping(docDir, selected);
        }

        reader.loadFromCache(selected);
        const data = reader.getData();
        if (data) {
          renderAll(data);
          updateStatus(data, true);
          const statsArray = Array.isArray(data.statistics) ? data.statistics : [];
          autocompleteMonitor.setStatistics(statsArray);
        } else {
          document.getElementById("models-list")!.innerHTML = '<div class="empty-state">No statistics cached for this project. Connect to server or load file.</div>';
          document.getElementById("tables-list")!.innerHTML = '<div class="empty-state">No tables cached.</div>';
          const tablesPanel = document.getElementById("tables-panel");
          if (tablesPanel) tablesPanel.style.display = "none";
          setStatus(`Project '${selected}' loaded (no cached data)`, "info");
        }
      } else {
        linkedProjectName = null;
        Office.context.document.settings.remove("StatSyncLinkedProject");
        Office.context.document.settings.saveAsync();
        const tablesPanel = document.getElementById("tables-panel");
        if (tablesPanel) tablesPanel.style.display = "none";
        setStatus("Project link cleared", "info");
      }
    };
  }

  if (btnRemoveProject) {
    btnRemoveProject.onclick = (e) => {
      e.preventDefault();
      const selected = select.value;
      if (selected) {
        localStorage.removeItem(`statsync_cache_${selected}`);
        populateProjectDropdown();
        if (linkedProjectName === selected) {
          select.value = "";
          select.dispatchEvent(new Event("change"));
        }
      }
    };
  }

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
      setStatus("Automatic syncing paused", "warning");
    } else {
      btnPauseSync.textContent = "⏸ Pause Automatic Syncing";
      btnPauseSync.classList.remove("btn-primary");
      btnPauseSync.classList.add("btn-outline");
      setStatus("Resuming automatic sync", "success");
    }

    // Refresh UI immediately to reflect the new pause state
    const data = reader.getData();
    if (data) {
      renderAll(data);
      updateStatus(data, !isConnected || isAutoSyncPaused);

      if (btnManualSync) btnManualSync.style.display = (isAutoSyncPaused || !isConnected) ? "block" : "none";
    }
  };

  btnManualSync.onclick = async (e) => {
    e.preventDefault();
    if (isManualSyncing) return;
    isManualSyncing = true;
    btnManualSync.disabled = true;
    const originalText = btnManualSync.innerHTML;
    btnManualSync.innerHTML = '🔄 Syncing...';

    const data = reader.getData();
    // Helper to get groups
    const getGroups = (d: StatSyncProject | null) => {
      const s = new Set<string>();
      if (d && d.statistics) d.statistics.forEach(st => s.add(st.group || "Ungrouped"));
      return s;
    };
    const oldGroups = getGroups(data);

    try {
      if (isConnected) {
        await reader.refresh(true);
      }

      const newData = reader.getData();
      const newGroups = getGroups(newData);

      // Compute structural changes for the report
      let added = 0;
      newGroups.forEach(g => { if (!oldGroups.has(g)) added++; });
      let deleted = 0;
      oldGroups.forEach(g => { if (!newGroups.has(g)) deleted++; });

      if (newData) {
        renderAll(newData);
        updateStatus(newData);
      }

      // Explicitly update Word document tags
      const res = await inserter.updateAllLinks((id) => reader.getStatistic(id), (id) => reader.getTable(id));
      showUpdateResult(res, undefined, added, deleted);
      setStatus("✓ Sync complete", "success");
    } catch (err) {
      console.error("Manual sync failed", err);
      setStatus(`Manual sync failed: ${err}`, "error");
    } finally {
      isManualSyncing = false;
      btnManualSync.innerHTML = originalText;
      btnManualSync.disabled = false;
    }
  };
}

// ============================================================
// AUTOCOMPLETE
// ============================================================

function setupAutocomplete(): void {
  autocompleteMonitor.onSuggestions((suggestions, triggerText) => {
    if (triggerText && !dialog) {
      openAutocompleteDialog(triggerText);
    }
  });
}

function openAutocompleteDialog(triggerText: string): void {
  currentReplaceText = triggerText;
  autocompleteMonitor.stop(); // pause polling while dialog is open

  // Share statistics data with the dialog via localStorage
  const allStats = reader.getData()?.statistics || [];
  try {
    localStorage.setItem("statsync_dialog_data", JSON.stringify(allStats));
    // Pass the typed search query (everything after {{)
    const queryMatch = triggerText.match(/\{\{([^}]*)/);
    const query = queryMatch ? queryMatch[1].trim() : "";
    localStorage.setItem("statsync_dialog_prefill", query);
  } catch (e) {
    console.error("Failed to set localStorage items for dialog", e);
  }

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
  let data;
  try {
    data = JSON.parse(arg.message);
  } catch (err) {
    console.error("Failed to parse dialog message:", err);
    if (dialog) { dialog.close(); }
    dialog = null;
    autocompleteMonitor.ignoreCurrent();
    autocompleteMonitor.dismiss();
    setTimeout(() => { autocompleteMonitor.start(); }, 1000);
    return;
  }

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

      let storedCustom = null;
      let storedFields = null;
      try {
        storedCustom = localStorage.getItem("statsync_dialog_custom_formatted");
        if (storedCustom) {
          localStorage.removeItem("statsync_dialog_custom_formatted");
        }
        storedFields = localStorage.getItem("statsync_dialog_custom_fields");
        if (storedFields) {
          localStorage.removeItem("statsync_dialog_custom_fields");
        }
      } catch (e) {
        console.error("Failed to read/clear dialog custom formatting from localStorage", e);
      }

      if (storedCustom && storedCustom.length > 0) {
        statToInsert.formatted = storedCustom;
      } else if (data.customFormatted && data.customFormatted.length > 0) {
        statToInsert.formatted = data.customFormatted;
      }

      try {
        await inserter.replaceTextAndInsert(
          currentReplaceText,
          statToInsert,
          "full",
          undefined,
          storedFields || undefined
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
  const searchPanel = document.getElementById("search-panel");
  const updatePanel = document.getElementById("update-panel");
  if (searchPanel) searchPanel.style.display = "block";
  if (updatePanel) updatePanel.style.display = "block";

  const modelsPanel = document.getElementById("models-panel");
  if (modelsPanel) modelsPanel.style.display = "none";
}

function renderAll(data: StatSyncProject): void {
  const currentProjectName = data.project?.name || null;
  if (currentProjectName !== lastProjectName) {
    cardStates.clear();
    lastProjectName = currentProjectName;
  }
  renderFilterChips(data);
  renderModelCards(data);
  renderTables(data);
  filterModels();
}

function renderFilterChips(data: StatSyncProject): void {
  const container = document.getElementById("filter-chips");
  if (!container) return;
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
    const modelsPanel = document.getElementById("models-panel");
    if (modelsPanel) modelsPanel.style.display = "block";
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
      const modelsPanel = document.getElementById("models-panel");
      if (modelsPanel) modelsPanel.style.display = "block";
      filterModels();
    });
    container.appendChild(chip);
  });
}

function renderTables(data: StatSyncProject): void {
  const container = document.getElementById("tables-list");
  const panel = document.getElementById("tables-panel");
  if (!container || !panel) return;

  container.innerHTML = "";

  const tablesArray = Array.isArray(data.tables) ? data.tables : [];
  if (tablesArray.length === 0) {
    panel.style.display = "none";
    return;
  }

  panel.style.display = "block";

  tablesArray.forEach((table) => {
    const item = document.createElement("div");
    item.className = "table-item";

    const info = document.createElement("div");
    info.className = "table-item-info";

    const caption = document.createElement("div");
    caption.className = "table-item-caption";
    caption.textContent = table.caption || "Table";
    info.appendChild(caption);

    const meta = document.createElement("div");
    meta.className = "table-item-meta";
    const numRows = table.rows.length;
    const numCols = table.rows[0]?.cells.length || (table.headers[0]?.length || 0);
    meta.textContent = `${numRows} rows × ${numCols} columns`;
    info.appendChild(meta);

    item.appendChild(info);

    const btn = document.createElement("button");
    btn.className = "btn btn-small btn-primary";
    btn.textContent = "Insert";
    btn.addEventListener("click", async () => {
      setStatus(`Inserting table: ${table.caption || "Table"}...`, "info");
      try {
        await inserter.insertTable(table);
        setStatus(`✓ Inserted table: ${table.caption || "Table"}`, "success");
      } catch (err) {
        console.error("Failed to insert table:", err);
        setStatus(`Failed to insert table: ${err}`, "error");
      }
    });
    item.appendChild(btn);

    container.appendChild(item);
  });
}

function renderModelCards(data: StatSyncProject): void {
  const container = document.getElementById("models-list");
  if (!container) return;
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

  const countEl = document.getElementById("stat-count");
  if (countEl) countEl.textContent = `${totalStats} stats`;
}

function createModelCard(groupName: string, stats: StatisticEntry[]): HTMLElement {
  const card = document.createElement("div");
  card.className = "model-card";
  card.dataset.group = groupName.toLowerCase();
  card.dataset.types = [...new Set(stats.map((s) => s.type))].join(",");

  const primaryType = stats[0].type;
  const config = getFieldConfig(primaryType);

  const statTypes = [...new Set(stats.map((s) => s.type))];
  const subtitle = stats.length === 1
    ? config.label
    : `${stats.length} statistics · ${statTypes.map((t) => getFieldConfig(t).label).join(", ")}`;

  const header = document.createElement("div");
  header.className = "model-card-header";
  header.innerHTML = `
    <span class="model-card-chevron">▶</span>
    <span class="model-card-icon">${config.icon}</span>
    <div class="model-card-info">
      <div class="model-card-title">${escapeHtml(groupName)}</div>
      <div class="model-card-subtitle">${escapeHtml(subtitle)}</div>
    </div>
    <span class="model-card-badge">${stats.length}</span>
  `;

  header.addEventListener("click", () => {
    card.classList.toggle("expanded");
  });
  card.appendChild(header);

  const body = document.createElement("div");
  body.className = "model-card-body";

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
      let displayLabel = stat.label.replace(groupName + " - ", "").replace(groupName + " -", "");
      option.textContent = `${getFieldConfig(stat.type).icon} ${displayLabel}`;
      if (stat.id === state.selectedCoefId) option.selected = true;
      select.appendChild(option);
    });

    select.addEventListener("change", () => {
      state.selectedCoefId = select.value;
      const newStat = stats.find((s) => s.id === select.value)!;
      const newConfig = getFieldConfig(newStat.type);
      state.checkedFields = new Set<string>();
      newConfig.fields.forEach((f) => {
        if (f.apaDefault) state.checkedFields.add(f.key);
      });
      renderCardBody(body, groupName, stats, state);
    });

    selectorDiv.appendChild(select);
    body.appendChild(selectorDiv);
  }

  renderCardBody(body, groupName, stats, state);
  card.appendChild(body);

  return card;
}

function renderCardBody(
  body: HTMLElement,
  groupName: string,
  stats: StatisticEntry[],
  state: CardState
): void {
  const existingPreview = body.querySelector(".preview-box");
  if (existingPreview) existingPreview.remove();

  const selectedStat = stats.find((s) => s.id === state.selectedCoefId) || stats[0];

  const previewBox = document.createElement("div");
  previewBox.className = "preview-box";
  previewBox.innerHTML = `
    <div class="preview-label">Preview</div>
    <div class="preview-text"></div>
  `;
  body.appendChild(previewBox);

  const previewText = previewBox.querySelector(".preview-text")!;
  previewText.innerHTML = markupToHtml(selectedStat.formatted);
}

function filterModels(): void {
  const searchInput = document.getElementById("search-input") as HTMLInputElement;
  if (!searchInput) return;
  const query = searchInput.value.toLowerCase();
  const cards = document.querySelectorAll(".model-card") as NodeListOf<HTMLElement>;

  let visibleCount = 0;

  cards.forEach((card) => {
    const group = card.dataset.group || "";
    const types = card.dataset.types || "";
    const matchesSearch = query === "" || group.includes(query);
    const matchesType = activeTypeFilter === null || types.includes(activeTypeFilter);
    const visible = matchesSearch && matchesType && (activeTypeFilter !== "none" || query.length > 0);
    card.style.display = visible ? "block" : "none";
    if (visible) visibleCount++;
  });

  const countEl = document.getElementById("stat-count");
  if (countEl) {
    const total = cards.length;
    countEl.textContent = query || (activeTypeFilter && activeTypeFilter !== "none")
      ? `${visibleCount}/${total} shown`
      : `${total} models`;
  }
}

// ============================================================
// HELPERS
// ============================================================

function setStatus(message: string, type: string = "info"): void {
  const statusEl = document.getElementById("status");
  if (statusEl) statusEl.textContent = message;
}

function updateStatus(data: StatSyncProject, isOfflineOrPaused: boolean = false): void {
  const statsArray = Array.isArray(data.statistics) ? data.statistics : [];
  const statusMsg = !isConnected
    ? `🔴 Offline (${statsArray.length} cached)`
    : (isAutoSyncPaused ? `⏸ Paused (${statsArray.length} stats)` : `${statsArray.length} statistics`);

  setStatus(statusMsg);

  const projectNameEl = document.getElementById("project-name");
  if (projectNameEl) {
    const current = data.project?.name || "Untitled";
    if (linkedProjectName && linkedProjectName !== current && isConnected) {
      projectNameEl.innerHTML = `⚠️ <span style="color:var(--error)">Wrong Project: ${escapeHtml(current)}</span> (Expected: ${escapeHtml(linkedProjectName)})`;
    } else {
      const name = linkedProjectName || current;
      if (!isConnected) {
        projectNameEl.innerHTML = `${escapeHtml(name)} <small>(Offline)</small>`;
      } else {
        projectNameEl.textContent = name;
      }
    }
  }

  const lastSyncEl = document.getElementById("last-sync");
  if (lastSyncEl) {
    lastSyncEl.textContent = !isConnected
      ? "Last Sync: " + new Date(data.generated_at || Date.now()).toLocaleTimeString()
      : new Date().toLocaleTimeString();
  }
}

function showUpdateResult(
  result: { updated: number, failed: number, unchanged: number } | null,
  error?: string,
  addedModels: number = 0,
  deletedModels: number = 0
): void {
  const div = document.getElementById("update-result");
  if (!div) return;

  // Kill existing timer
  if (resultHideTimer) {
    clearTimeout(resultHideTimer);
  }

  div.style.display = "block";

  if (error) {
    div.className = "update-result error";
    div.textContent = error;
    div.style.display = "block";
  } else {
    const updatedCount = result ? result.updated : 0;
    if (updatedCount > 0 || addedModels > 0 || deletedModels > 0) {
      div.className = "update-result success";
      div.innerHTML = `✅ Updated: ${updatedCount} · ➕ Added: ${addedModels} · 🗑️ Deleted: ${deletedModels}`;
      div.style.display = "block";
    } else {
      div.style.display = "none";
      return;
    }
  }

  resultHideTimer = setTimeout(() => {
    div.style.display = "none";
    resultHideTimer = null;
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

function escapeHtml(text: string): string {
  const div = document.createElement("div");
  div.textContent = text;
  return div.innerHTML;
}
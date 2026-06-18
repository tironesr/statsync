// ============================================================
// DATA SOURCE — reads from file or live server
// ============================================================

import { StatSyncProject, StatisticEntry, TableEntry } from "../models/types";

export enum DataSourceType {
  FILE = "file",
  SERVER = "server",
}

export class StatSyncReader {
  private data: StatSyncProject | null = null;
  private sourceType: DataSourceType = DataSourceType.FILE;
  private serverUrl: string = "http://localhost:8877";
  private pollInterval: number | null = null;
  private onUpdateCallbacks: Array<(data: StatSyncProject, isLive: boolean) => void> = [];
  private isLive: boolean = false;

  private isStorageAvailable(): boolean {
    try {
      return typeof window !== "undefined" && typeof window.localStorage !== "undefined" && window.localStorage !== null;
    } catch (e) {
      return false;
    }
  }

  constructor() {
    // Explicitly do NOT load from cache automatically.
    // The taskpane must explicitly call loadFromCache(projectName) based on document bindings.
  }

  // --- Persistence for Offline Mode ---
  public loadFromCache(projectName?: string): void {
    if (!this.isStorageAvailable()) return;
    const key = projectName ? `statsync_cache_${projectName}` : "statsync_cached_project";
    try {
      const cached = localStorage.getItem(key);
      if (cached) {
        const parsed = JSON.parse(cached) as StatSyncProject;
        this.data = parsed;
      }
    } catch (e) {
      console.error("Failed to load StatSync cache", e);
    }
  }

  private saveToCache(): void {
    if (!this.isStorageAvailable()) return;
    if (this.data) {
      try {
        // Global last-seen cache
        localStorage.setItem("statsync_cached_project", JSON.stringify(this.data));

        // Project-specific cache
        if (this.data.project?.name) {
          localStorage.setItem(`statsync_cache_${this.data.project.name}`, JSON.stringify(this.data));
        }
      } catch (e) {
        console.error("Failed to save StatSync cache", e);
      }
    }
  }

  // --- Load from file (user picks a .statsync.json) ---
  async loadFromFile(file: File): Promise<StatSyncProject> {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = (e) => {
        try {
          const text = e.target?.result as string;
          this.data = JSON.parse(text) as StatSyncProject;
          if (this.data) {
            if (!Array.isArray(this.data.statistics)) this.data.statistics = [];
            if (!Array.isArray(this.data.tables)) this.data.tables = [];
          }
          this.sourceType = DataSourceType.FILE;
          this.notifyUpdate();
          resolve(this.data);
        } catch (err) {
          reject(new Error(`Failed to parse StatSync file: ${err}`));
        }
      };
      reader.onerror = () => reject(new Error("Failed to read file"));
      reader.readAsText(file);
    });
  }

  // --- Load from JSON string (e.g., from clipboard or drag-drop) ---
  loadFromJson(json: string): StatSyncProject {
    this.data = JSON.parse(json) as StatSyncProject;
    if (this.data) {
      if (!Array.isArray(this.data.statistics)) this.data.statistics = [];
      if (!Array.isArray(this.data.tables)) this.data.tables = [];
    }
    this.sourceType = DataSourceType.FILE;
    this.notifyUpdate();
    return this.data;
  }

  // --- Connect to live R server ---
  async connectToServer(url?: string): Promise<boolean> {
    if (url) this.serverUrl = url;

    try {
      const response = await fetch(`${this.serverUrl}/status`);
      if (!response.ok) throw new Error("Server not responding");

      const status = await response.json();
      if (!status.active) throw new Error("Server not active");

      // Initial load - force notify to trigger UI updates and document link syncs on startup
      await this.refresh(true);
      this.sourceType = DataSourceType.SERVER;
      this.isLive = true;

      return true;
    } catch (err) {
      console.error("Failed to connect to StatSync server:", err);
      this.isLive = false;
      return false;
    }
  }

  public async refresh(force: boolean = false): Promise<void> {
    try {
      const response = await fetch(`${this.serverUrl}/stats`);
      if (!response.ok) throw new Error("Failed to fetch stats");

      const newData = (await response.json()) as StatSyncProject;
      if (newData) {
        if (!Array.isArray(newData.statistics)) newData.statistics = [];
        if (!Array.isArray(newData.tables)) newData.tables = [];
      }

      this.isLive = true;

      let droppedSomething = false;
      let destroyed = (newData as any).destroyed_projects;
      if (destroyed) {
        if (!Array.isArray(destroyed)) destroyed = [destroyed];
        destroyed.forEach((p: string) => {
          if (localStorage.getItem(`statsync_cache_${p}`)) {
            localStorage.removeItem(`statsync_cache_${p}`);
            droppedSomething = true;
          }
        });
      }

      // Check if data actually changed
      const newHash = JSON.stringify(newData.generated_at);
      const oldHash = this.data
        ? JSON.stringify(this.data.generated_at)
        : null;

      if (force || newHash !== oldHash || droppedSomething) {
        if (this.data === null || this.data.project?.name !== (newData as any).project?.name) {
             this.data = newData;
        } else if (newHash !== oldHash) {
             this.data = newData;
        }
        
        // If the current active project was destroyed, but the server is now serving "StatSync Project" empty state:
        // Well, newData will just be the empty state, so `this.data = newData` is correct.
        
        this.notifyUpdate();
      }
    } catch (err) {
      if (this.isLive) {
        this.isLive = false;
        this.notifyUpdate(); // Notify status change even if data haven't changed
      }
      throw err;
    }
  }

  // --- Polling for live updates ---
  startPolling(intervalMs: number = 2000): void {
    this.stopPolling();
    this.pollInterval = window.setInterval(async () => {
      try {
        await this.refresh();
      } catch (err) {
        console.warn("Poll failed:", err);
      }
    }, intervalMs);
  }

  stopPolling(): void {
    if (this.pollInterval !== null) {
      window.clearInterval(this.pollInterval);
      this.pollInterval = null;
    }
  }

  // --- Data access ---
  getData(): StatSyncProject | null {
    return this.data;
  }

  getStatistic(id: string): StatisticEntry | undefined {
    return this.data?.statistics.find((s) => s.id === id);
  }

  getStatisticsByGroup(): Map<string, StatisticEntry[]> {
    const groups = new Map<string, StatisticEntry[]>();
    if (!this.data) return groups;

    for (const stat of this.data.statistics) {
      const group = stat.group || "Ungrouped";
      if (!groups.has(group)) groups.set(group, []);
      groups.get(group)!.push(stat);
    }
    return groups;
  }

  getTable(id: string): TableEntry | undefined {
    return this.data?.tables.find((t) => t.id === id);
  }

  getTables(): TableEntry[] {
    return this.data?.tables || [];
  }

  searchStatistics(query: string): StatisticEntry[] {
    if (!this.data) return [];
    const q = query.toLowerCase();
    return this.data.statistics.filter(
      (s) =>
        s.id.toLowerCase().includes(q) ||
        s.label.toLowerCase().includes(q) ||
        s.formatted.toLowerCase().includes(q)
    );
  }

  // --- Callbacks ---
  onUpdate(callback: (data: StatSyncProject, isLive: boolean) => void): void {
    this.onUpdateCallbacks.push(callback);
  }

  private notifyUpdate(): void {
    if (this.data) {
      this.saveToCache();
      this.onUpdateCallbacks.forEach((cb) => cb(this.data!, this.isLive));
    }
  }

  // --- Project Directory Mappings ---
  getDirectoryMapping(dir: string): string | null {
    if (!this.isStorageAvailable()) return null;
    try {
      const mappingsStr = localStorage.getItem("statsync_directory_mappings");
      if (mappingsStr) {
        const mappings = JSON.parse(mappingsStr);
        return mappings[dir] || null;
      }
    } catch (e) {
      console.error("Failed to parse directory mappings", e);
    }
    return null;
  }

  setDirectoryMapping(dir: string, projectName: string): void {
    if (!this.isStorageAvailable()) return;
    try {
      const mappingsStr = localStorage.getItem("statsync_directory_mappings");
      let mappings: Record<string, string> = {};
      if (mappingsStr) {
        try {
          mappings = JSON.parse(mappingsStr);
        } catch (e) {
          console.error("Failed to parse directory mappings for saving", e);
        }
      }
      mappings[dir] = projectName;
      localStorage.setItem("statsync_directory_mappings", JSON.stringify(mappings));
    } catch (e) {
      console.error("Failed to set directory mapping", e);
    }
  }

  // --- Cached Projects List ---
  getCachedProjects(): string[] {
    const projects: {name: string, time: number}[] = [];
    if (!this.isStorageAvailable()) return [];
    try {
      for (let i = 0; i < localStorage.length; i++) {
        const key = localStorage.key(i);
        if (key && key.startsWith("statsync_cache_")) {
          const projectName = key.replace("statsync_cache_", "");
          if (projectName) {
            let time = 0;
            try {
              const dataStr = localStorage.getItem(key);
              if (dataStr) {
                const data = JSON.parse(dataStr);
                if (data.generated_at) {
                  time = new Date(data.generated_at).getTime();
                }
              }
            } catch (err) {
              // Ignore parsing errors for individual projects
            }
            projects.push({ name: projectName, time });
          }
        }
      }
    } catch (e) {
      console.error("Failed to get cached projects", e);
    }
    
    // Sort descending by time (most recent first)
    projects.sort((a, b) => b.time - a.time);
    return projects.map(p => p.name);
  }

  // --- Saved Connection Settings ---
  saveConnectionSettings(url: string, mode: "live" | "offline"): void {
    if (!this.isStorageAvailable()) return;
    try {
      localStorage.setItem("statsync_server_url", url);
      localStorage.setItem("statsync_connection_mode", mode);
    } catch (e) {
      console.error("Failed to save connection settings", e);
    }
  }

  getConnectionSettings(): { url: string; mode: "live" | "offline" } {
    if (!this.isStorageAvailable()) {
      return { url: "http://localhost:8877", mode: "offline" };
    }
    try {
      const url = localStorage.getItem("statsync_server_url") || "http://localhost:8877";
      const mode = (localStorage.getItem("statsync_connection_mode") || "offline") as "live" | "offline";
      return { url, mode };
    } catch (e) {
      console.error("Failed to get connection settings", e);
      return { url: "http://localhost:8877", mode: "offline" };
    }
  }

  // --- Cleanup ---
  dispose(): void {
    this.stopPolling();
    this.onUpdateCallbacks = [];
  }
}
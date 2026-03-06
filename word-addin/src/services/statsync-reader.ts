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
  private onUpdateCallbacks: Array<(data: StatSyncProject) => void> = [];

  // --- Load from file (user picks a .statsync.json) ---
  async loadFromFile(file: File): Promise<StatSyncProject> {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = (e) => {
        try {
          const text = e.target?.result as string;
          this.data = JSON.parse(text) as StatSyncProject;
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

      // Initial load
      await this.fetchFromServer();
      this.sourceType = DataSourceType.SERVER;

      return true;
    } catch (err) {
      console.error("Failed to connect to StatSync server:", err);
      return false;
    }
  }

  private async fetchFromServer(): Promise<void> {
    const response = await fetch(`${this.serverUrl}/stats`);
    if (!response.ok) throw new Error("Failed to fetch stats");

    const newData = (await response.json()) as StatSyncProject;
    if (newData) {
      if (!Array.isArray(newData.statistics)) newData.statistics = [];
      if (!Array.isArray(newData.tables)) newData.tables = [];
    }

    // Check if data actually changed
    const newHash = JSON.stringify(newData.generated_at);
    const oldHash = this.data
      ? JSON.stringify(this.data.generated_at)
      : null;

    if (newHash !== oldHash) {
      this.data = newData;
      this.notifyUpdate();
    }
  }

  // --- Polling for live updates ---
  startPolling(intervalMs: number = 2000): void {
    this.stopPolling();
    this.pollInterval = window.setInterval(async () => {
      try {
        await this.fetchFromServer();
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
  onUpdate(callback: (data: StatSyncProject) => void): void {
    this.onUpdateCallbacks.push(callback);
  }

  private notifyUpdate(): void {
    if (this.data) {
      this.onUpdateCallbacks.forEach((cb) => cb(this.data!));
    }
  }

  // --- Cleanup ---
  dispose(): void {
    this.stopPolling();
    this.onUpdateCallbacks = [];
  }
}
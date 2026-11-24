import { execFile } from "node:child_process";
import { promisify } from "node:util";

// Fixed bundle path rather than the PATH symlink: Raycast's environment has no user PATH.
export const CLI = "/Applications/Stasis.app/Contents/Helpers/stasis";

/** Mirrors `AppSummary` in StasisCore; `stasis list --json` is the contract. */
export type AppState = "running" | "not-responding" | "partial" | "paused";

export interface App {
  pid: number;
  name: string;
  bundleIdentifier: string | null;
  bundlePath: string | null;
  state: AppState;
  residentBytes: number;
  processCount: number;
  pausedCount: number;
}

const execFileAsync = promisify(execFile);

/** Runs the CLI; rejects with its stderr text on a non-zero exit so callers can show it verbatim. */
export async function stasis(...args: string[]): Promise<string> {
  try {
    const { stdout } = await execFileAsync(CLI, args);
    return stdout.trim();
  } catch (error) {
    const e = error as NodeJS.ErrnoException & { stderr?: string };
    if (e.code === "ENOENT") {
      throw new Error("Stasis is not installed in /Applications. Run `make install` in the Stasis repo.");
    }
    throw new Error(e.stderr?.trim() || e.message);
  }
}

export async function listApps(): Promise<App[]> {
  return JSON.parse(await stasis("list", "--json")) as App[];
}

export function formatMemory(bytes: number): string {
  if (bytes >= 1e9) return `${(bytes / 1e9).toFixed(2)} GB`;
  if (bytes >= 1e6) return `${(bytes / 1e6).toFixed(0)} MB`;
  return `${(bytes / 1e3).toFixed(0)} KB`;
}

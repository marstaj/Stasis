import { showHUD, showToast, Toast } from "@raycast/api";
import { stasis } from "./stasis";

/** Shared body of the no-view commands: HUD on success, toast with the CLI's message on failure. */
export async function runBulk(command: "pause-all" | "resume-all", ...flags: string[]) {
  try {
    const message = await stasis(command, ...flags);
    await showHUD(message);
  } catch (e) {
    await showToast({ style: Toast.Style.Failure, title: `${command} failed`, message: (e as Error).message });
  }
}

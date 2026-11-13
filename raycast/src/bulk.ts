import { showHUD, showToast, Toast } from "@raycast/api";
import { stasis } from "./stasis";

/** Shared body of the two no-view commands: HUD on success, toast with the CLI's message on failure. */
export async function runBulk(command: "pause-all" | "resume-all") {
  try {
    const message = await stasis(command);
    await showHUD(message);
  } catch (e) {
    await showToast({ style: Toast.Style.Failure, title: `${command} failed`, message: (e as Error).message });
  }
}

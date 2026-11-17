import { Action, ActionPanel, Alert, Color, confirmAlert, Icon, List, showToast, Toast } from "@raycast/api";
import { usePromise } from "@raycast/utils";
import { runBulk } from "./bulk";
import { App, formatMemory, listApps, stasis } from "./stasis";

type Verb = "pause" | "resume" | "kill";

const progressTitle: Record<Verb, string> = { pause: "Pausing", resume: "Resuming", kill: "Killing" };

/** Every app in one list; Enter toggles and the row stays where it is with its tag updated. */
export default function Command() {
  const { data, isLoading, revalidate } = usePromise(listApps, [], {
    onError: async (error) => {
      await showToast({ style: Toast.Style.Failure, title: "Could not list apps", message: error.message });
    },
  });

  // The CLI sorts paused apps first; here that would make a row jump on toggle, so memory order.
  const apps = [...(data ?? [])].sort((a, b) => b.residentBytes - a.residentBytes);

  async function run(verb: Verb, app: App) {
    const toast = await showToast({ style: Toast.Style.Animated, title: `${progressTitle[verb]} ${app.name}` });
    try {
      // The bundle id is unique and never ambiguous; the name may be a prefix of another app's.
      toast.title = await stasis(verb, app.bundleIdentifier ?? app.name);
      toast.style = Toast.Style.Success;
    } catch (e) {
      toast.style = Toast.Style.Failure;
      toast.title = `Could not ${verb} ${app.name}`;
      toast.message = (e as Error).message;
    }
    revalidate();
  }

  async function kill(app: App) {
    const confirmed = await confirmAlert({
      title: `Kill ${app.name}?`,
      message: "Unsaved work in it will be lost.",
      primaryAction: { title: "Kill", style: Alert.ActionStyle.Destructive },
    });
    if (confirmed) await run("kill", app);
  }

  async function bulk(command: "pause-all" | "resume-all") {
    await runBulk(command);
    revalidate();
  }

  return (
    <List isLoading={isLoading} searchBarPlaceholder="Pause or resume which app?">
      <List.EmptyView title="No running apps" />
      {apps.map((app) => {
        // Enter on a partially paused app resumes it, like the menu bar; Pause stays available under ⌘K.
        const primary = app.state === "running" ? "pause" : "resume";
        const secondary = primary === "pause" ? "resume" : "pause";
        return (
          <List.Item
            key={app.pid}
            title={app.name}
            icon={app.bundlePath ? { fileIcon: app.bundlePath } : Icon.AppWindow}
            accessories={[{ text: formatMemory(app.residentBytes) }, stateTag(app)]}
            actions={
              <ActionPanel>
                <ActionPanel.Section>
                  <Action title={capitalize(primary)} icon={verbIcon(primary)} onAction={() => run(primary, app)} />
                  {app.state === "partial" && (
                    <Action title={capitalize(secondary)} icon={verbIcon(secondary)} onAction={() => run(secondary, app)} />
                  )}
                  <Action title="Refresh" icon={Icon.ArrowClockwise} shortcut={{ modifiers: ["cmd"], key: "r" }} onAction={revalidate} />
                  <Action
                    title="Kill"
                    icon={Icon.XMarkCircle}
                    style={Action.Style.Destructive}
                    shortcut={{ modifiers: ["ctrl"], key: "x" }}
                    onAction={() => kill(app)}
                  />
                </ActionPanel.Section>
                <ActionPanel.Section>
                  <Action title="Pause All Apps" icon={Icon.Pause} shortcut={{ modifiers: ["cmd", "shift"], key: "p" }} onAction={() => bulk("pause-all")} />
                  <Action title="Resume All Apps" icon={Icon.Play} shortcut={{ modifiers: ["cmd", "shift"], key: "r" }} onAction={() => bulk("resume-all")} />
                </ActionPanel.Section>
              </ActionPanel>
            }
          />
        );
      })}
    </List>
  );
}

function verbIcon(verb: "pause" | "resume") {
  return verb === "pause" ? Icon.Pause : Icon.Play;
}

function stateTag(app: App): List.Item.Accessory {
  switch (app.state) {
    case "running":
      return { tag: { value: "Running", color: Color.SecondaryText } };
    case "partial":
      return { tag: { value: `${app.pausedCount}/${app.processCount} paused`, color: Color.Yellow } };
    case "paused":
      return { tag: { value: "Paused", color: Color.Orange } };
  }
}

function capitalize(word: string): string {
  return word[0].toUpperCase() + word.slice(1);
}

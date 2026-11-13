import { runBulk } from "./bulk";

export default async function Command() {
  await runBulk("resume-all");
}

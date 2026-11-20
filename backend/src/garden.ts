import { HttpError, isRecord, str } from "./http";

/**
 * The app sends a "garden snapshot" with every request: profile, beds, plants, inventory,
 * budget, recent journal, weather summary and active nudges. Its shape is defined by
 * GardenSnapshot in ios/Packages/GardenCore/Sources/GardenCore/Snapshot.swift.
 *
 * The backend does not need every field, so it only checks the few it reads and passes the
 * rest to the coach as JSON.
 */
export interface GardenContext {
  /** Compact JSON of the snapshot, as given to the coach. */
  json: string;
  /** The gardener's local date, YYYY-MM-DD. */
  today: string;
  timeZone: string;
  gardenerName: string;
}

const MAX_SNAPSHOT_CHARS = 150_000;
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

export function readGarden(value: unknown, now: Date = new Date()): GardenContext {
  if (value === undefined || value === null) {
    return {
      json: "{}",
      today: now.toISOString().slice(0, 10),
      timeZone: "UTC",
      gardenerName: "",
    };
  }
  if (!isRecord(value)) {
    throw new HttpError(400, "bad_garden", "`garden` must be an object.");
  }
  const json = JSON.stringify(value);
  if (json.length > MAX_SNAPSHOT_CHARS) {
    throw new HttpError(413, "garden_too_large", "The garden snapshot is too large.");
  }
  const today = str(value.today, 10);
  const gardener = isRecord(value.gardener) ? str(value.gardener.name, 80) : "";
  return {
    json,
    today: DATE_RE.test(today) ? today : now.toISOString().slice(0, 10),
    timeZone: str(value.timeZone, 64) || "UTC",
    gardenerName: gardener,
  };
}

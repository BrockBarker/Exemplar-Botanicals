import type Anthropic from "@anthropic-ai/sdk";
import { isRecord, num, oneOf, str } from "./http";
import {
  BED_KINDS,
  FACT_CATEGORIES,
  GROWTH_STAGES,
  INVENTORY_CATEGORIES,
  IRRIGATION_KINDS,
  JOURNAL_KINDS,
  MOISTURE_READINGS,
  SOIL_TYPES,
  SUN_EXPOSURES,
  type BedKind,
  type FactCategory,
  type GrowthStage,
  type InventoryCategory,
  type IrrigationKind,
  type JournalKind,
  type MoistureReading,
  type SoilType,
  type SunExposure,
} from "./vocab";

type Tool = Anthropic.Beta.Messages.BetaTool;

/**
 * Record-keeping tools. The coach calls them when the gardener mentions something worth
 * saving; the server answers "saved" right away and returns the normalized actions to the
 * app, which applies them to its on-device records (CoachAction in GardenCore).
 */
export const COACH_TOOLS: Tool[] = [
  {
    name: "log_journal_entry",
    description:
      "Save an entry in the garden journal. Call this whenever the gardener says they did something in the garden (watered, fed, foliar sprayed, mulched, staked, planted, transplanted, pruned, harvested, checked for pests or treated them, amended soil, checked soil moisture) or reports a notable observation, even in passing. Do not call it for plans or for advice you are giving.",
    input_schema: {
      type: "object",
      properties: {
        date: {
          type: "string",
          description: "Local date it happened, YYYY-MM-DD. Today's date from the garden context unless they said otherwise (e.g. yesterday).",
        },
        kind: { type: "string", enum: [...JOURNAL_KINDS] },
        what: { type: "string", description: "What was done or applied, e.g. 'fish emulsion' or 'deep watering'." },
        amount: { type: "string", description: "How much, e.g. '1 tbsp per gallon, 2 gallons'. Omit if unknown." },
        bed_name: { type: "string", description: "Bed name as in the garden context. Omit if none or unknown." },
        plant_name: { type: "string", description: "Plant name as in the garden context. Omit if none or unknown." },
        moisture: {
          type: "string",
          enum: [...MOISTURE_READINGS],
          description: "For moisture checks only: what the soil felt like about 2 inches down.",
        },
        notes: { type: "string" },
      },
      required: ["date", "kind", "what"],
      additionalProperties: false,
    },
  },
  {
    name: "update_plant",
    description:
      "Add a plant or update one already in the garden context. Call this when the gardener mentions planting something new, a variety name, a change in growth stage (first flowers, fruit set), staking or caging, how many they have, or pulling a plant out. Match existing plants by name.",
    input_schema: {
      type: "object",
      properties: {
        plant_name: { type: "string", description: "Name as the gardener calls it, e.g. 'Sungold tomato'." },
        crop: {
          type: "string",
          description: "Crop type id if it matches one: tomato, cherry_tomato, pepper, eggplant, cucumber, summer_squash, winter_squash, melon, corn, bush_bean, pole_bean, pea, lettuce, spinach, kale, chard, cabbage, broccoli, cauliflower, carrot, beet, radish, onion, garlic, potato, sweet_potato, okra, strawberry, blueberry, bramble, basil, perennial_herb, annual_herb, flower_annual, dahlia, rose, fruit_tree, citrus. Omit if none fits.",
        },
        bed_name: { type: "string" },
        stage: { type: "string", enum: [...GROWTH_STAGES] },
        planted_on: { type: "string", description: "YYYY-MM-DD" },
        staked: { type: "boolean", description: "True once it has a stake, cage or trellis." },
        count: { type: "integer" },
        removed: { type: "boolean", description: "True if the plant was pulled out or died." },
        notes: { type: "string" },
      },
      required: ["plant_name"],
      additionalProperties: false,
    },
  },
  {
    name: "update_bed",
    description:
      "Add a bed or container, or update one in the garden context, when the gardener mentions its soil type, sun, irrigation, mulch, size, or soil test results.",
    input_schema: {
      type: "object",
      properties: {
        bed_name: { type: "string" },
        kind: { type: "string", enum: [...BED_KINDS] },
        soil_type: { type: "string", enum: [...SOIL_TYPES] },
        sun: { type: "string", enum: [...SUN_EXPOSURES] },
        irrigation: { type: "string", enum: [...IRRIGATION_KINDS] },
        mulch: { type: "string", description: "Mulch type, e.g. 'straw', or 'none'." },
        area_sq_ft: { type: "number" },
        soil_ph: { type: "number" },
        soil_test_notes: { type: "string", description: "Other soil test results in plain words." },
        notes: { type: "string" },
      },
      required: ["bed_name"],
      additionalProperties: false,
    },
  },
  {
    name: "update_inventory",
    description:
      "Add or remove something in the gardener's inventory of fertilizers, amendments, foliar sprays, rock dusts, compost, mulch, biologicals, organic pest controls and tools. Call it when they say they have, bought or were given something, or used it up.",
    input_schema: {
      type: "object",
      properties: {
        action: { type: "string", enum: ["add", "remove"] },
        name: { type: "string", description: "e.g. 'Neptune's Harvest Fish & Seaweed'" },
        category: { type: "string", enum: [...INVENTORY_CATEGORIES] },
        quantity: { type: "string", description: "e.g. 'half a quart'" },
        notes: { type: "string" },
      },
      required: ["action", "name"],
      additionalProperties: false,
    },
  },
  {
    name: "update_budget",
    description: "Record the gardener's monthly gardening budget in US dollars when they mention it or it changes.",
    input_schema: {
      type: "object",
      properties: {
        monthly_dollars: { type: "number" },
        notes: { type: "string" },
      },
      required: ["monthly_dollars"],
      additionalProperties: false,
    },
  },
  {
    name: "remember_garden_fact",
    description:
      "Remember a lasting fact about the gardener or their garden that the other tools don't cover, e.g. 'collects rainwater in a 50-gallon barrel', 'dog digs in the north bed', 'prefers no animal-based products'. Don't use it for one-off events (use log_journal_entry) or facts already in the garden context.",
    input_schema: {
      type: "object",
      properties: {
        fact: { type: "string" },
        category: { type: "string", enum: [...FACT_CATEGORIES] },
      },
      required: ["fact"],
      additionalProperties: false,
    },
  },
];

export type CoachAction =
  | {
      type: "journal";
      summary: string;
      date: string;
      kind: JournalKind;
      what: string;
      amount: string;
      bedName: string;
      plantName: string;
      moisture: MoistureReading | null;
      notes: string;
    }
  | {
      type: "plant";
      summary: string;
      plantName: string;
      crop: string;
      bedName: string;
      stage: GrowthStage | null;
      plantedOn: string;
      staked: boolean | null;
      count: number | null;
      removed: boolean;
      notes: string;
    }
  | {
      type: "bed";
      summary: string;
      bedName: string;
      kind: BedKind | null;
      soilType: SoilType | null;
      sun: SunExposure | null;
      irrigation: IrrigationKind | null;
      mulch: string;
      areaSqFt: number | null;
      soilPH: number | null;
      soilTestNotes: string;
      notes: string;
    }
  | {
      type: "inventory";
      summary: string;
      action: "add" | "remove";
      name: string;
      category: InventoryCategory | null;
      quantity: string;
      notes: string;
    }
  | { type: "budget"; summary: string; monthlyDollars: number; notes: string }
  | { type: "fact"; summary: string; fact: string; category: FactCategory };

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

function date(v: unknown, fallback: string): string {
  const s = str(v, 10);
  return DATE_RE.test(s) ? s : fallback;
}

function bool(v: unknown): boolean | null {
  return typeof v === "boolean" ? v : null;
}

function label(kind: string): string {
  return kind.replace(/_/g, " ");
}

/**
 * Validates one tool call from the coach. Returns null (and the coach is told it failed)
 * when required fields are missing.
 */
export function normalizeAction(name: string, input: unknown, today: string): CoachAction | null {
  if (!isRecord(input)) return null;
  switch (name) {
    case "log_journal_entry": {
      const kind = oneOf(input.kind, JOURNAL_KINDS) ?? "other";
      const what = str(input.what, 200);
      if (!what) return null;
      const d = date(input.date, today);
      const bedName = str(input.bed_name, 80);
      const plantName = str(input.plant_name, 80);
      const where = plantName || bedName;
      return {
        type: "journal",
        summary: `Logged ${label(kind)}: ${what}${where ? ` (${where})` : ""}, ${d}`,
        date: d,
        kind,
        what,
        amount: str(input.amount, 120),
        bedName,
        plantName,
        moisture: oneOf(input.moisture, MOISTURE_READINGS),
        notes: str(input.notes, 500),
      };
    }
    case "update_plant": {
      const plantName = str(input.plant_name, 80);
      if (!plantName) return null;
      const removed = input.removed === true;
      const stage = oneOf(input.stage, GROWTH_STAGES);
      const count = num(input.count);
      return {
        type: "plant",
        summary: removed
          ? `Removed ${plantName} from your plants`
          : `Updated ${plantName}${stage ? ` (${label(stage)})` : ""}`,
        plantName,
        crop: str(input.crop, 40),
        bedName: str(input.bed_name, 80),
        stage,
        plantedOn: date(input.planted_on, ""),
        staked: bool(input.staked),
        count: count !== null && count > 0 ? Math.round(count) : null,
        removed,
        notes: str(input.notes, 500),
      };
    }
    case "update_bed": {
      const bedName = str(input.bed_name, 80);
      if (!bedName) return null;
      const area = num(input.area_sq_ft);
      const ph = num(input.soil_ph);
      return {
        type: "bed",
        summary: `Updated bed ${bedName}`,
        bedName,
        kind: oneOf(input.kind, BED_KINDS),
        soilType: oneOf(input.soil_type, SOIL_TYPES),
        sun: oneOf(input.sun, SUN_EXPOSURES),
        irrigation: oneOf(input.irrigation, IRRIGATION_KINDS),
        mulch: str(input.mulch, 80),
        areaSqFt: area !== null && area > 0 ? area : null,
        soilPH: ph !== null && ph >= 3 && ph <= 10 ? ph : null,
        soilTestNotes: str(input.soil_test_notes, 500),
        notes: str(input.notes, 500),
      };
    }
    case "update_inventory": {
      const action = oneOf(input.action, ["add", "remove"] as const);
      const itemName = str(input.name, 120);
      if (!action || !itemName) return null;
      return {
        type: "inventory",
        summary: action === "add" ? `Added ${itemName} to your inventory` : `Removed ${itemName} from your inventory`,
        action,
        name: itemName,
        category: oneOf(input.category, INVENTORY_CATEGORIES),
        quantity: str(input.quantity, 80),
        notes: str(input.notes, 300),
      };
    }
    case "update_budget": {
      const dollars = num(input.monthly_dollars);
      if (dollars === null || dollars < 0) return null;
      return {
        type: "budget",
        summary: `Set your monthly budget to $${Math.round(dollars)}`,
        monthlyDollars: dollars,
        notes: str(input.notes, 300),
      };
    }
    case "remember_garden_fact": {
      const fact = str(input.fact, 300);
      if (!fact) return null;
      return {
        type: "fact",
        summary: `Noted: ${fact}`,
        fact,
        category: oneOf(input.category, FACT_CATEGORIES) ?? "other",
      };
    }
    default:
      return null;
  }
}

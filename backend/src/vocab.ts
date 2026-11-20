// Shared vocabulary. These raw values must match the Swift enums in
// ios/Packages/GardenCore/Sources/GardenCore/Vocabulary.swift.

export const JOURNAL_KINDS = [
  "watering",
  "feeding",
  "foliar_spray",
  "amendment",
  "mulching",
  "staking",
  "planting",
  "transplanting",
  "pruning",
  "harvest",
  "moisture_check",
  "pest_or_disease",
  "observation",
  "other",
] as const;
export type JournalKind = (typeof JOURNAL_KINDS)[number];

export const INVENTORY_CATEGORIES = [
  "fertilizer",
  "amendment",
  "foliar",
  "rock_dust",
  "compost",
  "mulch",
  "biological",
  "pest_control",
  "tool",
  "other",
] as const;
export type InventoryCategory = (typeof INVENTORY_CATEGORIES)[number];

export const GROWTH_STAGES = ["seed", "seedling", "vegetative", "flowering", "fruiting", "mature", "dormant"] as const;
export type GrowthStage = (typeof GROWTH_STAGES)[number];

export const BED_KINDS = ["in_ground", "raised", "container", "row"] as const;
export type BedKind = (typeof BED_KINDS)[number];

export const SOIL_TYPES = ["sand", "sandy_loam", "loam", "silt_loam", "clay_loam", "clay", "potting_mix", "unknown"] as const;
export type SoilType = (typeof SOIL_TYPES)[number];

export const SUN_EXPOSURES = ["full_sun", "part_sun", "part_shade", "shade"] as const;
export type SunExposure = (typeof SUN_EXPOSURES)[number];

export const IRRIGATION_KINDS = ["hand", "hose", "soaker", "drip", "sprinkler", "rain_only"] as const;
export type IrrigationKind = (typeof IRRIGATION_KINDS)[number];

export const MOISTURE_READINGS = ["dry", "slightly_moist", "moist", "wet"] as const;
export type MoistureReading = (typeof MOISTURE_READINGS)[number];

export const FACT_CATEGORIES = [
  "soil",
  "water",
  "sun",
  "pests",
  "wildlife",
  "preference",
  "equipment",
  "history",
  "other",
] as const;
export type FactCategory = (typeof FACT_CATEGORIES)[number];

/** Ranking order for every recommendation: what they own, then free, then low cost, then branded. */
export const TIERS = ["owned", "free", "low_cost", "branded"] as const;
export type Tier = (typeof TIERS)[number];

export const DIAGNOSIS_OVERALL = [
  "healthy",
  "water_stress",
  "nutrient_deficiency",
  "nutrient_toxicity",
  "pest_or_disease",
  "other",
  "unclear",
] as const;

export const FINDING_CATEGORIES = [
  "underwatering",
  "overwatering",
  "deficiency",
  "toxicity",
  "ph_lockout",
  "pest",
  "disease",
  "environmental",
  "other",
] as const;

export const CONFIDENCE = ["high", "medium", "low"] as const;
export const LIKELIHOOD = ["likely", "possible", "unlikely"] as const;

/**
 * Turns a coach reply (light Markdown) into plain text that sounds right when read aloud.
 * Mirrors SpeechText.plain(_:) in GardenCore so both sides agree on what gets spoken.
 */
export function speechText(markdown: string): string {
  let t = markdown.replace(/\r\n/g, "\n");
  t = t.replace(/```[\s\S]*?```/g, " "); // code blocks
  t = t.replace(/`([^`]*)`/g, "$1"); // inline code
  t = t.replace(/!\[([^\]]*)\]\([^)]*\)/g, "$1"); // images
  t = t.replace(/\[([^\]]+)\]\([^)]*\)/g, "$1"); // links
  t = t.replace(/^\s{0,3}#{1,6}\s+/gm, ""); // headings
  t = t.replace(/^\s*[-*+]\s+/gm, ""); // bullets
  t = t.replace(/^\s*(\d+)[.)]\s+/gm, "$1. "); // numbered lists
  t = t.replace(/(\*\*|__)(.*?)\1/g, "$2"); // bold
  t = t.replace(/(\*|_)(\S(?:.*?\S)?)\1/g, "$2"); // italics
  t = t.replace(/°F/g, " degrees");
  t = t.replace(/[ \t]+/g, " ");
  t = t.replace(/\n{2,}/g, "\n\n");
  return t.trim();
}

export function clip(text: string, max: number): string {
  if (text.length <= max) return text;
  const cut = text.slice(0, max);
  const lastStop = Math.max(cut.lastIndexOf(". "), cut.lastIndexOf("\n"));
  return (lastStop > max * 0.6 ? cut.slice(0, lastStop + 1) : cut).trim();
}

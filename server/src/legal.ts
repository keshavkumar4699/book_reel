import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

import { escapeHtml } from "./social/shares.js";

/**
 * The privacy policy and terms (Production plan A5), served at /privacy and
 * /terms from the same Markdown files the app shows (app/assets/legal), so
 * there is one text to keep up to date. In the server image they are copied
 * to LEGAL_DIR.
 */
export const LEGAL_DOCS = ["privacy", "terms"] as const;
export type LegalDoc = (typeof LEGAL_DOCS)[number];

export function legalDir(env: NodeJS.ProcessEnv = process.env): string {
  return env.LEGAL_DIR ?? resolve(process.cwd(), "../app/assets/legal");
}

const cache = new Map<string, string>();

/** The document's Markdown, or undefined when it isn't there. */
export function readLegal(doc: LegalDoc, dir = legalDir()): string | undefined {
  const path = resolve(dir, `${doc}.md`);
  const hit = cache.get(path);
  if (hit !== undefined) return hit;
  if (!existsSync(path)) return undefined;
  const text = readFileSync(path, "utf8");
  cache.set(path, text);
  return text;
}

/** Inline Markdown: **bold** only (everything is escaped first). */
const inline = (s: string) => escapeHtml(s).replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>");

/**
 * The small part of Markdown these documents use: # and ## headings,
 * paragraphs, "- " lists, tables and **bold**.
 */
export function markdownToHtml(md: string): string {
  const out: string[] = [];
  const lines = md.replace(/\r\n/g, "\n").split("\n");
  let para: string[] = [];
  let list: string[] = [];
  let table: string[][] = [];
  const flush = () => {
    if (para.length) out.push(`<p>${inline(para.join(" "))}</p>`);
    if (list.length) out.push(`<ul>${list.map((l) => `<li>${inline(l)}</li>`).join("")}</ul>`);
    if (table.length) {
      const [head, ...rows] = table;
      out.push(
        `<table><thead><tr>${head!.map((c) => `<th>${inline(c)}</th>`).join("")}</tr></thead><tbody>` +
          rows.map((r) => `<tr>${r.map((c) => `<td>${inline(c)}</td>`).join("")}</tr>`).join("") +
          `</tbody></table>`,
      );
    }
    para = [];
    list = [];
    table = [];
  };
  for (const raw of lines) {
    const line = raw.trimEnd();
    if (!line.trim()) {
      flush();
    } else if (line.startsWith("## ")) {
      flush();
      out.push(`<h2>${inline(line.slice(3))}</h2>`);
    } else if (line.startsWith("# ")) {
      flush();
      out.push(`<h1>${inline(line.slice(2))}</h1>`);
    } else if (line.startsWith("- ")) {
      if (para.length || table.length) flush();
      list.push(line.slice(2));
    } else if (line.startsWith("|")) {
      if (para.length || list.length) flush();
      const cells = line.slice(1, line.endsWith("|") ? -1 : undefined).split("|").map((c) => c.trim());
      if (!cells.every((c) => /^:?-{3,}:?$/.test(c))) table.push(cells);
    } else {
      if (list.length || table.length) flush();
      para.push(line.trim());
    }
  }
  flush();
  return out.join("\n");
}

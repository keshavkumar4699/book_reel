import { randomBytes } from "node:crypto";

import { z } from "zod";

import type { Db } from "../db/db.js";

export const MAX_SHARED_WORDS = 75;

export const ShareSchema = z.discriminatedUnion("type", [
  z.object({
    type: z.literal("quote"),
    text: z.string().min(1).max(4000),
    book_title: z.string().max(300),
    author: z.string().max(200),
    public_domain: z.boolean().default(false),
  }),
  z.object({
    type: z.literal("progress"),
    headline: z.string().min(1).max(140),
    lines: z.array(z.string().max(140)).max(4).default([]),
  }),
]);
export type ShareInput = z.infer<typeof ShareSchema>;

/** Same limit the app applies (DESIGN.md §2.6), enforced again server-side. */
export function limitWords(text: string, max = MAX_SHARED_WORDS): string {
  const words = text.trim().split(/\s+/);
  return words.length <= max ? text.trim() : `${words.slice(0, max).join(" ")}…`;
}

export const escapeHtml = (s: string) =>
  s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);

export class ShareService {
  constructor(
    private readonly db: Db,
    private readonly baseUrl: string,
  ) {}

  async create(userId: string, input: ShareInput): Promise<{ id: string; url: string }> {
    const payload =
      input.type === "quote" ? { ...input, text: input.public_domain ? input.text.trim() : limitWords(input.text) } : input;
    const id = randomBytes(6).toString("base64url");
    await this.db.query("insert into shares (id, user_id, type, payload) values ($1, $2, $3, $4)", [
      id,
      userId,
      input.type,
      JSON.stringify(payload),
    ]);
    return { id, url: `${this.baseUrl}/c/${id}` };
  }

  /** Server-rendered preview page with Open Graph tags; null when unknown. */
  async page(id: string): Promise<string | null> {
    const rows = await this.db.query<{ payload: ShareInput }>(
      "update shares set open_count = open_count + 1 where id = $1 returning payload",
      [id],
    );
    const p = rows[0]?.payload;
    if (!p) return null;
    const title = p.type === "quote" ? `“${limitWords(p.text, 24)}”` : p.headline;
    const desc = p.type === "quote" ? `${p.author}, ${p.book_title}. Read it on Cloro.` : [...p.lines, "Reading on Cloro"].join(" · ");
    const body =
      p.type === "quote"
        ? `<blockquote>${escapeHtml(p.text)}</blockquote><p class="by">— ${escapeHtml(p.author)}, <em>${escapeHtml(p.book_title)}</em></p>`
        : `<h1>${escapeHtml(p.headline)}</h1>${p.lines.map((l) => `<p>${escapeHtml(l)}</p>`).join("")}`;
    return landingPage({ title, description: desc, url: `${this.baseUrl}/c/${id}`, body });
  }
}

export function landingPage(o: { title: string; description: string; url: string; body: string }): string {
  return `<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(o.title)} · Cloro</title>
<meta property="og:title" content="${escapeHtml(o.title)}">
<meta property="og:description" content="${escapeHtml(o.description)}">
<meta property="og:url" content="${escapeHtml(o.url)}">
<meta property="og:site_name" content="Cloro">
<meta name="twitter:card" content="summary">
<style>
:root{--bg:#FBF8F1;--fg:#1F1D1A;--muted:#7A746A;--accent:#D9822B}
@media (prefers-color-scheme:dark){:root{--bg:#141414;--fg:#E6E1D6;--muted:#9A948A}}
body{margin:0;background:var(--bg);color:var(--fg);font:18px/1.55 Georgia,serif;display:flex;min-height:100vh;align-items:center;justify-content:center}
main{max-width:560px;padding:32px 20px}
table{border-collapse:collapse;font-size:.85rem;margin:12px 0}th,td{border-top:1px solid #8885;padding:6px 8px;text-align:left;vertical-align:top}h2{margin-top:1.6em}
blockquote{margin:0;font-size:1.25rem}
.by,p{color:var(--muted)}
a.cta{display:inline-block;margin-top:24px;background:var(--accent);color:#fff;padding:12px 20px;border-radius:12px;text-decoration:none;font-family:system-ui,sans-serif}
</style></head><body><main>${o.body}
<a class="cta" href="https://play.google.com/store/apps/details?id=app.sweatik2.cloro">Read on Cloro</a>
</main></body></html>`;
}

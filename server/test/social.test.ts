import { exportJWK, generateKeyPair, SignJWT, createLocalJWKSet } from "jose";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { Authenticator, AuthError, FirebaseVerifier } from "../src/auth.js";
import type { Db } from "../src/db/db.js";
import { ActivityService } from "../src/habit/activity.js";
import { limitWords, ShareService } from "../src/social/shares.js";
import { SyncService } from "../src/social/sync.js";
import { testDb } from "./helpers.js";

let db: Db;
beforeEach(async () => {
  db = await testDb();
  await new ActivityService(db).user("u");
});
afterEach(() => db.close());

describe("sync", () => {
  it("last write wins per item, tombstones propagate, and pulls page by cursor", async () => {
    const sync = new SyncService(db);
    await sync.push("u", { items: [{ kind: "highlight", id: "h1", updated_at: 100, deleted: false, data: { text: "v1" } }] });
    // An older write from another device loses.
    const stale = await sync.push("u", { items: [{ kind: "highlight", id: "h1", updated_at: 50, deleted: false, data: { text: "old" } }] });
    expect(stale.applied).toBe(0);
    const first = await sync.pull("u", 0);
    expect(first.items).toEqual([{ kind: "highlight", id: "h1", data: { text: "v1" }, updated_at: 100, deleted: false }]);

    await sync.push("u", { items: [{ kind: "highlight", id: "h1", updated_at: 200, deleted: true }] });
    await sync.push("u", { items: [{ kind: "word", id: "sanguine", updated_at: 150, deleted: false, data: { meaning: "hopeful" } }] });
    const next = await sync.pull("u", first.cursor);
    expect(next.items.map((i) => [i.kind, i.id, i.deleted])).toEqual([
      ["highlight", "h1", true],
      ["word", "sanguine", false],
    ]);
    expect((await sync.pull("u", next.cursor)).items).toEqual([]);
  });
});

describe("share links", () => {
  it("limits copyrighted quotes, renders an escaped preview page and counts opens", async () => {
    const shares = new ShareService(db, "https://bookreel.app");
    const long = Array.from({ length: 120 }, (_, i) => `w${i}`).join(" ");
    const { id, url } = await shares.create("u", { type: "quote", text: long, book_title: "<Book>", author: "A & B", public_domain: false });
    expect(url).toBe(`https://bookreel.app/c/${id}`);
    const html = (await shares.page(id))!;
    expect(html).toContain("w74…");
    expect(html).not.toContain("w75 ");
    expect(html).toContain("&lt;Book&gt;");
    expect(html).toContain('property="og:title"');
    expect(await shares.page("missing")).toBeNull();
    expect(limitWords("a b c", 2)).toBe("a b…");
  });
});

describe("auth", () => {
  const projectId = "bookreel-test";

  async function setup() {
    const { publicKey, privateKey } = await generateKeyPair("RS256");
    const jwk = { ...(await exportJWK(publicKey)), kid: "k1", alg: "RS256" };
    const verifier = new FirebaseVerifier(projectId, createLocalJWKSet({ keys: [jwk] }));
    const sign = (sub: string, aud = projectId) =>
      new SignJWT({})
        .setProtectedHeader({ alg: "RS256", kid: "k1" })
        .setIssuer(`https://securetoken.google.com/${aud}`)
        .setAudience(aud)
        .setSubject(sub)
        .setIssuedAt()
        .setExpirationTime("1h")
        .sign(privateKey);
    return { verifier, sign };
  }

  const req = (headers: Record<string, string>) => ({ headers }) as never;

  it("accepts device ids and rejects missing credentials", async () => {
    const auth = new Authenticator(db);
    expect(await auth.resolve(req({ "x-device-id": "abcdef0123456789", "x-region": "IN" }))).toEqual({
      userId: "device:abcdef0123456789",
      region: "IN",
    });
    await expect(auth.resolve(req({}))).rejects.toBeInstanceOf(AuthError);
    await expect(auth.resolve(req({ authorization: "Bearer x" }))).rejects.toBeInstanceOf(AuthError); // not configured
  });

  it("verifies Firebase tokens and links the first sign-in to the device's existing account", async () => {
    const { verifier, sign } = await setup();
    const auth = new Authenticator(db, verifier);
    const activity = new ActivityService(db);
    await activity.user("device:abcdef0123456789");

    const token = await sign("uid-1");
    const first = await auth.resolve(req({ authorization: `Bearer ${token}`, "x-device-id": "abcdef0123456789" }));
    expect(first.userId).toBe("device:abcdef0123456789");
    // Same account later from a new phone (different device id).
    const later = await auth.resolve(req({ authorization: `Bearer ${token}`, "x-device-id": "1111222233334444" }));
    expect(later.userId).toBe("device:abcdef0123456789");
    // A brand-new user with no device data gets their own account.
    expect((await auth.resolve(req({ authorization: `Bearer ${await sign("uid-2")}` }))).userId).toBe("fb:uid-2");
    // Tokens for another Firebase project are rejected.
    await expect(auth.resolve(req({ authorization: `Bearer ${await sign("uid-3", "other")}` }))).rejects.toBeInstanceOf(AuthError);
  });
});

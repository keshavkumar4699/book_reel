import { generateKeyPairSync } from "node:crypto";

import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { buildApp } from "../src/app.js";
import { BillingService, GooglePlayVerifier, InvalidPurchase, type PlaySubscription, type PurchaseVerifier } from "../src/billing/play.js";
import type { Db } from "../src/db/db.js";
import { SegmentService } from "../src/segmentation/service.js";
import { SqlJobStore, SqlQuotaStore, SqlSegmentCache, SqlUsageLog } from "../src/stores/sql.js";
import { makeChapter, presentationOutput, structureOutput } from "./fixtures.js";
import { testDb } from "./helpers.js";

let db: Db;
beforeEach(async () => {
  db = await testDb();
});
afterEach(() => db.close());

/** Google's view of each purchase token. */
class FakePlay implements PurchaseVerifier {
  subs = new Map<string, PlaySubscription>();
  async verify(token: string) {
    const s = this.subs.get(token);
    if (!s) throw new InvalidPurchase("unknown");
    return s;
  }
}

const future = new Date("2027-01-01T00:00:00Z");
const sub = (productId: string, extra: Partial<PlaySubscription> = {}): PlaySubscription => ({
  state: "SUBSCRIPTION_STATE_ACTIVE",
  productId,
  expiresAt: future,
  test: true,
  ...extra,
});

function app(billing: BillingService) {
  const quota = new SqlQuotaStore(db);
  const segments = new SegmentService({
    cache: new SqlSegmentCache(db),
    quota,
    usage: new SqlUsageLog(db),
    jobs: new SqlJobStore(db),
    model: {
      structure: async (job) => ({ output: structureOutput(job.chapter), model: job.route.model, inputTokens: 1, outputTokens: 1 }),
      present: async (job) => ({ output: presentationOutput(job.cards), model: "claude-haiku-5-5", inputTokens: 1, outputTokens: 1 }),
    },
  });
  return buildApp({ db, segments, quota, billing, rtdnSecret: "s3cret" });
}

const device = { "x-device-id": "abcdef0123456789" };
const other = { "x-device-id": "0123456789abcdef" };
const token = "play-token-".padEnd(40, "x");

describe("Play Billing", () => {
  it("a verified purchase sets the plan; with billing enforced the app cannot claim a better one", async () => {
    const play = new FakePlay();
    play.subs.set(token, sub("bookreel_plus"));
    const a = app(new BillingService(db, play, { enforced: true, now: () => new Date("2026-11-12T00:00:00Z") }));
    const segment = (tier: string) =>
      a.inject({
        method: "POST",
        url: "/v1/segment",
        headers: device,
        payload: { book: { content_hash: "c".repeat(64), title: "T", author: "A" }, tier, card_length: "standard", chapters: [makeChapter(0)] },
      });
    // Not subscribed: claiming Scholar gets the free tier (no cloud AI).
    expect((await segment("scholar")).statusCode).toBe(403);
    const v = await a.inject({ method: "POST", url: "/v1/billing/verify", headers: device, payload: { product_id: "bookreel_plus", purchase_token: token } });
    expect(v.statusCode).toBe(200);
    expect(v.json()).toMatchObject({ tier: "plus", product_id: "bookreel_plus", enforced: true });
    // Subscribed to Plus: served as Plus (6 books a month), whatever the app says.
    const res = await segment("scholar");
    expect(res.statusCode).toBe(200);
    expect(res.json().quota).toEqual({ used: 1, limit: 6 });
    expect((await a.inject({ url: "/v1/billing/entitlement", headers: device })).json()).toMatchObject({ tier: "plus" });
    // A token for another product, or unknown to Google, is refused.
    expect((await a.inject({ method: "POST", url: "/v1/billing/verify", headers: device, payload: { product_id: "bookreel_pro", purchase_token: token } })).statusCode).toBe(400);
    expect((await a.inject({ method: "POST", url: "/v1/billing/verify", headers: device, payload: { product_id: "bookreel_pro", purchase_token: "nope".padEnd(20, "z") } })).statusCode).toBe(400);
  });

  it("renewals, cancellations, upgrades and expiry follow Google, also via real-time notifications", async () => {
    const play = new FakePlay();
    let now = new Date("2026-11-12T00:00:00Z");
    const billing = new BillingService(db, play, { enforced: true, now: () => now });
    const a = app(billing);
    play.subs.set(token, sub("bookreel_lite"));
    await billing.verify("u1", "bookreel_lite", token);
    expect((await billing.current("u1")).tier).toBe("lite");
    // Upgrade to Pro: the new purchase replaces the old one.
    const upgrade = "upgrade-token-".padEnd(40, "y");
    play.subs.set(upgrade, sub("bookreel_pro", { linkedPurchaseToken: token }));
    await billing.verify("u1", "bookreel_pro", upgrade);
    expect((await billing.current("u1")).tier).toBe("pro");
    // Cancelled: keeps Pro until the paid period ends, then Free.
    play.subs.set(upgrade, sub("bookreel_pro", { state: "SUBSCRIPTION_STATE_CANCELED" }));
    const push = (t: string, secret = "s3cret") =>
      a.inject({
        method: "POST",
        url: `/v1/billing/rtdn?secret=${secret}`,
        payload: { message: { data: Buffer.from(JSON.stringify({ subscriptionNotification: { notificationType: 3, purchaseToken: t } })).toString("base64") } },
      });
    expect((await push(upgrade)).statusCode).toBe(204);
    expect((await billing.current("u1")).tier).toBe("pro");
    now = new Date("2027-01-02T00:00:00Z");
    expect((await billing.current("u1")).tier).toBe("free");
    // On hold (payment failed): no plan.
    now = new Date("2026-12-01T00:00:00Z");
    play.subs.set(upgrade, sub("bookreel_pro", { state: "SUBSCRIPTION_STATE_ON_HOLD" }));
    await push(upgrade);
    expect((await billing.current("u1")).tier).toBe("free");
    // Notifications need the secret.
    expect((await push(upgrade, "wrong")).statusCode).toBe(403);
  });

  it("restoring on another device moves the plan to that account", async () => {
    const play = new FakePlay();
    play.subs.set(token, sub("bookreel_scholar"));
    const a = app(new BillingService(db, play, { enforced: true }));
    await a.inject({ method: "POST", url: "/v1/billing/verify", headers: device, payload: { product_id: "bookreel_scholar", purchase_token: token } });
    await a.inject({ method: "POST", url: "/v1/billing/verify", headers: other, payload: { product_id: "bookreel_scholar", purchase_token: token } });
    expect((await a.inject({ url: "/v1/billing/entitlement", headers: other })).json().tier).toBe("scholar");
    expect((await a.inject({ url: "/v1/billing/entitlement", headers: device })).json().tier).toBe("free");
  });

  it("without billing configured, development builds keep choosing their plan", async () => {
    const a = app(new BillingService(db, undefined));
    expect((await a.inject({ method: "POST", url: "/v1/billing/verify", headers: device, payload: { product_id: "bookreel_plus", purchase_token: token } })).statusCode).toBe(503);
    expect((await a.inject({ url: "/v1/me/ai-usage?tier=pro", headers: device })).json().books_limit).toBe(6);
    expect((await a.inject({ url: "/v1/billing/entitlement", headers: device })).json()).toMatchObject({ tier: "free", enforced: false });
  });

  it("asks Google's Play Developer API as the service account", async () => {
    const { privateKey } = generateKeyPairSync("rsa", { modulusLength: 2048, privateKeyEncoding: { type: "pkcs8", format: "pem" }, publicKeyEncoding: { type: "spki", format: "pem" } });
    const calls: { url: string; init?: RequestInit }[] = [];
    const fetchImpl = (async (url: string, init?: RequestInit) => {
      calls.push({ url, init });
      if (url.startsWith("https://oauth2.googleapis.com/token")) return Response.json({ access_token: "ya29.test", expires_in: 3600 });
      return Response.json({
        subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
        lineItems: [{ productId: "bookreel_plus", expiryTime: "2026-12-12T00:00:00Z", offerDetails: { basePlanId: "monthly" } }],
        linkedPurchaseToken: "older",
        testPurchase: {},
      });
    }) as unknown as typeof fetch;
    const v = new GooglePlayVerifier({ packageName: "app.bookreel", serviceAccount: { client_email: "billing@x.iam.gserviceaccount.com", private_key: privateKey }, fetchImpl });
    const s = await v.verify("tok/en");
    expect(s).toEqual({ state: "SUBSCRIPTION_STATE_ACTIVE", productId: "bookreel_plus", expiresAt: new Date("2026-12-12T00:00:00Z"), linkedPurchaseToken: "older", test: true });
    expect(calls[0]!.url).toBe("https://oauth2.googleapis.com/token");
    expect(String(calls[0]!.init!.body)).toContain("grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer");
    expect(calls[1]!.url).toBe("https://androidpublisher.googleapis.com/androidpublisher/v3/applications/app.bookreel/purchases/subscriptionsv2/tokens/tok%2Fen");
    expect((calls[1]!.init!.headers as Record<string, string>).authorization).toBe("Bearer ya29.test");
    // The access token is reused until it nearly expires.
    await v.verify("again");
    expect(calls.filter((c) => c.url.includes("oauth2"))).toHaveLength(1);
  });
});

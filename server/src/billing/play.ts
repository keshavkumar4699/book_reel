import { importPKCS8, SignJWT } from "jose";
import { z } from "zod";

import { isPaidTier, PAID_TIERS, type Tier } from "../config.js";
import type { Db } from "../db/db.js";

/**
 * Google Play Billing (DESIGN.md §6, IMPLEMENTATION_PLAN.md Phase 8).
 *
 * The app buys a subscription in Play, then sends the purchase token here.
 * The server asks Google's Play Developer API what that token is worth
 * (purchases.subscriptionsv2), stores the entitlement, and from then on
 * uses it instead of trusting the plan the app claims. Real-time developer
 * notifications (Pub/Sub push) keep renewals, cancellations and refunds in
 * step without the app.
 */

/** Play subscription product IDs; each has a "monthly" and a "yearly" base plan. */
export const PLAN_PRODUCTS: Record<string, Exclude<Tier, "free">> = {
  bookreel_lite: "lite",
  bookreel_plus: "plus",
  bookreel_pro: "pro",
  bookreel_scholar: "scholar",
};

/** States in which the subscriber keeps their plan (cancelled = until it runs out). */
const ENTITLED_STATES = new Set(["SUBSCRIPTION_STATE_ACTIVE", "SUBSCRIPTION_STATE_IN_GRACE_PERIOD", "SUBSCRIPTION_STATE_CANCELED"]);

export interface PlaySubscription {
  state: string;
  productId: string;
  expiresAt: Date | null;
  /** The purchase this one replaced (upgrade, downgrade, resubscribe). */
  linkedPurchaseToken?: string;
  test: boolean;
}

export interface PurchaseVerifier {
  verify(purchaseToken: string): Promise<PlaySubscription>;
}

export class InvalidPurchase extends Error {}
export class BillingUnavailable extends Error {}

const ServiceAccountSchema = z.object({ client_email: z.string(), private_key: z.string() });

/** Talks to the Play Developer API as a service account (JWT bearer grant). */
export class GooglePlayVerifier implements PurchaseVerifier {
  private token?: { value: string; expires: number };

  constructor(
    private readonly opts: {
      packageName: string;
      serviceAccount: { client_email: string; private_key: string };
      fetchImpl?: typeof fetch;
      now?: () => number;
    },
  ) {}

  private get fetch() {
    return this.opts.fetchImpl ?? fetch;
  }

  private async accessToken(): Promise<string> {
    const now = (this.opts.now ?? Date.now)();
    if (this.token && this.token.expires - 60_000 > now) return this.token.value;
    const key = await importPKCS8(this.opts.serviceAccount.private_key, "RS256");
    const assertion = await new SignJWT({ scope: "https://www.googleapis.com/auth/androidpublisher" })
      .setProtectedHeader({ alg: "RS256", typ: "JWT" })
      .setIssuer(this.opts.serviceAccount.client_email)
      .setAudience("https://oauth2.googleapis.com/token")
      .setIssuedAt(Math.floor(now / 1000))
      .setExpirationTime(Math.floor(now / 1000) + 3600)
      .sign(key);
    const res = await this.fetch("https://oauth2.googleapis.com/token", {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }).toString(),
    });
    if (!res.ok) throw new BillingUnavailable(`Google token exchange failed (${res.status})`);
    const body = (await res.json()) as { access_token: string; expires_in?: number };
    this.token = { value: body.access_token, expires: now + (body.expires_in ?? 3600) * 1000 };
    return body.access_token;
  }

  async verify(purchaseToken: string): Promise<PlaySubscription> {
    const url =
      `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${encodeURIComponent(this.opts.packageName)}` +
      `/purchases/subscriptionsv2/tokens/${encodeURIComponent(purchaseToken)}`;
    const res = await this.fetch(url, { headers: { authorization: `Bearer ${await this.accessToken()}` } });
    if (res.status === 404 || res.status === 400 || res.status === 410) throw new InvalidPurchase("Google does not know this purchase");
    if (!res.ok) throw new BillingUnavailable(`Play Developer API answered ${res.status}`);
    const sub = (await res.json()) as {
      subscriptionState?: string;
      lineItems?: { productId: string; expiryTime?: string }[];
      linkedPurchaseToken?: string;
      testPurchase?: object;
    };
    const item = sub.lineItems?.[0];
    if (!item) throw new InvalidPurchase("purchase has no subscription");
    return {
      state: sub.subscriptionState ?? "SUBSCRIPTION_STATE_UNSPECIFIED",
      productId: item.productId,
      expiresAt: item.expiryTime ? new Date(item.expiryTime) : null,
      linkedPurchaseToken: sub.linkedPurchaseToken,
      test: sub.testPurchase !== undefined,
    };
  }
}

/** The verifier from the environment, or none (plans then stay unverified, for development). */
export function verifierFromEnv(env: NodeJS.ProcessEnv = process.env): PurchaseVerifier | undefined {
  const packageName = env.PLAY_PACKAGE_NAME;
  const json = env.PLAY_SERVICE_ACCOUNT_JSON;
  if (!packageName || !json) return undefined;
  return new GooglePlayVerifier({ packageName, serviceAccount: ServiceAccountSchema.parse(JSON.parse(json)) });
}

export interface Entitlement {
  tier: Tier;
  productId: string | null;
  expiresAt: Date | null;
  state: string | null;
}

interface EntitlementRow {
  purchase_token: string;
  user_id: string | null;
  product_id: string;
  tier: string;
  state: string;
  expires_at: Date | string | null;
}

export const VerifyPurchaseSchema = z.object({
  product_id: z.string().max(100),
  purchase_token: z.string().min(10).max(4000),
});

export class BillingService {
  constructor(
    private readonly db: Db,
    private readonly verifier: PurchaseVerifier | undefined,
    private readonly opts: { enforced?: boolean; now?: () => Date } = {},
  ) {}

  /** Plans come from verified purchases (production), not from the app. */
  get enforced(): boolean {
    return this.opts.enforced ?? false;
  }

  private now() {
    return (this.opts.now ?? (() => new Date()))();
  }

  /** Checks a purchase with Google and records it for [userId]. */
  async verify(userId: string, productId: string, purchaseToken: string): Promise<Entitlement> {
    if (!this.verifier) throw new BillingUnavailable("Billing is not configured on this server.");
    const sub = await this.verifier.verify(purchaseToken);
    if (sub.productId !== productId || !PLAN_PRODUCTS[sub.productId]) throw new InvalidPurchase("purchase is not a Cloro plan");
    await this.store(purchaseToken, userId, sub);
    return this.current(userId);
  }

  /** A real-time notification: re-reads the purchase and updates it. */
  async refresh(purchaseToken: string): Promise<void> {
    if (!this.verifier) return;
    const sub = await this.verifier.verify(purchaseToken);
    if (!PLAN_PRODUCTS[sub.productId]) return;
    const known = await this.db.query<{ user_id: string | null }>(`select user_id from entitlements where purchase_token = $1`, [purchaseToken]);
    await this.store(purchaseToken, known[0]?.user_id ?? null, sub);
  }

  private async store(purchaseToken: string, userId: string | null, sub: PlaySubscription) {
    // The latest device to verify a token owns it (restoring on a new phone moves the plan).
    await this.db.query(
      `insert into entitlements (purchase_token, user_id, product_id, tier, state, expires_at, test, updated_at)
       values ($1, $2, $3, $4, $5, $6, $7, now())
       on conflict (purchase_token) do update set
         user_id = coalesce(excluded.user_id, entitlements.user_id), product_id = excluded.product_id, tier = excluded.tier,
         state = excluded.state, expires_at = excluded.expires_at, test = excluded.test, updated_at = now()`,
      [purchaseToken, userId, sub.productId, PLAN_PRODUCTS[sub.productId], sub.state, sub.expiresAt, sub.test],
    );
    // An upgrade or downgrade replaces the old purchase.
    if (sub.linkedPurchaseToken) {
      await this.db.query(`update entitlements set state = 'SUPERSEDED', updated_at = now() where purchase_token = $1`, [sub.linkedPurchaseToken]);
    }
  }

  /** The best plan the account holds now. */
  async current(userId: string): Promise<Entitlement> {
    const rows = await this.db.query<EntitlementRow>(`select * from entitlements where user_id = $1`, [userId]);
    const now = this.now().getTime();
    let best: Entitlement = { tier: "free", productId: null, expiresAt: null, state: null };
    for (const r of rows) {
      const expires = r.expires_at ? new Date(r.expires_at) : null;
      if (!ENTITLED_STATES.has(r.state) || (expires && expires.getTime() <= now) || !isPaidTier(r.tier)) continue;
      if (best.tier === "free" || PAID_TIERS.indexOf(r.tier) > PAID_TIERS.indexOf(best.tier as Exclude<Tier, "free">)) {
        best = { tier: r.tier, productId: r.product_id, expiresAt: expires, state: r.state };
      }
    }
    return best;
  }

  /**
   * The plan to serve: the verified one when billing is enforced, otherwise
   * what the app asked for (development builds, before billing is live).
   */
  async tierFor(userId: string, requested: string): Promise<Tier> {
    if (!this.enforced) return (isPaidTier(requested) || requested === "free" ? requested : "free") as Tier;
    return (await this.current(userId)).tier;
  }
}

/** A Pub/Sub push message carrying a Play real-time developer notification. */
export const RtdnSchema = z.object({
  message: z.object({ data: z.string() }),
});

export function purchaseTokenFromRtdn(body: unknown): string | null {
  const msg = RtdnSchema.parse(body);
  const json = JSON.parse(Buffer.from(msg.message.data, "base64").toString("utf8")) as {
    subscriptionNotification?: { purchaseToken?: string };
  };
  return json.subscriptionNotification?.purchaseToken ?? null;
}

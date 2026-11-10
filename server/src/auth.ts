import type { FastifyRequest } from "fastify";
import { createRemoteJWKSet, jwtVerify, type JWTVerifyGetKey } from "jose";

import type { Db } from "./db/db.js";
import type { Caller } from "./segmentation/service.js";

const DEVICE_ID = /^[a-f0-9]{16,64}$/;
const GOOGLE_JWKS = "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com";

export class AuthError extends Error {}

/** Verifies Firebase Auth ID tokens (RS256, issued for [projectId]). */
export class FirebaseVerifier {
  private readonly keys: JWTVerifyGetKey;

  constructor(
    private readonly projectId: string,
    keys?: JWTVerifyGetKey,
  ) {
    this.keys = keys ?? createRemoteJWKSet(new URL(GOOGLE_JWKS));
  }

  async uid(token: string): Promise<string> {
    try {
      const { payload } = await jwtVerify(token, this.keys, {
        issuer: `https://securetoken.google.com/${this.projectId}`,
        audience: this.projectId,
        algorithms: ["RS256"],
      });
      if (!payload.sub) throw new AuthError("token has no subject");
      return payload.sub;
    } catch (e) {
      throw new AuthError(`invalid ID token: ${(e as Error).message}`);
    }
  }
}

/**
 * Resolves who is calling.
 * - `Authorization: Bearer <Firebase ID token>` → the signed-in account. On the
 *   first sign-in from a device, the account is linked to that device's
 *   existing data (alias), so nothing read before signing in is lost.
 * - Otherwise `x-device-id` → an anonymous device account.
 */
export class Authenticator {
  constructor(
    private readonly db: Db,
    private readonly firebase?: FirebaseVerifier,
  ) {}

  async resolve(req: FastifyRequest): Promise<Caller> {
    const region = typeof req.headers["x-region"] === "string" ? req.headers["x-region"] : undefined;
    const device = typeof req.headers["x-device-id"] === "string" && DEVICE_ID.test(req.headers["x-device-id"]) ? req.headers["x-device-id"] : undefined;
    const auth = req.headers.authorization;
    if (auth?.startsWith("Bearer ")) {
      if (!this.firebase) throw new AuthError("sign-in is not configured on this server");
      const uid = await this.firebase.uid(auth.slice(7));
      return { userId: await this.accountFor(`fb:${uid}`, device ? `device:${device}` : undefined), region };
    }
    if (!device) throw new AuthError("missing credentials");
    return { userId: `device:${device}`, region };
  }

  private async accountFor(identity: string, deviceUser?: string): Promise<string> {
    const alias = await this.db.query<{ user_id: string }>("select user_id from aliases where alias = $1", [identity]);
    if (alias[0]) return alias[0].user_id;
    if (deviceUser) {
      const exists = await this.db.query("select 1 from users where id = $1", [deviceUser]);
      if (exists.length) {
        await this.db.query("insert into aliases (alias, user_id) values ($1, $2) on conflict do nothing", [identity, deviceUser]);
        return (await this.db.query<{ user_id: string }>("select user_id from aliases where alias = $1", [identity]))[0]!.user_id;
      }
    }
    return identity;
  }
}

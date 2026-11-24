# Deploying Cloro

What the code already does, and the one-time setup it needs from your accounts. It covers Production plan items A1 (release signing), A6 (hosting) and A7 (error reporting). Nothing here goes in the repository except the variable *names*: keys and passwords live in GitHub secrets and Google Secret Manager.

## 1. Server: pay nothing until you have users

The app works fully without a server (Free mode: cards cut on the phone, everything kept on the phone). The server adds following, the Journal feed, sync between phones, AI cards and Play purchases. This setup keeps it at **₹0 until people actually use it**, then costs grow with use.

### 1.0 First: stop what you're being charged for now

Earlier versions of this guide created a **Cloud SQL** database. Cloud SQL bills for every hour the instance exists, used or not: a `db-g1-small` costs roughly ₹2,000–2,500 a month plus storage. That is almost certainly the charge you saw.

1. Confirm: Google Cloud console → **Billing → Reports**, group by **SKU**. Look for *Cloud SQL for PostgreSQL*.
2. Delete the instance. There are no real users yet, so there's nothing to keep:

   ```bash
   gcloud sql instances delete cloro-db
   ```

3. Check nothing else is left running or stored:

   ```bash
   gcloud sql instances list
   ```

   ```bash
   gcloud run services list
   ```

   ```bash
   gcloud artifacts docker images list asia-south1-docker.pkg.dev/PROJECT_ID/cloro
   ```

   The last one covers the old region; delete images you don't need. Then remove the `CLOUD_SQL_INSTANCE` repository variable on GitHub.
4. Set a **budget alert** (Billing → Budgets & alerts), e.g. ₹100 with alerts at 50%, 90% and 100%. An alert warns you by email; it doesn't stop spending, so act on it.

### 1.1 Three stages

| Stage | When | What runs | Cost |
|---|---|---|---|
| **0. No server** | Until you have testers | The app only. Leave `BOOKREEL_API` unset and the app never calls a server. | ₹0 |
| **1. Free tiers** | First real users | **Cloud Run** (runs only while a request is served) and **Neon** Postgres (sleeps 5 minutes after the last query). | ₹0 within the free limits below |
| **2. Pay as you grow** | When you pass a free limit | The same two, on usage-based plans. | Grows with use |

**What's free** (November 2026; check the pricing pages before relying on it):
- **Neon Free:** 100 compute-hours a month per project, 1 GB of storage, 5 GB of transfer, no card needed. A sleeping database uses no compute. Past a limit the database pauses until next month; it never bills you. ([Neon free plan](https://neon.com/faqs/free-plan-limits-and-quotas))
- **Cloud Run:** 2 million requests, 180,000 vCPU-seconds and 360,000 GiB-seconds a month, across your billing account. ([Cloud Run pricing](https://cloud.google.com/run/pricing))
- **Artifact Registry** 0.5 GB, **Secret Manager** 6 active secret versions, **Cloud Logging** 50 GiB a month.

**How the code keeps an unused server at zero:**
- Cloud Run keeps no instance running (`--min-instances 0`), bills CPU only during requests (`--cpu-throttling`), and runs at most 2 instances (`CLOUD_RUN_MAX_INSTANCES`), so a burst of traffic can't run up a bill.
- The server closes idle database connections after 10 seconds, so the database falls asleep 5 minutes after the last request. It waits up to 15 seconds for a sleeping database to wake (it takes about a second).
- `/healthz` (CI and uptime checks) never touches the database. The server runs no timers or background jobs.
- The app syncs every 5 minutes only while it's open, never in the background.
- Old server images are deleted automatically (the 3 newest are kept), so storage stays under the free 0.5 GB.

**How far the free tier goes:** the database is awake only while someone is using the app (plus 5 minutes). At the smallest size, 100 compute-hours is about 400 awake hours a month, shared by everyone reading at the same time. That's plenty for testers and the first few hundred daily readers. Neon's console shows the hours used.

**Already in the repository:** `server/Dockerfile` (Node 22, production dependencies only, a non-root user), built and checked (`/healthz`) by CI on every push. `.github/workflows/deploy-server.yml` builds, deploys and smoke-tests on a `server-v*` tag or by hand, and does nothing until `GCP_PROJECT` is set. In production the server refuses to start without a Postgres `DATABASE_URL` (a container's disk is wiped on restart). It runs its migrations at start-up (safe to repeat) and shuts down cleanly.

### 1.2 Stage 1 setup (one time)

Replace `PROJECT_ID` and `OWNER/REPO` (your GitHub repository). Everything runs in Singapore (`asia-southeast1`), next to the database: Neon has no Mumbai region, and Singapore is close to India.

**The database (Neon):**
1. Sign up at [neon.com](https://neon.com) (free, no card).
2. Create a project named `cloro`: Postgres 17, region **AWS Asia Pacific (Singapore)**.
3. Dashboard → **Connect**. Turn on **Connection pooling** and copy the connection string (`postgresql://…-pooler.ap-southeast-1.aws.neon.tech/neondb?sslmode=require…`). The server creates its tables on first start.

**Google Cloud:**

```bash
gcloud config set project PROJECT_ID
```

```bash
gcloud services enable run.googleapis.com artifactregistry.googleapis.com secretmanager.googleapis.com iamcredentials.googleapis.com
```

```bash
gcloud artifacts repositories create cloro --repository-format=docker --location=asia-southeast1
```

Keep only the newest images (run from the repository's root):

```bash
gcloud artifacts repositories set-cleanup-policies cloro --location=asia-southeast1 --policy=server/deploy/artifact-cleanup.json --no-dry-run
```

The database address as a secret. Paste Neon's string between the quotes:

```bash
printf '%s' 'NEON_CONNECTION_STRING' | gcloud secrets create cloro-database-url --data-file=-
```

The other secrets, one per key you use. There are 6 free secret versions in all, so add only what you need:
- `cloro-anthropic-key`;
- `cloro-tts-key`;
- `cloro-admin-token`;
- `cloro-play-service-account`;
- `cloro-play-rtdn-secret`.

The service account the server runs as (it only reads secrets):

```bash
gcloud iam service-accounts create cloro-api
```

```bash
gcloud projects add-iam-policy-binding PROJECT_ID --member=serviceAccount:cloro-api@PROJECT_ID.iam.gserviceaccount.com --role=roles/secretmanager.secretAccessor
```

Keyless deploys from GitHub (Workload Identity Federation):

```bash
gcloud iam service-accounts create cloro-deployer
```

```bash
for role in roles/run.admin roles/artifactregistry.writer roles/iam.serviceAccountUser; do gcloud projects add-iam-policy-binding PROJECT_ID --member=serviceAccount:cloro-deployer@PROJECT_ID.iam.gserviceaccount.com --role=$role; done
```

```bash
gcloud iam workload-identity-pools create github --location=global
```

```bash
gcloud iam workload-identity-pools providers create-oidc github --location=global --workload-identity-pool=github --issuer-uri=https://token.actions.githubusercontent.com --attribute-mapping=google.subject=assertion.sub,attribute.repository=assertion.repository --attribute-condition="assertion.repository=='OWNER/REPO'"
```

```bash
gcloud iam service-accounts add-iam-policy-binding cloro-deployer@PROJECT_ID.iam.gserviceaccount.com --role=roles/iam.workloadIdentityUser --member="principalSet://iam.googleapis.com/projects/$(gcloud projects describe PROJECT_ID --format='value(projectNumber)')/locations/global/workloadIdentityPools/github/attribute.repository/OWNER/REPO"
```

**GitHub repository variables** (Settings → Secrets and variables → Actions → Variables):

| Variable | Value |
|---|---|
| `GCP_PROJECT` | `PROJECT_ID` |
| `GCP_REGION` | `asia-southeast1` |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | `projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github/providers/github` |
| `GCP_DEPLOY_SERVICE_ACCOUNT` | `cloro-deployer@PROJECT_ID.iam.gserviceaccount.com` |
| `GCP_RUNTIME_SERVICE_ACCOUNT` | `cloro-api@PROJECT_ID.iam.gserviceaccount.com` |
| `CLOUD_RUN_ENV` | e.g. `PUBLIC_BASE_URL=https://cloro.example,SUPPORT_EMAIL=help@cloro.example,FIREBASE_PROJECT_ID=…` |
| `CLOUD_RUN_SECRETS` | e.g. `DATABASE_URL=cloro-database-url:latest,ANTHROPIC_API_KEY=cloro-anthropic-key:latest,TTS_API_KEY=cloro-tts-key:latest,ADMIN_TOKEN=cloro-admin-token:latest` |
| `CLOUD_RUN_MAX_INSTANCES` | optional, default `2`: raise it only when the server gets busy |
| `BOOKREEL_API` | the server's `https://` address, so CI builds apps that use it. Leave it unset for Stage 0. |

Don't set `CLOUD_SQL_INSTANCE`.

**Deploy** by pushing a tag, or with **Run workflow** on the Actions tab:

```bash
git tag server-v1.0.0 && git push origin server-v1.0.0
```

Map `api.cloro.in` to the service (Cloud Run → Manage custom domains) and build the app with `BOOKREEL_API=https://api.cloro.in`. The website on `cloro.in` passes share links (`/c/…`), invites (`/i/…`) and `assetlinks.json` through to this service (§5), so set `PUBLIC_BASE_URL=https://cloro.in` and those links use the site's domain.

### 1.3 Stage 2: when to start paying

Check monthly: Neon's console (compute-hours and storage) and Google Cloud **Billing → Reports**.
- **Neon:** when compute-hours near 100 or storage nears 1 GB, move to the usage-based **Launch** plan. It bills for hours awake and GB stored, and it still sleeps when nobody reads. Free-plan restore history is short, so turn on longer restore history when you upgrade. For a copy of your own, take a `pg_dump` now and then.
- **Cloud Run:** past the free tier, it bills per request and per second served. Raise `CLOUD_RUN_MAX_INSTANCES` only when requests start queuing.
- **Cloud SQL** only makes sense for a database that's busy around the clock. It's billed hourly even when idle. The deploy workflow still supports it (`CLOUD_SQL_INSTANCE`) if you ever need it.

## 2. Release signing (Android)

**What's ready:**
- `app/android/app/build.gradle.kts` signs release builds with the key described in `app/android/key.properties`. That file is git-ignored, and the debug key is used when it's absent.
- **CI with the secrets below:**
  - writes `key.properties`;
  - signs the APKs with the upload key;
  - also builds a Play-ready **App Bundle** (artifact `cloro-release-aab`).
- **Version codes** come from the CI run number, so every build is higher than the last.

**One time.** Make an upload key and keep the file and passwords somewhere safe, outside the repository:

```bash
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Then turn the file into one line of text for the secret. On Linux:

```bash
base64 -w0 upload-keystore.jks
```

On macOS:

```bash
base64 -i upload-keystore.jks
```

On Windows (PowerShell):

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("upload-keystore.jks"))
```

Copy only that text into the secret: no quotes, and no `-----BEGIN…` or `-----END…` lines (CI drops those, and line breaks, if they slip in). If the key doesn't open with the password and alias below, CI still builds the APKs, signs them with the debug key, skips the App Bundle and shows an **Upload key not used** warning on the run.

Then add these **GitHub secrets** (Settings → Secrets and variables → Actions → Secrets):

| Secret | Value |
|---|---|
| `ANDROID_UPLOAD_KEYSTORE_BASE64` | the `base64` output above |
| `ANDROID_UPLOAD_STORE_PASSWORD` | the keystore password |
| `ANDROID_UPLOAD_KEY_ALIAS` | `upload` |
| `ANDROID_UPLOAD_KEY_PASSWORD` | the key password |

In Play Console, turn on **Play App Signing** (Google keeps the app signing key; you upload with this one). Copy the **app signing** certificate's SHA-256 from Play Console → Setup → App signing into the server's `ANDROID_CERT_SHA256`, for App Links.

To build a signed bundle on your own machine, create `app/android/key.properties`:

```
storeFile=/absolute/path/to/upload-keystore.jks
storePassword=…
keyAlias=upload
keyPassword=…
```

## 3. Privacy policy and terms

**What's ready:** drafts in `app/assets/legal/privacy.md` and `terms.md`, written from what the app and server actually collect and send.
- The app shows them in Settings → About.
- The server serves the same files at `/privacy` and `/terms`; they are copied into the image, which is why it's built from the repository root.

**Before launch:**
- Fill in every [bracketed] part: who runs Cloro, the contact email, the effective date, and the governing law.
- Have both reviewed.
- Put `https://<your domain>/privacy` in Play Console (App content → Privacy policy).
- Use the policy's lists to fill in the Data safety form.

## 4. Errors and alerts

**What's ready:**
- **Server:** in production it logs JSON lines that Cloud Logging understands (`severity`, `message`). Every unhandled error is an **Error Reporting** event with its stack trace (service `cloro-api`, version = Cloud Run revision).
- **App:** sends errors it didn't handle to `POST /v1/errors`, logged as Error Reporting events for service `cloro-app` with the app version.
  - **What's sent:** the error and stack trace only, never book text on purpose; no reader id is logged.
  - **Limits:** each distinct error once, at most 10 per run, and 30 an hour per phone.
  - **Opt-out:** Settings → Comfort & privacy → Send crash reports.
- **Native crashes and freezes (ANRs)** show in Play Console → Android vitals without any setup.

**One time, in Google Cloud:**
- **Error Reporting** shows both services. Turn on notifications for new errors: Error Reporting → *Configure notifications*.
- **Uptime check** on `https://<your domain>/healthz` (Monitoring → Uptime checks) every 15 minutes, with an alert to your email. It never wakes the database.
- **Alerting policies** (Monitoring → Alerting) for Cloud Run 5xx rate over 1% for 5 minutes, and request latency p95 over 2 s.
- **AI spend:** keep the Anthropic console's monthly limit at a level you're comfortable with. The server's `ai_usage` table has the cost of every request, for comparison with DESIGN.md §5.

## 5. Website (cloro.in)

The site is static and lives in `website/`. It's served by Firebase Hosting, in the same Google Cloud project as the server. The full guide is in [`website/README.md`](../website/README.md).

- **Deploy:** `cd website && firebase use --add` (once), then `npm run deploy` (it checks the site first). In the Firebase console, go to Hosting → Add custom domain: add `cloro.in`, and add `www.cloro.in` as a redirect to it.
- **Routes to the server:** `website/firebase.json` routes `/c/**`, `/i/**` and `/.well-known/assetlinks.json` to the Cloud Run service `cloro-api` in `asia-southeast1`. Change both there if yours differ.
- **Domains:** the server answers on `api.cloro.in` for the app. Share links, invites and App Links work on `cloro.in`.
- **Legal pages:** `/privacy/`, `/terms/` and `/account/delete/` are the site's own pages. The first two are built from `app/assets/legal/*.md` (`npm run build`), the same text the app and server show. Use these URLs in Play Console.
- **Search:** add `cloro.in` to Google Search Console and submit `https://cloro.in/sitemap.xml`.

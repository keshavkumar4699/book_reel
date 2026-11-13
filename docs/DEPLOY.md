# Deploying Cloro

What the code already does, and the one-time setup it needs from your accounts. It covers Production plan items A1 (release signing), A6 (hosting) and A7 (error reporting). Nothing here goes in the repository except the variable *names*: keys and passwords live in GitHub secrets and Google Secret Manager.

## 1. Server on Google Cloud Run

**What's ready:**
- `server/Dockerfile` (Node 22, production dependencies only, runs as a non-root user). CI builds it on every push and checks `/healthz`.
- `.github/workflows/deploy-server.yml`: builds, pushes and deploys on a `server-v*` tag or by hand, then smoke-tests `/healthz`. It does nothing until `GCP_PROJECT` is set.
- **Start-up safety:** the server refuses to start in production without a Postgres `DATABASE_URL`, because a container's disk is wiped on restart. It shuts down cleanly on SIGTERM. Migrations run at start-up and are safe to repeat.

**One-time setup.** Replace `PROJECT_ID`, `REGION` (e.g. `asia-south1`) and `OWNER/REPO` (your GitHub repository):

```bash
gcloud config set project PROJECT_ID
```

```bash
gcloud services enable run.googleapis.com sqladmin.googleapis.com artifactregistry.googleapis.com secretmanager.googleapis.com iamcredentials.googleapis.com
```

```bash
gcloud artifacts repositories create cloro --repository-format=docker --location=REGION
```

A Postgres database with daily backups:

```bash
gcloud sql instances create cloro-db --database-version=POSTGRES_16 --edition=enterprise --tier=db-g1-small --region=REGION --backup-start-time=03:00
```

```bash
gcloud sql databases create cloro --instance=cloro-db
```

```bash
gcloud sql users create cloro --instance=cloro-db --password='CHOOSE_A_LONG_PASSWORD'
```

Secrets, one per key. Repeat for each key you use:
- `cloro-anthropic-key`;
- `cloro-tts-key` (also used for mood);
- `cloro-admin-token`;
- `cloro-play-service-account`;
- `cloro-play-rtdn-secret`.

```bash
printf '%s' 'postgres://cloro:CHOOSE_A_LONG_PASSWORD@/cloro?host=/cloudsql/PROJECT_ID:REGION:cloro-db' | gcloud secrets create cloro-database-url --data-file=-
```

The service account the server runs as:

```bash
gcloud iam service-accounts create cloro-api
```

```bash
for role in roles/secretmanager.secretAccessor roles/cloudsql.client; do gcloud projects add-iam-policy-binding PROJECT_ID --member=serviceAccount:cloro-api@PROJECT_ID.iam.gserviceaccount.com --role=$role; done
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
| `GCP_REGION` | `REGION` |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | `projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github/providers/github` |
| `GCP_DEPLOY_SERVICE_ACCOUNT` | `cloro-deployer@PROJECT_ID.iam.gserviceaccount.com` |
| `GCP_RUNTIME_SERVICE_ACCOUNT` | `cloro-api@PROJECT_ID.iam.gserviceaccount.com` |
| `CLOUD_SQL_INSTANCE` | `PROJECT_ID:REGION:cloro-db` |
| `CLOUD_RUN_ENV` | e.g. `PUBLIC_BASE_URL=https://cloro.example,SUPPORT_EMAIL=help@cloro.example,FIREBASE_PROJECT_ID=…` |
| `CLOUD_RUN_SECRETS` | e.g. `DATABASE_URL=cloro-database-url:latest,ANTHROPIC_API_KEY=cloro-anthropic-key:latest,TTS_API_KEY=cloro-tts-key:latest,ADMIN_TOKEN=cloro-admin-token:latest` |
| `BOOKREEL_API` | the server's `https://` address, so CI builds apps that use it |

**Deploy** by pushing a tag, or with **Run workflow** on the Actions tab:

```bash
git tag server-v1.0.0 && git push origin server-v1.0.0
```

Map your domain to the service (Cloud Run → Manage custom domains), then set `PUBLIC_BASE_URL` to it.

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

```bash
base64 -w0 upload-keystore.jks
```

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

## 3. Errors and alerts

**What's ready:**
- **Server:** in production it logs JSON lines that Cloud Logging understands (`severity`, `message`). Every unhandled error is an **Error Reporting** event with its stack trace (service `cloro-api`, version = Cloud Run revision).
- **App:** sends errors it didn't handle to `POST /v1/errors`, logged as Error Reporting events for service `cloro-app` with the app version.
  - **What's sent:** the error and stack trace only, never book text on purpose; no reader id is logged.
  - **Limits:** each distinct error once, at most 10 per run, and 30 an hour per phone.
  - **Opt-out:** Settings → Comfort & privacy → Send crash reports.
- **Native crashes and freezes (ANRs)** show in Play Console → Android vitals without any setup.

**One time, in Google Cloud:**
- **Error Reporting** shows both services. Turn on notifications for new errors: Error Reporting → *Configure notifications*.
- **Uptime check** on `https://<your domain>/healthz` (Monitoring → Uptime checks), with an alert to your email.
- **Alerting policies** (Monitoring → Alerting) for Cloud Run 5xx rate over 1% for 5 minutes, and request latency p95 over 2 s.
- **AI spend:** keep the Anthropic console's monthly limit at a level you're comfortable with. The server's `ai_usage` table has the cost of every request, for comparison with DESIGN.md §5.

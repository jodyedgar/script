<!--
  AI ASSISTANT: Read this file first. Only reference files listed in the
  "Active Files" sections. Ignore anything under deprecated/ (none yet).
  When replacing a file, deprecate it (move to deprecated/YYYY-MM-DD/) — never delete.
-->

# ARCHITECTURE — Ticket Management Scripts

CLI tooling for the **Bucky** ticket system. All scripts talk to Firestore via
the **REST API + `gcloud` auth** (no Notion API key). Firebase Storage uploads
use a service account (`qa/service-account.json`).

- **Firebase project:** `bucky-app-355a3`
- **Storage bucket:** `bucky-app-355a3.firebasestorage.app`
- **Auth:** `gcloud auth login` (REST reads/writes run as your gcloud identity)
- **Deps:** `bash`, `jq`, `curl`, `gcloud`; `node` + `firebase-admin` (in `qa/`) for Storage uploads
- **Git:** repo `github.com/jodyedgar/script.git`

---

## Bucky ticket data model (what the scripts read/write)

Collection: **`tickets`** — auto-ID documents. Source of truth is the Bucky repo
(`functions/src/types/collections.ts` `TicketDoc`, `functions/src/services/dataService.ts` `createTicket`).

Key fields: `displayId` ("TICK-N"), `ticketNumber` (int), `name` (title),
`status` (default `"Backlog"`), `content` (plain-text body), `projectId` +
denormalized `projectName`, `clientId` + `clientName`, `shopifyStoreId` +
`shopifyStoreUrl`, `pageUrl`, `rushOrder`, `screenshots[]`, `qaBefore[]`,
`qaAfter[]`, `attachments[]`, `source`, `createdAt`/`updatedAt`.

**Critical rules (server-side authority):**
- **TICK-N is minted ONLY by the `enforceTicketNumber` onCreate trigger** from
  `counters/tickets`. When creating a ticket, OMIT `ticketNumber`/`displayId`
  and let the trigger assign them — never compute max+1 or set them manually.
- Status `"In Queue"` fires a client QA-questionnaire email; `"Client Approval"`
  fires a client approval email. `"Backlog"` is silent. Default new tickets to Backlog.

**Resolution collections:**
- `clients` — `name` (often company name or "#channel"), `companyName`, `slackChannels[]`
- `clientProjects` — `name`, `clientId`, `clientName`, `shopifyStoreId`
- `shopifyStores` — `onlineStoreUrl`, `myshopifyUrl` (store URL = `onlineStoreUrl || myshopifyUrl`)

⚠️ **Slack channel strings are NOT unique** — one channel (e.g. "cava") can live
in multiple clients' `slackChannels`. Resolution must disambiguate, not pick the first.

---

## Active Files

### Entry point
- **`ticket.sh`** — unified ticket script. Three modes:
  - **Fetch** (`ticket.sh TICK-###`): show details, cache viewport for QA, set "In Progress".
  - **Update** (`ticket.sh TICK-### --status ... --qa-before --qa-after --summary ...`): status/PR/theme + QA screenshots.
  - **Create** (`ticket.sh --create ...`): create a new ticket — see below.

### Shared library
- **`_firestore-lib.sh`** — sourced by all scripts. Firestore REST helpers:
  - Reads: `query_ticket`, `query_tickets_by_status/_project/_range`, `get_document`, `get_project_by_id`, `get_client_by_id`, `fs_*` extractors
  - Writes: `update_ticket`, `append_content`, `update_ticket_array`
  - **Create-mode (added 2026-06-19):** `normalize_channel`, `query_clients_by_slack_channel`, `query_projects_by_client`, `create_ticket`, `wait_for_display_id`

### Create-mode flow (`ticket.sh --create`)
1. Resolve client — by `--client-id`, else by `--channel` (slack) via `query_clients_by_slack_channel`.
   If a channel matches >1 client → list + require `--client-id`.
2. Resolve project — `query_projects_by_client`. If >1 project → list + require `--project-id`.
   Denormalize `projectName`/`clientName`/`shopifyStoreId`, then store URL from `shopifyStores`.
3. Build the Firestore `fields` payload (mirrors `dataService.createTicket`), **omitting** `ticketNumber`/`displayId`. `source:"cli"`.
4. `create_ticket` (POST auto-ID doc) → `wait_for_display_id` polls until the trigger mints TICK-N.
5. Attachments: `qa/upload-attachment.js` uploads each `--attach` file to Storage; URL → `attachments[]` (+ `screenshots[]` if image) + an "Attachments" section appended to `content`.

   Flags: `-c/--channel`, `-N/--name` (required); `-d/--description`, `-D/--description-file`,
   `-s/--status`, `--client-id`, `--project-id`, `--rush`, `--page-url`, `-a/--attach` (repeatable), `--dry-run`.
   Use `--dry-run` to preview resolution + payload without writing. Typical use: an agent reads a
   brief/PDF/source, synthesizes title + description, then calls create mode.

### QA subsystem (`qa/`)
- **`upload-attachment.js`** — upload ANY file (PDF/source/image) to `ticket-attachments/`, return public URL. (Used by create mode.)
- **`upload-screenshot.js`** — QA before/after screenshot upload → `qa-screenshots/`, writes `qa_screenshots` collection.
- **`capture-screenshot.js`** — full-page Chrome capture with viewport matching.
- **`extract-feedbucket.sh`**, **`compare-screenshots.sh`** — Feedbucket image extraction / before-after diff.
- `service-account.json` — Firebase Admin creds (Storage). `firebase-config.json`, `package.json`, `node_modules/`.
- **`ticket-qa.sh`** (top level) — orchestrates QA before/after via the `qa/` node scripts.

### Other ticket scripts
- **`ticket-navigate.sh`** — fetch + local directory lookup.
- **`ticket-estimator.sh`** — time/credit estimation.
- **`ticket-update-credits.sh`** — write credit fields.
- **`ticket-batch-fetch.sh`** / **`ticket-batch-complete.sh`** — batch fetch / batch complete.

### Quote analysis (duplicate detection)
- **`quote-workflow.sh`** (orchestrator) → `quote-fetch-ticket.sh`, `quote-batch-fetch.sh`, `quote-compare.sh`, `quote-analyzer.sh`.

### Batch (`batch/`)
- **`batch/workflow.sh`** — end-to-end batch processing. **`batch/qa-capture.sh`** — batch Feedbucket/page-URL extraction. `categorization_rules.json`.

---

## Conventions
- Add new Firestore access through `_firestore-lib.sh`, not ad-hoc curl, so auth/escaping stay consistent.
- String values written via REST must be JSON-escaped (`jq -Rs`) — `update_ticket` already does this.
- Never set `ticketNumber`/`displayId` on create; the trigger owns them.
- Reads/writes assume an authenticated `gcloud` session; run `gcloud auth login` if calls 401.

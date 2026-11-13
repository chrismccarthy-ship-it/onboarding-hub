# Onboarding Hub — Solution Guide

*White-label client & employee onboarding for Salesforce — Service Cloud · Experience Cloud · Agentforce.*
*Covers Phase 1 (platform), Phase 2 (AI document intelligence), and Phase 3 (reminders, notifications, doc-gen). Last updated: 2026-11-04.*

---

## 1. What this is

**Onboarding Hub** is a configurable onboarding platform on Salesforce. A single dashboard component drives client and employee onboarding — KYC, document collection, integration setup, enablement — and **rebrands per bank** (Citi, Citizens, ICE…) by changing one field, with no redeploy.

It serves three audiences from one data model and one core component:

| Audience | Surface | What they see |
|---|---|---|
| **Internal ops** | Lightning app/record page | Full checklist, internal procedure notes, AI document actions, compliance gates |
| **Clients** | Experience Cloud portal | A clean, branded view of what's needed and progress — internal content filtered out server-side |
| **Agentforce** | Service agent | Reads checklist status and completes items conversationally |

**Phase 2 headline:** ops never types business data — a client uploads a document, an AI reads it, the KYC fields populate, the item completes itself, with a confidence gate routing low-confidence extractions to a human.

**Phase 3 headline:** the platform chases the work for you — a scheduled engine sends multi-channel reminders with an escalation ladder, and generates + emails a branded sign-off PDF, logging every action.

---

## 2. Architecture at a glance

```
   Internal ops  ─────►  onboardingHub LWC (dashboard)
   Client (portal) ───►  onboardingPortal LWC
                                  │  getDashboard() (cacheable, server-side portal filtering)
                                  ▼
                    OnboardingDashboardController (Apex)
   Data model:  Checklist__c ─(M-D)─ Checklist_Item__c ─(M-D)─ Checklist_Item_Step__c
                            Dashboard_Config__c (branding)

   ── Phase 2 (AI) ───────────────────────────────────────────────
   onboardingDocUpload ─► OnboardingDocAnalyzer ─► AnalyzerJob (Queueable)
        read txt/csv → KYC prompt → Models API (gpt-4o-mini) → write business fields
        → confidence ≥ 70 ? auto-complete : Needs Review → AI_Analysis_Complete__e (live UI)

   ── Phase 3 (engine) ──────────────────────────────────────────
   OnboardingReminderScheduler (daily) ─► OnboardingReminderBatch (Batchable, callouts)
        find overdue / due-soon items (quiet-period guarded)
        ├─ reminder on item channel ─► OnboardingNotifier ─┐
        └─ escalate (level ≥ 2) to Onboarding Specialist   │
   OnboardingNotifier (router):  Email + In-App (real) · Slack + SMS (config-gated callout)
        every send → Notification_Log__c
   OnboardingDocGenerator (@Invocable) ─► OnboardingDesignDoc (VF renderAs pdf)
        → save File to checklist → email client
```

**Agentforce:** `OnboardingAgentActions.getChecklistStatus()` and `OnboardingItemActions.completeItem()` (one `@InvocableMethod` per class).

---

## 3. Data model

- **`Checklist__c`** — the journey. Record types **Client** / **Employee**. Type, segment, status, dates, rolled-up progress %, comms channel, specialist/sales/manager lookups, and AI-populated business fields (`Legal_Entity_Name__c`, `DBA_Name__c`, `Business_Address__c`, `Tax_ID__c`, `Date_of_Incorporation__c`).
- **`Checklist_Item__c`** — a task (master-detail). Required/due/signature flags, category, `Visible_In_Portal__c`. **Phase 2:** `AI_Extracted_Data__c`, `AI_Confidence__c`, `AI_Last_Run__c`, `Auto_Complete_On_Analysis__c`, `AI_Analysis_Status__c`. **Phase 3:** `Escalation_Level__c`, plus reminder hooks `Reminder_Count__c`, `Last_Reminder_Date__c`, `Reminder_Channel__c`.
- **`Checklist_Item_Step__c`** — sub-steps (master-detail).
- **`Dashboard_Config__c`** — white-label branding profile.
- **`Notification_Log__c`** *(Phase 3)* — one row per notification: Channel, Status (Sent/Simulated/Failed), Recipient, Message, Sent Date, related item.

**Events:** `AI_Analysis_Complete__e` (Phase 2, live UI). **Config:** `Onboarding_Channel_Config__mdt` (Phase 3, Slack/SMS endpoint + enabled).

---

## 4. Components

### Apex
| Class | Responsibility |
|---|---|
| `OnboardingDashboardController` | Cacheable `getDashboard()`, `completeStep/completeItem` + rollups, server-side portal filtering |
| `OnboardingDocAnalyzer` / `AnalyzerJob` | Phase 2: read docs → Models API → extract KYC fields → auto-complete/needs-review → platform event |
| `OnboardingDocService`, `OnboardingRollup` | Phase 2: file ops; standalone checklist rollup |
| `OnboardingAgentActions` / `OnboardingItemActions` | Agentforce invocable actions |
| `OnboardingReminderBatch` / `OnboardingReminderScheduler` | Phase 3: scheduled reminder/escalation engine (quiet-period guarded, callouts-before-DML) |
| `OnboardingNotifier` | Phase 3: channel router → `Notification_Log__c` |
| `OnboardingDocGenerator` / `OnboardingDesignDocController` | Phase 3: `@Invocable` PDF generate + email; VF controller |

### LWC
`onboardingHub` (internal dashboard) · `onboardingDocUpload` (upload + Analyze) · `onboardingPortal` (Experience Cloud).

### Declarative
`Onboarding_Doc_Extraction` prompt template · `OnboardingDesignDoc` VF page (renderAs pdf) · `Onboarding_Alert` custom notification type · `Slack_Hooks` / `SMS_Provider` Remote Site Settings.

---

## 5. Configuration & setup

> **Environment:** org alias `devhub`, API 62.0, Windows + PowerShell + `sf` CLI. Run from the folder containing `sfdx-project.json`.

### 5.1 Prerequisites
- Einstein Generative AI **ON**; user has **Einstein Generative AI User**.
- Model `sfdc_ai__DefaultOpenAIGPT4OmniMini` available.

### 5.2 Deploy (per phase project)
```powershell
sf project deploy start --source-dir force-app --target-org devhub --ignore-conflicts   # p1, then p2, then p3
sf org assign permset --name OnboardingHub_Admin   --target-org devhub
sf org assign permset --name OnboardingHub_Phase3  --target-org devhub
```
Validate with `--dry-run` first. `GenAiPromptTemplate` and Windows-authored LWC bundles may perpetually report `Changed` (cosmetic normalization/line-endings).

### 5.3 Access & record types
Assign the permission sets (FLS is mandatory — new fields are invisible otherwise). Assign the `Checklist__c` **Client/Employee** record types on the profile.

### 5.4 Branding
Create a `Dashboard_Config__c` per brand; point a checklist via `Dashboard_Config_Name__c`.

### 5.5 Place components
`onboardingHub` on an internal page (Internal View = ON); `onboardingDocUpload` on the Checklist Item record page; `onboardingPortal` in Experience Cloud.

### 5.6 Channels (Phase 3)
Email + in-app bell work out of the box. To make **Slack/SMS** real: set the endpoint + `Enabled` on the matching `Onboarding_Channel_Config__mdt` record and activate the matching Remote Site Setting (`Slack_Hooks` is pre-activated for hooks.slack.com; edit `SMS_Provider` for your provider). Until then they log **Simulated**.

---

## 6. How to use it

- **Internal ops:** open the checklist — progress ring, items, status dots, filter pills, internal notes, action chips. Expand an item for its steps.
- **AI analysis (Phase 2):** upload a **text** doc (txt/csv) to the Business Verification item → **Analyze Documents** → fields populate, item auto-completes at confidence ≥ 70 (else Needs Review). Headless: `OnboardingDocAnalyzer.analyzeItem(itemId);`.
- **Portal:** `onboardingPortal` renders the same checklist for the client; internal content and `Visible_In_Portal__c = false` items are filtered server-side.
- **Agentforce:** "Get Onboarding Checklist Status" / "Complete Onboarding Item" actions.
- **Reminders (Phase 3):** schedule with `OnboardingReminderScheduler.scheduleDaily();`. The batch reminds overdue/due-soon items on their channel and escalates to the specialist. Review `Notification_Log__c`.
- **Doc-gen (Phase 3):** the "Generate & Send" action (`OnboardingDocGenerator`) renders the sign-off PDF, saves it to the checklist, and emails the client.

---

## 7. Testing

| Layer | Proves | How |
|---|---|---|
| Unit — P2 | Analyzer plumbing | `sf apex run test --class-names OnboardingDocAnalyzerTest …` |
| Unit — P3 | Batch, quiet-period, escalation, notifier (sim + mocked callout), doc-gen | `sf apex run test --class-names OnboardingPhase3Test …` |
| E2E — AI | Real extraction → fields + auto-complete | Upload sample txt, Analyze, query item + checklist |
| E2E — reminders | Multi-channel send + log | Run `OnboardingHub_Phase3_DemoSetup.apex`, query `Notification_Log__c` |
| Portal | Server-side filtering | Open portal as a community user |

> **Coverage caveat (P2):** `OnboardingDocAnalyzer.callModel` returns `null` in tests, so JSON parse / field-mapping / confidence are only proven by the E2E run, not the unit suite.

---

## 8. Limitations & known issues

### Functional / by design
- **Text files only** for AI analysis (txt/csv). Binary PDFs need OCR (marked extension point) — not implemented.
- **AI is non-deterministic**; the **70** confidence cutoff is a tunable business decision.
- **Confidence gate vs. parse failure look identical in the UI** — check `AI_Extracted_Data__c`.
- **Async** analysis + batch (Queueable/Batchable) — results aren't instant.
- **Org-specific Models API shape** (`Code200.generation.generatedText`, instance call).
- **Reminder cadence:** due-within-3-days or overdue, suppressed by a 2-day quiet-period guard (both tunable on the batch). In-app is an internal channel; escalations go to the Onboarding Specialist (fallback: owner).
- **PDF** is a print-simple design/sign-off summary, not a contract.

### ⚠️ Open UX gaps (Phase 2 punch-list)
- **`onboardingDocUpload` upload path is unreliable** — in testing it failed to attach; fix before portal use.
- **Dashboard "Analyze Documents" is a Phase 1 stub** — wire it to `OnboardingDocAnalyzer.analyzeItem`, or embed the upload in the item.

### Platform / operational
- **FLS is mandatory** — assign `OnboardingHub_Admin` + `OnboardingHub_Phase3`.
- **Record-type assignment is profile-based**; demo scripts fall back to the default record type.
- **Slack/SMS need external infra** (webhook/provider + active Remote Site Setting) — real-capable, ship **simulated**.
- **Email deliverability** depends on org settings + a recipient Contact email.
- **Windows:** never `Set-Content -Encoding UTF8` for Apex/XML (BOM breaks compile); LWC/prompt-template source tracking shows perpetual `Changed`.
- **Single org, no managed package.**

### Not yet built (roadmap)
- **Phase 4 (optional):** Supabase external data layer for raw integration/file telemetry.
- **E-signature:** `Signature_Required__c` / `Signature_Captured__c` exist but aren't wired to a signing flow.
- **Real Slack/SMS** endpoints (config stubs shipped).

---

## 9. Quick reference

```powershell
# deploy a phase + grant access
sf project deploy start --source-dir force-app --target-org devhub --ignore-conflicts
sf org assign permset --name OnboardingHub_Admin --target-org devhub
sf org assign permset --name OnboardingHub_Phase3 --target-org devhub
```
- **Rebrand:** `Checklist__c.Dashboard_Config_Name__c` (Citi ↔ Citizens).
- **Analyze headlessly:** `OnboardingDocAnalyzer.analyzeItem(itemId);`
- **Schedule reminders:** `OnboardingReminderScheduler.scheduleDaily();`
- **The five first-deploy breakers:** duplicate `@InvocableMethod`, LWC `lightningCommunity__Page` property tags, UTF-8 BOM, missing FLS permission set, unassigned record type.

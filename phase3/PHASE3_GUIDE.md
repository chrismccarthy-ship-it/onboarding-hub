# Onboarding Hub — Phase 3

Reminder & escalation engine, multi-channel notifications, and document generation + email-back.

## What's in Phase 3

**New object:** `Notification_Log__c` — one row per notification (Channel, Status = Sent/Simulated/Failed, Recipient, Message, Sent Date, related Checklist Item). Your audit trail and the proof for the demo.

**New field:** `Checklist_Item__c.Escalation_Level__c` (0 = reminder, 1 = overdue nudge, 2+ = escalated).

**Apex**
- `OnboardingReminderBatch` (Batchable + AllowsCallouts + Stateful) — finds required, portal-visible items that are overdue or due within 3 days; dispatches a reminder on the item's channel; at escalation level ≥ 2 also pings the specialist in-app; maintains `Reminder_Count__c`, `Last_Reminder_Date__c`, `Escalation_Level__c`. **All callouts run before DML**, which is why `OnboardingNotifier.dispatch()` returns an unsaved log that the batch bulk-inserts at the end.
- `OnboardingReminderScheduler` (Schedulable) — `scheduleDaily()` schedules a 7:00 daily run.
- `OnboardingNotifier` — channel router. **Email + In-App bell send for real.** **Slack + SMS** do a real HTTP callout when their `Onboarding_Channel_Config__mdt` record is **Enabled** with an **Endpoint** (and a Remote Site Setting for the host); otherwise they record **Simulated**. Endpoints are configuration, not code.

**Config (Custom Metadata):** `Onboarding_Channel_Config__mdt` with records `Slack` and `SMS` (fields `Endpoint__c`, `Enabled__c`). **Remote Site Settings:** `Slack_Hooks` (hooks.slack.com, active) and `SMS_Provider` (placeholder — edit the URL and activate).
- `OnboardingDocGenerator` — `@InvocableMethod` "Generate & Send": renders the PDF, saves it to the checklist as a File, emails it to the client. Callable from a Flow, the dashboard action, or an Agentforce action.
- `OnboardingDesignDocController` — backs the PDF page.
- `OnboardingPhase3Test` — covers the batch, scheduler, notifier (simulated + mocked real callout), and doc generator.

**Visualforce:** `OnboardingDesignDoc` (`renderAs="pdf"`) — branded design/sign-off document.

**Custom Notification Type:** `Onboarding_Alert` — drives the in-app bell.

## Deploy

```powershell
# from the phase3 project folder
sf project deploy start --source-dir force-app --target-org devhub --dry-run
sf project deploy start --source-dir force-app --target-org devhub --ignore-conflicts
sf org assign permset --name OnboardingHub_Phase3 --target-org devhub
```

> Requires Phase 1 + Phase 2 already deployed (it references `Checklist__c`, `Checklist_Item__c`, and their fields).

## Run the demo

Execute Anonymous → paste `OnboardingHub_Phase3_DemoSetup.apex` → run. It fires one notification per channel, generates the design PDF, and logs everything. Then check:

```powershell
sf data query --target-org devhub --query "SELECT Channel__c, Status__c, Recipient__c, Sent_Date__c FROM Notification_Log__c ORDER BY CreatedDate DESC LIMIT 10"
```
Expect Email + In-App = **Sent**, Slack + SMS = **Simulated** (until you configure endpoints). The PDF appears under the checklist's **Files**.

**Schedule the engine:** `OnboardingReminderScheduler.scheduleDaily();` (Execute Anonymous).

## Enabling real Slack / SMS

No code change needed — it's all configuration:

**Slack** (host already allow-listed via the `Slack_Hooks` Remote Site Setting):
1. Create a Slack **Incoming Webhook** and copy the URL.
2. Setup → Custom Metadata Types → **Onboarding Channel Config** → Manage Records → **Slack** → set `Endpoint` to the webhook URL and tick `Enabled`.

**SMS:**
1. Edit the **`SMS_Provider`** Remote Site Setting: set the URL to your provider's host and set it active.
2. Set the **SMS** channel config `Endpoint` (your provider's POST endpoint) and tick `Enabled`.

Until enabled, both exercise the real code path but record **Simulated** — safe for demos, honest in the log. The expected payloads are `{"text": "..."}` for Slack and `{"to": "...", "message": "..."}` for SMS; adjust `OnboardingNotifier.sendSlack` / `sendSms` if your provider differs.

## Limitations & notes

- **Slack/SMS need external infra** (webhook/provider + Remote Site Setting). They are *real-capable* but ship **disabled → simulated**; don't promise live Slack/SMS in a demo without configuring them (see above).
- **Email deliverability** depends on org email settings / deliverability mode and the recipient on the Checklist's Contact. No contact email → the notifier logs `Simulated`.
- **In-app bell** requires access to the `Onboarding_Alert` type. Client reminders on the `In-App` channel notify the running user; **escalations** (level ≥ 2) notify the checklist's **Onboarding Specialist**, falling back to the checklist **Owner**. In-app is an internal channel — don't set a client-facing item's reminder channel to In-App.
- **Reminder cadence:** items are reminded when due within `dueWindowDays` (3) or overdue, and a `quietDays` (2) guard suppresses any item reminded within that window, so an overdue item is pinged at most once every 2 days — not every run. Both are public fields on the batch if you want to tune them.
- **PDF** is generated server-side via Visualforce; styling is intentionally print-simple. It is a design/sign-off summary, not a contract.
- The batch processes **portal-visible, required** items only — internal-only items don't generate client reminders by design.

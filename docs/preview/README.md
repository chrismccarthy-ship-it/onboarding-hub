# Onboarding Hub — Visual Preview

Static renders of the `onboardingHub` LWC, built from the component's own HTML/CSS and populated with the Phase 1 demo data (Lakeside Regional Holdings — NACHA integration). These are **previews only**; the live component runs in Salesforce after deploy.

| File | View | Branding | Notes |
|---|---|---|---|
| `01-internal-citi.png` | Internal ops | Citi | Full view: business profile, internal notes, action chips, steps |
| `02-internal-citizens.png` | Internal ops | Citizens | Identical data/code — only `Dashboard_Config_Name__c` changed |
| `03-portal-external.png` | External portal | Citi | `isInternal = false`; internal-only content + items stripped server-side |
| `04-portal-mobile.png` | External portal (mobile) | Citi | Responsive stacking via the component's media queries |

## HTML mockups

The `*.html` files are self-contained, openable in any browser — useful for click-throughs in a demo without an org:

- `internal-citi.html`
- `internal-citizens.html`
- `portal-external.html` (also the source for the mobile render — resize the window)

## How the views differ

| Element | Internal | Portal | Mechanism |
|---|---|---|---|
| "Internal View" chip | shown | hidden | `if:true={isInternal}` |
| Business Profile panel | shown | hidden | `showBusinessDetails && isInternal` |
| Internal Procedure notes | shown | hidden | `showInternalNotes = isInternal` |
| Action chips | shown | hidden | `if:true={isInternal}` |
| Step "Mark done" | shown | hidden | `canComplete = … && isInternal` |
| `Visible_In_Portal__c = false` items | shown | **removed** | filtered in Apex `getDashboard()` before the payload is sent |

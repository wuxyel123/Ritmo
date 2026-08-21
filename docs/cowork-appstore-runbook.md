# Cowork routine — fill the App Store Connect listing

A task you can hand to Cowork to fill in every App Store Connect field for
Ritmo 1.0. Everything below is a value already decided elsewhere in this repo;
this file exists so none of it has to be retyped or re-reasoned.

**How to use it:** open Cowork with App Store Connect already signed in, and
paste the block in [The task](#the-task). Everything after that section is
reference material the task points at.

---

## Before you start — things Cowork cannot do for you

These need your Apple ID, your password, or your signature. Do them first or the
routine will stall halfway.

- [ ] Apple Developer Program enrolment **active**
- [ ] **Free Apps agreement accepted** — App Store Connect › Business. This is a
      contract; sign it yourself. Nothing else is needed, since Ritmo is free.
- [ ] **App record created** — bundle ID `com.alessandrodiscalzi.ritmo`,
      SKU `ritmo`. Both are permanent, so create the record by hand.
- [ ] **Build uploaded** and finished processing — Xcode › Product › Archive ›
      Distribute › App Store Connect. Version `1.0`, build `1`.
- [ ] **Confirm the app name you actually reserved.** The listing copy assumes
      `Ritmo: Training & Recovery` / `Ritmo: Carico e Recupero`. If you reserved
      something else, the name field must match the reservation — tell Cowork
      the real name before it starts.

## Guardrails — put these in the task, they matter

The routine fills forms on a live account that publishes software under your
name. Cowork must **not**:

- Click **Submit for Review**. Fill everything, then stop and hand back.
- Accept any agreement, contract, or terms on your behalf.
- Enter passwords or 2FA codes. If it hits a login wall, it stops and asks.
- Change the bundle ID, SKU, or primary language — all permanent after release.
- Invent an answer to a legal question. The declarations below are pre-decided;
  if the form asks something not covered here, it stops and asks you.

---

## The task

> Fill in the App Store Connect listing for my app **Ritmo**, version 1.0.
> All values come from `docs/cowork-appstore-runbook.md` in the repo at
> `/Users/alessandrodiscalzi/Developer/Projects/FitSync` — read it first and use
> it as the source of truth for every field.
>
> Rules:
> - Do **not** click "Submit for Review". Fill everything, save, then stop and
>   tell me what is left.
> - Do **not** accept any agreement or terms, and do not enter any password or
>   2FA code. If you hit one, stop and ask me.
> - Do **not** change the bundle ID, SKU, or primary language.
> - If a form asks something the runbook does not cover, stop and ask rather
>   than guessing — several of these are legal declarations.
>
> Work through sections 1–7 of the runbook in order. When you are done, run the
> verification checklist in section 8 and report anything that did not save.

---

## 1. App Information

| Field | Value |
|---|---|
| Primary language | English (U.S.) |
| Bundle ID | `com.alessandrodiscalzi.ritmo` |
| SKU | `ritmo` |
| Primary category | Health & Fitness |
| Secondary category | Sports |
| Content rights | Does **not** contain third-party content |
| Age rating | **4+** — answer "None" / "No" to every questionnaire item |

## 2. Pricing and Availability

| Field | Value |
|---|---|
| Price | **Free** |
| Availability | All countries and regions |
| Pre-orders | No |
| Distribution | Public on the App Store |

## 3. Localised listing text

Two locales: **English (U.S.)** as primary, **Italian** as secondary. The full
paste-ready text — name, subtitle, promotional text, keywords, description,
what's new — is in [`app-store-listing.md`](app-store-listing.md). Copy each
field verbatim; the character counts there were checked against Apple's limits.

Two things not to "improve" while pasting:

- **Keywords must not mention Hevy, Strava or OpenPowerlifting.** Other
  companies' trademarks in the keywords field are a routine rejection.
- **Do not add health claims.** No "improve your recovery" phrasing. Ritmo is an
  analytics app, not a medical device, and the description is written to stay on
  the right side of that line.

## 4. Screenshots

Upload from `screens/upload/`. Use the **6.9" set first** — the smaller display
sizes are auto-filled by scaling down from the largest, and nothing can fill
6.9" for you.

| Slot | Folder | Size |
|---|---|---|
| iPhone 6.9" | `screens/upload/iphone-6.9-inch/` | 1320 × 2868 |
| iPhone 6.5" | `screens/upload/iphone-6.5-inch/` | 1284 × 2778 |
| iPhone 6.3" | `screens/upload/iphone-6.3-inch/` | 1206 × 2622 |
| iPhone 6.1" | `screens/upload/iphone-6.1-inch/` | 1170 × 2532 |
| Apple Watch | `screens/upload/watch/` | 416 × 496 |

Order is encoded in the watch filenames (`1-score`, `2-recovery-health`,
`3-sleep`, `4-nutrition`). App Store Connect validates against whichever display
size tab is selected, so a correct file in the wrong tab is rejected — match the
folder to the tab.

Apple requires the **Watch screenshots be the same size across every
localisation**, so use these same four for both English and Italian.

## 5. App Privacy

App Store Connect › App Privacy.

> **"Do you or your third-party partners collect data from this app?" → No.**

That single answer short-circuits the entire questionnaire. It is correct
because of how the app is built, and the reasoning is in
[`../SUBMISSION.md`](../SUBMISSION.md): no analytics, no crash reporting, no ads,
no third-party SDKs, no developer-controlled server to transmit to. Health data
stays in Apple Health and the local database. The Hevy / Strava /
OpenPowerlifting calls go from the user's device straight to those services with
the user's own credentials to fetch the user's own data.

Supporting evidence if App Review pushes back: no networking code targets a
developer-controlled host, and `PrivacyInfo.xcprivacy` declares
`NSPrivacyTracking = false` with an empty `NSPrivacyCollectedDataTypes`.

**Privacy policy URL** — required, health apps cannot ship without one:

```
https://wuxyel123.github.io/Ritmo/privacy.html
```

## 6. Other listing fields

| Field | Value |
|---|---|
| Support URL | the GitHub repository |
| Marketing URL | leave empty |
| Copyright | `2026 Alessandro Discalzi` — **displays publicly** |
| Version | `1.0` |
| Release | Manually release this version |

## 7. App Review Information

Contact details are yours to fill. No demo account is needed — the app has no
login.

**Review notes** — this matters more than usual for Ritmo, because a reviewer's
device has almost no health history and several screens will legitimately look
empty. Paste:

```
Ritmo reads Apple Health. HealthKit permission must be granted or every screen
will legitimately appear empty — a review device with no health history will
show zeros throughout, which is expected behaviour rather than a defect.

Hevy, Strava and OpenPowerlifting are optional integrations. Each is off by
default and requires the reviewer's own account credentials, so none of them is
needed to evaluate the app.

There is no login and no demo account: the app has no server and no user
accounts.
```

**Export compliance** — already declared in the build.
`ITSAppUsesNonExemptEncryption = false` is set in `Ritmo iOS/Info.plist`, so App
Store Connect should not ask. The declaration is accurate: the app contains no
custom cryptography (no CryptoKit, no CommonCrypto) and uses only standard
HTTPS through `URLSession`, which is exempt. If the form appears anyway, that is
the answer.

**EU Digital Services Act — trader status.** Leave this to Alessandro. Shipping
free with no revenue makes the non-trader reading defensible, which also avoids
publishing a home address on the EU listing, but it is a legal declaration and
should be confirmed with a commercialista. Revisit the moment any money changes
hands.

## 8. Verification checklist

Before handing back, confirm each of these actually saved — App Store Connect
silently drops changes when a required field elsewhere on the page is empty:

- [ ] Both locales (English and Italian) have name, subtitle, keywords,
      description and What's New filled
- [ ] Screenshots present in the 6.9" iPhone slot **and** the Watch slot
- [ ] Privacy policy URL saved and resolving
- [ ] App Privacy shows "Data Not Collected"
- [ ] Age rating shows 4+
- [ ] Price shows Free, availability all territories
- [ ] Build 1.0 (1) is attached to the version
- [ ] Review notes saved
- [ ] **Not** submitted for review

Then report: what saved, what did not, and anything the forms asked that this
runbook did not answer.

---

## Deliberately left to you

Not automation gaps — decisions that should not be delegated.

- **Submitting for review.** The routine stops one click short.
- **DSA trader status.** A legal declaration about you, not about the app.
- **The Hevy question.** Still unresolved: their terms could not be retrieved to
  confirm whether a publicly distributed third-party client may use the API with
  per-user keys. Draft email in [`hevy-permission-email.md`](hevy-permission-email.md).
  If they decline, removing the integration is `HevyService` plus one settings
  screen.
- **Accepting the Free Apps agreement.**

## Known risks carried into submission

So a rejection is not a surprise. Full detail in [`../SUBMISSION.md`](../SUBMISSION.md).

- **Estimated sleep stages** written to Apple Health for manually logged nights,
  tagged `RitmoEstimatedStages`. Guideline 5.1.3 forbids inaccurate HealthKit
  data; the tag keeps it honest inside Ritmo but is invisible to other apps.
  A deliberate decision, not an oversight.
- **Empty screens without Health permission** — mitigated by the review notes.
- **Strava** asks each user to register their own API application.
- **OpenPowerlifting** uses an undocumented endpoint that may change.

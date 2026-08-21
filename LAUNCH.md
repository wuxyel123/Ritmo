# Launch runbook

Ordered, with the dependencies made explicit. All of it needs your Apple ID or
your Keychain, so it is yours to do — there is nothing left on the code side.

Status legend: `[ ]` not started · `[~]` waiting on someone else · `[x]` done

---

## Phase 1 — start today, these are the slow ones

- [ ] **Free Apps agreement** — App Store Connect › Business. Accept it. That
      is all that is needed: Ritmo ships entirely free, so there is no Paid
      Apps agreement, no banking, no tax forms and no bank verification wait.
      *If Pro is ever switched on, that whole track comes back — start it well
      before, because bank verification takes weeks.*
- [ ] **Reserve the app name** — create the app record with bundle ID
      `com.alessandrodiscalzi.ritmo`. Names are unique across the whole store
      and first-come, so claim it before anything else.
      First choice `Ritmo: Training & Recovery`; if refused try
      `Ritmo — Training & Recovery`, then `Ritmo Training`.
      *→ tell Claude which name stuck so the listing copy matches.*
- [ ] **Email Hevy** — draft at `docs/hevy-permission-email.md`, add your name
      and a contact address.
      *Blocks: submitting with the Hevy integration in good conscience. If they
      decline, removing it is `HevyService` plus one settings screen.*

## Phase 2 — identifiers

Developer portal › Identifiers. Each App ID needs **HealthKit** and
**App Groups** enabled:

- [ ] `com.alessandrodiscalzi.ritmo`
- [ ] `com.alessandrodiscalzi.ritmo.watchkitapp`
- [ ] `com.alessandrodiscalzi.ritmo.widgets`
- [ ] `com.alessandrodiscalzi.ritmo.watchkitapp.watchwidget`
- [ ] App Group `group.alessandrodiscalzi.com.ritmo`

## Phase 3 — pricing

Nothing to do. The app is free with no in-app purchases, so there is no
subscription to create and no product ID to register.

`ProStore` and `PaywallView` stay in the repo, unreachable and unread. They are
kept because `AppTransaction.originalPurchaseDate` works retroactively: if Pro
is ever switched on, everyone who installed during the free era can still be
given it permanently, without 1.0 having shipped anything to record them.

**DSA trader status**: shipping free with no revenue makes the non-trader
reading defensible, which also avoids publishing a home address on the EU
listing. Confirm with a commercialista — and revisit the moment any money
changes hands.

## Phase 4 — build and verify

- [ ] **Archive** in Xcode: device destination, Product › Archive, then
      Distribute › App Store Connect.
- [ ] **Install from TestFlight on your own phone** and check the things a
      debug build cannot tell you:
  - [ ] Every feature is reachable — no PRO badges, no paywall anywhere
  - [ ] HealthKit permission prompts list the right data
  - [ ] Steps card shows distance and floors with real data
  - [ ] A manually logged nap appears in Recovery alongside the night
  - [ ] The app is in your chosen language throughout, including the daily
        recommendation and insights

## Phase 5 — listing

- [ ] Screenshots: `screens/appstore/` (1290×2796, five of them)
- [ ] Name, subtitle, keywords, description, release notes:
      `docs/app-store-listing.md` — English and Italian
- [ ] Privacy policy URL: `https://wuxyel123.github.io/Ritmo/privacy.html`
- [ ] App Privacy answers: "no data collected" — reasoning in `SUBMISSION.md`
- [ ] Age rating 4+, category Health & Fitness
- [ ] **Review notes** — this matters more than usual here. Say that Apple
      Health permissions must be granted or every screen is legitimately empty,
      and that Hevy, Strava and OpenPowerlifting are optional and need the
      reviewer's own accounts, so they are not needed to evaluate the app.

## Phase 6 — submit

- [ ] Submit for review.
- [ ] If rejected, the likeliest causes for this app, in order:
      empty screens without Health permission (fixed by the review notes),
      and the estimated sleep stages written to HealthKit (see `SUBMISSION.md`
      — known, accepted risk).

---

## Known risks carried into launch

Recorded so a rejection is not a surprise. Full detail in `SUBMISSION.md`.

- **Estimated sleep stages** are written to Apple Health for manually logged
  nights, tagged `RitmoEstimatedStages`. Guideline 5.1.3 forbids inaccurate
  HealthKit data; the tag makes it honest inside Ritmo but invisible to other
  apps. Deliberate decision, not an oversight.
- **Strava** asks each user to register their own API application. Labelled
  "Avanzato" in Settings so nobody reads it as broken.
- **OpenPowerlifting** uses an undocumented endpoint that may change.
- **No automated tests and no crash reporting**, by design. Bugs will arrive
  through reviews.
- **Bundle ID and App Group carry your surname** and are permanent after the
  first release. The App Store also shows your legal name as seller on an
  individual account.

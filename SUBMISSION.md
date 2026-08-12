# App Store submission notes

Working notes for submitting Ritmo. Everything here is derived from what the
code actually does — if the app changes, re-check it rather than trusting this
file.

## App Privacy answers (App Store Connect)

App Store Connect → your app → App Privacy.

**"Do you or your third-party partners collect data from this app?" → No.**

That answer is only correct because of how the app is built, so the reasoning
matters:

- No analytics, no crash reporting, no advertising, no third-party SDKs.
- Nothing is transmitted to the developer — there is no server to transmit to.
- Health data stays in Apple Health and the local database.
- Hevy, Strava and OpenPowerlifting requests go from the user's device straight
  to those services, carrying the user's own credentials to fetch the user's own
  data. Apple's definition of "collect" covers data transmitted off device *and*
  retained by you or your partners on the user's behalf; none of that happens
  here. If a backend is ever added (see the Strava note below), this answer must
  be revisited.

If App Review pushes back, the supporting facts are: no networking code targets
a developer-controlled host, and `PrivacyInfo.xcprivacy` declares
`NSPrivacyTracking = false` with an empty `NSPrivacyCollectedDataTypes`.

## Privacy policy URL

Required — health apps cannot ship without one. [PRIVACY.md](PRIVACY.md) is the
text. Publish it somewhere stable and paste the URL into App Store Connect. The
cheapest option is GitHub Pages on this repository, which needs no extra
infrastructure.

## Screenshots

Required sizes: 6.9" and 6.5" iPhone, plus Apple Watch if the watch app is
listed. These have to be captured on a device with real data — the simulator
has no health history, so its screens look empty and unconvincing.

Take them from: Oggi (day score populated), Allenamenti (a few workouts),
Statistiche (gym and cardio), the meet calculator, and the watch home.

## App Review notes

Reviewers test on devices with almost no health data, so several screens will
legitimately look empty. Say so in the notes, and mention that:

- HealthKit permissions must be granted for anything to appear.
- Hevy, Strava and OpenPowerlifting are optional and each requires the
  reviewer's own credentials — they are not needed to evaluate the app.

## Third-party integrations

**OpenPowerlifting** — data is released into the public domain (CC0);
attribution is encouraged and the app credits it. No permission needed. The
`/api/liftercsv/` endpoint is undocumented, so treat it as liable to change.

**Strava** — the API agreement allows showing a user their own data, which is
all Ritmo does. Requirements met: "Powered by Strava" attribution wherever
imported races are displayed; no use of Strava data for AI/ML training; no
display of one user's data to another.

Onboarding: each user registers their own Strava API application, because
Strava requires a client secret for the token exchange and does not document
PKCE support, and there is no server here to keep a shared secret on. That is
developer work to ask of an end user, so the integration is labelled "Avanzato"
in Settings and the races card points at manual entry first — nobody should
read an empty card as a broken feature.

If Strava import ever needs to be mainstream, the fix is one shared
registration plus a stateless function holding the secret for the token
exchange. It would see OAuth codes and tokens, never health data, and store
nothing — but it would still make the "no backend" claim false and require
revisiting the App Privacy answer above.

**Hevy** — unresolved. The public API requires a Hevy Pro subscription and
per-user API keys, and the terms of service could not be retrieved to confirm
whether publicly distributed third-party clients are permitted. Ask them before
shipping; a draft is in [docs/hevy-permission-email.md](docs/hevy-permission-email.md).

## Sleep stages written to Apple Health

Manually logged nights are written with a deep/REM/core split derived from the
quality rating the user picked — an estimate, not a measurement. This was
removed once as an App Review risk (5.1.3 forbids writing inaccurate data into
HealthKit) and restored at the developer's request, because Apple Health's
sleep screen is empty without it.

The mitigation: every estimated stage sample carries the metadata key
`RitmoEstimatedStages`, and the app's own sleep score reads that marker and
declines to score deep/REM it produced itself. So the estimate never becomes
evidence inside Ritmo. It is still an estimate sitting in Health where other
apps cannot tell, which is the residual risk to weigh before submitting.

## Ritmo Pro and the founding cohort

The app ships with a free tier that never sees a paywall — daily score,
recommendation, workouts, sleep, recovery and the whole Watch app — and a
yearly subscription (`com.alessandrodiscalzi.ritmo.pro.yearly`) covering
statistics, calculators, insights and the third-party integrations.

**Founding users keep Pro permanently.** Anyone whose first download predates
`ProStore.foundingWindowEnd` is entitled forever, with nothing to buy or
restore. The cohort is decided by `AppTransaction.originalPurchaseDate`, Apple's
own record, so it survives reinstalls and cannot be moved by changing the device
clock.

Before submitting:

1. **Set `ProStore.foundingWindowEnd`** to your launch date plus six months. It
   is currently 1 January 2027 as a placeholder. Once users exist, never move it
   backwards — that revokes entitlements people were promised.
2. **Create the subscription** in App Store Connect with exactly that product
   ID, in a subscription group, with a price and localized display name.
3. **Complete the Paid Apps agreement** (banking plus tax forms) — nothing can
   be sold until it is active, and bank verification takes time.
4. **Enrol in the Small Business Program** for 15% commission instead of 30%.
5. Announce the founding offer where people will see it: the App Store
   description, the welcome sheet, and wherever you post about the launch. An
   unannounced gift buys no goodwill.

### Your own copy

You are covered by the founding rule itself — your first download necessarily
predates the window, so the App Store build entitles you permanently like any
other early user. On top of that, `ProStore.debugForcePro` keeps every debug
build entitled so development never meets a paywall; it is inside `#if DEBUG`,
so it is compiled out of the shipped app rather than being a back door. Set it
to false when you want to test the locked state.

The paywall links to the privacy policy and to Apple's standard EULA. If you
write your own terms, replace that link.

Testing: with no product configured, `Product.products` returns nothing and the
paywall says the price is unavailable — the buy button stays disabled rather
than failing confusingly. Add a StoreKit configuration file in Xcode to
exercise the purchase flow locally.

## Before the first submission

Bundle identifier (`com.alessandrodiscalzi.ritmo`) and App Group cannot be
changed after the first release, and both contain the developer's surname. The
App Store also shows the seller's legal name publicly on individual developer
accounts; only an organization account (requiring a legal entity and D-U-N-S
number) displays a company name instead.

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

Open question: the app currently asks each user to register their own Strava
API application, because Strava requires a client secret for the token exchange
and does not document PKCE support. That is a poor onboarding flow for a public
release. The alternative is one shared registration with a small backend holding
the secret — which would change the App Privacy answer above and the "no
backend" claim in the README.

**Hevy** — unresolved. The public API requires a Hevy Pro subscription and
per-user API keys, and the terms of service could not be retrieved to confirm
whether publicly distributed third-party clients are permitted. Ask them before
shipping; a draft is in [docs/hevy-permission-email.md](docs/hevy-permission-email.md).

## Before the first submission

Bundle identifier (`com.alessandrodiscalzi.ritmo`) and App Group cannot be
changed after the first release, and both contain the developer's surname. The
App Store also shows the seller's legal name publicly on individual developer
accounts; only an organization account (requiring a legal entity and D-U-N-S
number) displays a company name instead.

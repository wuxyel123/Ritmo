# Ritmo

Ritmo is an iOS + watchOS fitness app built on Apple Health data. It brings workouts, sleep, nutrition, and recovery into one daily score, and adds powerlifting meet planning and endurance analysis on top, with an Apple Watch companion app and watch face complications.

No backend, no accounts — everything reads from and writes to Apple Health and SwiftData on-device.

## How this was built

Ritmo is an experiment as much as an app: the goal was to pair program an entire real project with Claude without writing a single line of code by hand. Every Swift file, the SwiftData models, the HealthKit queries, the watchOS app, the widgets and complications, and all six localizations were written by Claude in conversation.

The other half of the pairing was everything that isn't typing: deciding what to build, supplying the domain knowledge, and testing on real data. That last part carried the most weight. Bugs surfaced as observations — "with 5000 steps the distance still reads 0", "an 86 sleep score only gave 17 out of 30 points", "the warm-up makes me jump less than between my competition attempts" — and each one was traced back to a root cause and fixed. Several were subtle enough that only someone using the app with their own data would have caught them: iPhone and Apple Watch samples being summed instead of merged, a missing preference key reading back as the worst possible rating, a warm-up ramp whose jumps depended on where plate rounding happened to land.

The result is not a demo. It syncs with Apple Health, imports from Hevy and Strava, pulls competition results from OpenPowerlifting, ships watch complications and home screen widgets, and is localized in six languages.

## Features

### Daily

- **Daily score** — a composite of movement, recovery, nutrition, and workout activity, shown on iPhone and Apple Watch.
- **Today's recommendation** — push / easy / rest, from recovery, training load, and how much hard work the last two days already held.
- **Recovery** — a sleep + heart (HRV, resting heart rate) readiness score, separate from the sleep quality score.
- **Nutrition** — calorie and macro tracking sourced from any HealthKit-connected food tracker, with goal adherence driving both the progress bar color and the day score.

### Training

- **Training load** — session-RPE based load (effort × duration) with an acute-vs-chronic (7-day vs 28-day EWMA) trend, category-aware "vs your average" comparison (cardio compared to cardio, strength to strength), and a 14-day load chart.
- **RPE tracking** — set your own perceived exertion per workout, synced to Apple Health's workout effort score so it's consistent across devices and visible in the Fitness app.
- **Hevy import** — pull your workout history over the Hevy API; the Apple Health record stays canonical and is enriched with sets, reps, and per-set RPE.
- **Statistics hub** — weekly sets and tonnage, rep-range split, muscle-group frequency, session density, and per-exercise progression, split into gym and cardio sections.
- **Records timeline** — estimated 1RMs, race PBs, and session tonnage records as they happened.

### Powerlifting

- **Competition maxes** — entered by hand or pulled from OpenPowerlifting, with IPF GL points split by event type (full power vs single-lift).
- **Meet calculator** — attempts anchored at your max (third attempt = 100%, 4% jumps below) and a warm-up ramp built downwards from the opener so the jumps only ever shrink.
- **RPE calculator** — estimated 1RM from weight × reps @ RPE, and target loads per rep count, on the RTS chart.
- **Meet countdown** — on the home screen, as an iOS widget, and as a watch complication.

### Endurance

- **Personal bests** — per canonical distance from Apple Health sessions and logged races, with WMA age-grading.
- **Race log** — manual entry plus Strava import of race-tagged activities only.
- **Riegel equivalents** — predicted times at other distances, anchored to your closest PB.
- **Pace calculators** — pace / time / distance, plus expected pace from heart rate, fitted on your own runs.

### Platform

- **Sleep** — quality scoring across duration, deep/REM %, continuity, and bedtime consistency, with an interactive hypnogram; nights recorded without stage detail are scored on what was actually measured rather than counted as zero.
- **Apple Watch app** — home, nutrition, workout, sleep, health, and water tabs, plus goal sync from iPhone over WatchConnectivity.
- **Watch face complications** — daily score, rings, steps with distance and floors, days since last workout, and meet countdown.
- **iOS widgets** — daily score, activity, and macro goals, on the home screen and lock screen.
- **Siri shortcuts** — log water and ask for your day score.
- **CSV export** — workouts (one row per set) and races.
- Localized in Italian (base language), English, French, Spanish, German, and Portuguese.

## Structure

```
Ritmo/
├── Packages/RitmoCore/     ← shared Swift package: models, HealthKit repository, scoring logic
├── Ritmo iOS/              ← iPhone app
├── Ritmo watchOS/          ← Apple Watch app
├── Ritmo Widgets/          ← iOS home/lock screen widgets
└── Ritmo Watch Widget/     ← watch face complications
```

`RitmoCore` has no UI dependencies — it owns HealthKit access, SwiftData models, and the scoring, training-load, meet-planning, and endurance math shared by every target. Keeping that logic UI-free is also what makes it testable outside a simulator, which is how the scoring and meet-ramp fixes were verified.

## Privacy

Nothing is collected. There is no server, no account, and no analytics — health
data stays in Apple Health and in a local database on the device. See
[PRIVACY.md](PRIVACY.md).

## Setup

See [SETUP.md](SETUP.md) for the full Xcode project setup (targets, HealthKit entitlements, App Group, signing), and [SUBMISSION.md](SUBMISSION.md) for App Store notes.

Hevy, Strava, and OpenPowerlifting are optional: each is configured in Settings with your own API key, OAuth app, or username.

## Requirements

- Xcode 16+
- iOS 26 / watchOS 10 (see deployment targets in the project)
- A physical iPhone for HealthKit testing (the simulator has no real health data)
- Apple Watch paired to the test iPhone for the companion app

## License

See [LICENSE](LICENSE). Source-available for non-commercial use; all commercial rights are reserved.

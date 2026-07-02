# Ritmo

Ritmo is an iOS + watchOS fitness app built on Apple Health data. It brings workouts, sleep, nutrition, and recovery into one daily score, with an Apple Watch companion app and watch face complications.

No backend, no accounts — everything reads from and writes to Apple Health and SwiftData on-device.

## Features

- **Daily score** — a composite of movement, recovery, nutrition, and workout activity, shown on iPhone and Apple Watch.
- **Training load** — session-RPE based load (effort × duration) with an acute-vs-chronic (7-day vs 28-day EWMA) trend, category-aware "vs your average" comparison (cardio compared to cardio, strength to strength), and a 14-day load chart.
- **RPE tracking** — set your own perceived exertion per workout, synced to Apple Health's workout effort score so it's consistent across devices and visible in the Fitness app.
- **Recovery** — a sleep + heart (HRV, resting heart rate) readiness score, separate from the sleep quality score.
- **Sleep** — quality scoring across duration, deep/REM %, continuity, and bedtime consistency, with an interactive hypnogram.
- **Nutrition** — calorie and macro tracking sourced from any HealthKit-connected food tracker, with goal adherence driving both the progress bar color and the day score.
- **Apple Watch app** — home, nutrition, workout, sleep, health, and water tabs, plus goal sync from iPhone over WatchConnectivity (the watch has no CloudKit of its own).
- **Watch face complications** — a rings-style circular complication and a rectangular one, backed by a WidgetKit extension.
- **iOS widgets** — daily score, activity, and macro goals, on the home screen and lock screen.
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

`RitmoCore` has no UI dependencies — it owns HealthKit access, SwiftData models, and the scoring/training-load math, shared by every target.

## Setup

See [SETUP.md](SETUP.md) for the full Xcode project setup (targets, HealthKit entitlements, App Group, signing).

## Requirements

- Xcode 16+
- iOS 26 / watchOS 10 (see deployment targets in the project)
- A physical iPhone for HealthKit testing (the simulator has no real health data)
- Apple Watch paired to the test iPhone for the companion app

## License

See [LICENSE](LICENSE). Source-available for non-commercial use; all commercial rights are reserved.

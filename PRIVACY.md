# Privacy Policy — Ritmo

**Last updated: 12 August 2026**

> The hosted copy served to the App Store lives in [privacy.html](privacy.html).
> Keep the two in sync when this changes.

Ritmo is a fitness app for iPhone and Apple Watch. This policy describes what
the app does with your data. The short version: it stays on your device, and
the developer never receives any of it.

## What Ritmo collects

**Nothing is collected.** Ritmo has no servers, no accounts, no analytics, no
advertising, and no third-party tracking SDKs. No usage data, crash data, or
personal information is transmitted to the developer.

## Data Ritmo reads

With your explicit permission, Ritmo reads from **Apple Health**:

- Activity: steps, distance, flights climbed, active and resting energy,
  exercise minutes
- Body: weight, body fat, lean mass, BMI
- Heart: heart rate, resting heart rate, heart rate variability, VO₂ max,
  blood oxygen, respiratory rate
- Nutrition: calories, protein, carbohydrates, fat, fibre, water
- Sleep analysis
- Workouts, including routes and workout effort scores
- Characteristics: date of birth and biological sex, used only for age-graded
  race results and heart-rate zone calculations

You grant these permissions individually in Apple Health and can revoke any of
them at any time in Health › your profile › Apps and services › Ritmo.
Denying a permission simply means the related metric is unavailable.

## Data Ritmo writes

With your permission, Ritmo writes to Apple Health only what you enter
yourself: water intake, manually logged sleep, workouts you create in the app,
and the perceived exertion (RPE) you assign to a workout.

Manually logged sleep is written as a single "asleep" period plus the
interruptions you reported. Ritmo does not write sleep stage detail, because it
does not measure any.

## Where your data is stored

On your device only, in Apple Health and in the app's local database.
Ritmo does **not** use iCloud sync for its own database. Data shared with the
Ritmo widgets and the Apple Watch app stays inside a private App Group on your
devices.

Deleting the app removes its local database. Data Ritmo wrote to Apple Health
remains in Apple Health, under your control, and can be deleted there.

## Optional third-party connections

These are off by default. Each requires you to supply your own credentials, and
each sends requests directly from your device to that service — never through
the developer.

- **Hevy** — if you enter your own Hevy API key, Ritmo fetches your workout
  history to enrich the corresponding Apple Health workouts. Your key is stored
  on your device.
- **Strava** — if you connect your own Strava API application, Ritmo imports
  activities you tagged as races. Only your own data is requested, and it is
  shown only to you. Your tokens are stored on your device. You can revoke
  access at any time from your Strava account settings.
- **OpenPowerlifting** — if you enter your OpenPowerlifting username, Ritmo
  fetches your public competition results from openpowerlifting.org.

Each service's own privacy policy governs the data it holds. Removing a
connection in Settings stops all further requests to that service.

## Health data and advertising

Ritmo does not use health or fitness data for advertising or marketing, does
not share it with third parties, and does not use it for data mining. There is
no mechanism by which it could: the data never leaves your device.

## Children

Ritmo is not directed at children under 13 and collects no data from anyone.

## Changes

Material changes to this policy will be published here with an updated date.

## Contact

Questions about this policy can be raised as an issue on the project's GitHub
repository.

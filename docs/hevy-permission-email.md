# Draft: permission request to Hevy

Send to Hevy support (support@hevyapp.com, or whichever address their current
help page lists). The goal is a written answer on whether a publicly
distributed third-party app may use the Hevy API with per-user keys.

---

**Subject:** Using the Hevy API in a third-party iOS app — permission question

Hello,

I've built an iOS and watchOS app called Ritmo that brings Apple Health,
workout and recovery data together, and I'm preparing to submit it to the App
Store. It offers an optional Hevy integration and I'd like to check that my
usage is acceptable to you before releasing it.

How the integration works:

- Each user supplies their **own** Hevy API key, generated from their own Hevy
  account settings. The app ships no key of its own.
- The key is stored on the user's device and is used only to read that user's
  own workouts.
- Requests go directly from the user's device to api.hevyapp.com. I operate no
  server and never receive any Hevy data.
- Imported workouts are shown only to the user who imported them. Nothing is
  shared, republished, or aggregated.
- The app reads workouts and routines; it does not write to Hevy.

My questions:

1. Is this use of the API permitted for an app distributed publicly on the App
   Store?
2. Are there attribution requirements, or naming and branding rules I should
   follow when referring to Hevy in the app?
3. Are there rate limits I should design around, given each user authenticates
   with their own key?
4. Is there anything else you'd want changed before I ship it?

Happy to adjust the integration or remove it if any of this isn't in line with
how you want the API used.

Thank you,
[name]
[contact]

---

## If they say no, or don't reply

The integration is self-contained: `HevyService` and the settings screen are
the whole surface. Removing it leaves Apple Health as the workout source, which
is already the canonical one — Hevy only enriches those records with sets, reps
and per-set RPE.

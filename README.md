# Lull

An iPhone app for tracking a baby's sleep and estimating when they are likely to
be ready for the next one.

The product answers one question well: *when will my baby probably be ready to
sleep again?* It answers it as a **time range**, based on age-appropriate ranges
at first and on the baby's own pattern once there is enough history.

## Guiding principle

> Use age as a prior, but learn the individual baby's actual sleep pattern over time.

Wake-window charts are practical heuristics, not clinically validated rules,
while total-sleep recommendations and developmental trends rest on firmer
ground. So the app shows ranges, never a prescribed minute, and never tells a
parent what their baby *should* do.

## Layout

```
Lull.xcodeproj          iPhone app target (iOS 17+), sources synchronised from Lull/
Lull/                   SwiftUI app: screens, view model, theme
LullCore/               Swift package: all domain logic, no UI, no Apple UI frameworks
  Sources/LullCore/
    Model/              BabyProfile, SleepEvent, SleepDay, predictions, summaries
    Age/                Chronological and corrected age, derived on demand
    Priors/             Wake-window and total-sleep age priors with interpolation
    Classification/     Replaceable nap/night classifier
    Indexing/           Sleep-day calendar, nap indices, wake windows
    Analytics/          Daily summaries, rolling totals, derived baseline, trends
    Prediction/         History matching, next-sleep planning, prediction engine
    Store/              Dataset, repositories, SleepService facade
    Formatting/         Duration/time formatting and all parent-facing copy
  Sources/LullCoreVerify/  Runnable assertion suite for the domain logic
```

### Data architecture

```
Baby
 ├── BabyProfile          persisted
 ├── SleepEvents          persisted — the source of truth
 ├── DayFlags             persisted — "this day was unusual"
 ├── Predictions          persisted audit log, kept apart from observations
 ├── DailySleepSummaries  derived, never stored
 └── BabySleepProfile     derived, never stored
```

Summaries and the derived baseline are recomputed from events on demand, so the
analytics can be improved without a migration. Predictions are recorded only as
an audit trail (`generatedAt`, `basedOnSleepEventId`, `predictionVersion`, the
range, confidence, sample size) so the engine can change without corrupting
history.

## Running it

**App:** open `Lull.xcodeproj` in Xcode 16 or later and run on an iPhone
simulator. The app target links the local `LullCore` package; there are no
external dependencies.

**On a physical iPhone:** the target is iPhone-only (`TARGETED_DEVICE_FAMILY = 1`),
signs automatically against the free personal team in `DEVELOPMENT_TEAM`, and
uses the bundle identifier `com.williambjork.Lull` — free personal teams register
bundle identifiers globally, so a generic one such as `com.lull.Lull` is refused
as "not available". Anyone else building this needs to change both settings to
their own.

Two things must be true on the phone before it appears in Xcode's destination
menu; miss either and Xcode falls back to the build-only *Any iOS Device*
placeholder and refuses to run with "A build only device cannot be used to run
this target".

1. The phone is unlocked and has answered *Trust This Computer* for this Mac.
   `xcrun devicectl list devices` must show it as `available (paired)`, not as a
   bare ECID row. A bare ECID row means the pairing never completed.
2. *Settings → Privacy & Security → Developer Mode* is on. The toggle only
   appears after the phone has been plugged into a Mac running Xcode, and
   turning it on reboots the phone.

Then, on the first install only, iOS refuses to launch the app until its
developer certificate is trusted. The install itself succeeds and the launch
fails with "its profile has not been explicitly trusted by the user".

Trusting it is *Settings → General → VPN & Device Management → Apple
Development: <your Apple ID> → Trust*, but that row does not exist on a phone
that has never been asked to run an untrusted developer's app. Installing the
app is not enough to make it appear — try to open the app once, from the home
screen or via Xcode's Run, and let the launch be refused. That refusal is what
puts the developer into the list, after which the Settings row is there.

A free personal team expires the provisioning profile after seven days, so
re-signing and this trust step both recur. `xcrun devicectl device profile list
--device <udid>` shows what is currently on the phone and when it expires.

**Domain logic:** the toolchain on this machine (Command Line Tools only) ships
neither XCTest nor Swift Testing, so the domain logic is verified by a runnable
assertion harness instead of a test target:

```
cd LullCore && swift run LullCoreVerify
```

It currently runs 162 assertions covering age maths, priors, classification, nap
indexing, wake windows, totals, the derived baseline, every prediction weighting
tier, trend detection, the service flow and the copy. Port it to a test target
(the assertions translate one-to-one) once a full Xcode install is available.

## How the estimate works

1. **Wake start** — the current wake period begins when the last completed sleep
   ended. With nothing tracked yet, the parent can supply the morning wake time.
2. **Which sleep is next** — nap 1, nap 2, … or bedtime, derived from how many
   naps this baby has actually had today and how many they usually have. No fixed
   nap count is imposed. Evaluated twice, because a late target time can itself
   turn "another nap" into "bedtime".
3. **Age prior** — interpolated between published bands, so a 4.5-month-old lands
   between the 3–4 and 5–7 month ranges instead of snapping to one of them. Past
   12 months the prior is marked extrapolated, its influence decays, and the app
   shifts emphasis to nap structure and total sleep.
4. **Personal history** — wake windows from the same transition (same sleep type,
   same or neighbouring nap index), last 14 days, completed sleeps only, days
   marked unusual excluded. The **median** is used, so one chaotic day cannot
   drag the estimate.
5. **Blend** — 0–4 comparable observations: age prior only. 5–9: 70% personal.
   10+: 80% personal. All weights live in `PredictionConfig`.
6. **Range** — the target time ±15 minutes, with a confidence level derived from
   sample size, how consistent this baby actually is, and how closely the matched
   history fits.

### What it deliberately does not do

- No hard-coded rules like "30-minute nap ⇒ subtract 20 minutes". Short naps are
  recorded, and `WakeWindowAdjusting` is the seam for learning such a
  relationship from a baby's own data later.
- No automatic adjustment from context tags (illness, teething, travel). Tags
  explain anomalies and filter history; they never quietly change arithmetic.
- No declaring a dropped nap. When the signals line up — fewer naps, longer wake
  windows, stable total sleep, one nap repeatedly refused — the app says the
  pattern *may be moving* toward fewer naps, and shows its evidence.
- No machine learning. A deterministic, explainable algorithm over clean raw data
  is far more useful than a model trained on five naps.
- No stored age and no editable duration. Both are always computed
  (`durationMinutes` is a computed property, so there is no field to disagree
  with the timestamps).

## Extension points

| Want to change | Replace |
| --- | --- |
| The prediction algorithm | `SleepPredicting` (`HeuristicSleepPredictionEngine`) |
| Nap/night classification | `SleepClassifying` (`HeuristicSleepClassifier`) |
| Weights, lookback, range width | `PredictionConfig` |
| Short-nap or cue-based adjustments | `WakeWindowAdjusting` |
| Storage | `SleepRepository` (`FileSleepRepository`, `InMemorySleepRepository`) |

Classification is stored on the event with its source, so a newer classifier
never rewrites history or overrules a parent's own choice.

## MVP status

Implemented: baby profile with optional corrected age · start/stop timer ·
persistent events · calculated durations · nap/night classification · nap
indexing · wake windows · age-based prediction · personal-history prediction ·
24-hour and daily totals · sleep history with editing · prediction confidence ·
marking unusual days · nap-transition hints · cue and context capture.

Groundwork, intentionally not finished: cue-timing personalisation needs a
timestamp per observed cue (see `CueAnalytics`); sleep latency is captured via
the optional `putDownAt` but is not a primary metric.

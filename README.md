# Exemplary Botanicals

An iPhone app that acts as a personal organic gardening coach, modeled on David. It remembers your garden, watches your local weather, and nudges you at the right moment.

It's a gift for a friend: no accounts, no ads, nothing to buy. Garden records stay on the phone.

## What it does

- **Today:** the forecast, a water estimate for each bed, and the nudges that matter right now across the whole garden (what's ready to harvest, a quick pest check, pruning, staking, sowing again for a steady supply, checking moisture, water stress, feeding heavy feeders when they need it, frost and heat warnings, and the end-of-season wrap-up). Nudges also arrive as notifications, at most two a day, outside quiet hours (9 PM to 7 AM by default).
- **Coach:** chat with David's coach persona. It sees your beds, plants, journal, supplies on hand and the weather, covers harvest timing, pests, pruning, sowing, watering and weather as well as feeding (feeding only when it's warranted), gives strictly organic advice in the order *what you have → free → low cost → products to buy (with prices)*, and keeps your records up to date as you talk. Replies can be read aloud in David's cloned voice (off by default).
- **Photo check:** take a photo of a struggling plant; the coach looks for water stress and nutrient deficiency or excess, says how sure it is, and suggests a soil test when it can't tell.
- **Garden:** a list of your beds and containers. Open one to see what's growing in it (type and how many), add a plant, and see the bed's record; supplies on hand and a budget sit below. 38 common crops are built in, each with harvest timing, what pests to watch for and pruning notes. Each bed and plant has a running record: its photos over time, before-and-after pairs around each feeding, spray, amendment or other treatment, and everything logged for it.
- **Journal:** everything done and noticed, with an optional photo on any entry. Nudges and the coach add to it, and the water and feeding estimates and the bed and plant records read from it.

Without a backend the app runs in **demo mode**: everything works except that coach answers and photo checks come from built-in rules.

## How it's built

| Folder | What | Runs on |
| --- | --- | --- |
| `ios/ExemplarBotanicals` | The SwiftUI app (iOS 17+, SwiftData) | iPhone |
| `ios/Packages/GardenCore` | Garden logic with no UI: weather, water balance, nudge rules and pacing, supplies ranking, before-and-after photo matching, the snapshot sent to the coach | iPhone, tested on Linux in CI |
| `backend` | A small Cloudflare Worker that holds the API keys: coach chat, photo diagnosis, nudge wording, voice | Cloudflare (free plan) |
| `backend/persona` | The Markdown files that make the coach sound and think like David | read into the backend at deploy |

Weather comes from Open-Meteo (free, no key). The coach uses the Claude API; the voice uses ElevenLabs.

## Getting started

- [docs/SETUP.md](docs/SETUP.md): run the app on an iPhone, deploy the backend, turn on the voice, and get it onto your friend's phone.
- [docs/WHAT-DAVID-PROVIDES.md](docs/WHAT-DAVID-PROVIDES.md): the photo, writing, voice recording and accounts only David can supply.

## Checks

GitHub Actions runs the backend type check and tests and the GardenCore tests on every push. The full iOS build is a manual job (Actions → CI → Run workflow) because macOS minutes cost ten times as much on a private repository.

Locally:

```sh
cd backend && npm ci && npm test
cd ios/Packages/GardenCore && swift test
```

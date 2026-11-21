# Setting up Exemplary Botanicals

There are four stages. Each one works on its own, so you can stop after any of them.

1. [Run the app on your iPhone in demo mode](#1-run-the-app-on-your-iphone-demo-mode) (about 20 minutes, free)
2. [Deploy the coach backend](#2-deploy-the-coach-backend) so the real coach answers (about 20 minutes)
3. [Turn on David's voice](#3-turn-on-davids-voice-optional) (optional)
4. [Put the app on your friend's iPhone](#4-put-the-app-on-your-friends-iphone)

The persona (how the coach talks and what it recommends) is edited separately and can be improved at any time without an app update: see [5. Edit the coach persona](#5-edit-the-coach-persona).

---

## 1. Run the app on your iPhone (demo mode)

You need a Mac with Xcode 16 or later and an iPhone on iOS 17 or later.

**Install XcodeGen.** The Xcode project is generated from `ios/project.yml`, so it never has merge conflicts. Either:

- with Homebrew: `brew install xcodegen`, or
- without Homebrew: download `xcodegen.zip` from the [XcodeGen releases page](https://github.com/yonaskolb/XcodeGen/releases), unzip it, and use the path to `xcodegen/bin/xcodegen` wherever this guide says `xcodegen`.

**Fill in your settings.**

```sh
cd ios
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
```

Open `ios/Config/Secrets.xcconfig` and set:

| Setting | What to put |
| --- | --- |
| `EB_DEVELOPMENT_TEAM` | Your Apple Team ID. In Xcode: Settings → Accounts → your Apple ID → the team's ID. A free Apple ID works for your own phone. |
| `EB_BUNDLE_ID` | Any reverse-DNS id that's yours, e.g. `com.davidbarker.exemplar`. |
| `EB_BACKEND_HOST` | Leave the example value for now. It means demo mode. |
| `EB_APP_SECRET` | Leave the example value for now. |

`Secrets.xcconfig` is in `.gitignore`, so it stays on your Mac.

**Generate the project and run it.**

```sh
cd ios
xcodegen generate
open ExemplarBotanicals.xcodeproj
```

Plug in your iPhone (or pick it from the device menu if it's on the same Wi-Fi), choose it as the run destination, and press Run (⌘R). The first time, iPhone asks you to trust the developer: Settings → General → VPN & Device Management.

Run `xcodegen generate` again whenever you pull changes that add or remove files.

In demo mode the whole app works: onboarding, beds and plants, weather, water estimates, nudges, journal. Coach answers and photo checks come from built-in rules and say so.

> With a free Apple ID, apps you install expire after 7 days and need to be run from Xcode again. A paid developer account (step 4) removes that limit.

---

## 2. Deploy the coach backend

The backend is a small Cloudflare Worker. It keeps the Claude and ElevenLabs keys off the phone. The free Workers plan is enough.

You need: Node.js 20 or later, a [Cloudflare account](https://dash.cloudflare.com/sign-up), and a [Claude API key](https://console.anthropic.com/).

> **Set a spend limit first.** In the Claude Console, under Billing / Limits, set a monthly limit you're comfortable with. The app's shared secret (below) keeps casual strangers out, but anyone determined can pull it out of the app, so the spend limit is the real safety net.

```sh
cd backend
npm ci
npx wrangler login          # opens a browser to sign in to Cloudflare
npm run deploy              # builds the persona and deploys; prints your URL
```

The deploy prints a URL like `https://exemplar-botanicals.<your-subdomain>.workers.dev`. Now add the secrets (each command asks you to paste the value):

```sh
npx wrangler secret put ANTHROPIC_API_KEY
openssl rand -hex 32        # makes a long random string; copy it
npx wrangler secret put APP_SHARED_SECRET
```

Secrets take effect right away; no redeploy needed.

**Check it.** Replace the host and secret with yours:

```sh
curl -H "Authorization: Bearer YOUR_SHARED_SECRET" https://exemplar-botanicals.YOUR-SUBDOMAIN.workers.dev/v1/health
```

You should see `"ok":true` and `"claudeConfigured":true`, plus the status of each persona file.

**Point the app at it.** In `ios/Config/Secrets.xcconfig`:

```
EB_BACKEND_HOST = exemplar-botanicals.your-real-subdomain.workers.dev
EB_APP_SECRET = the-same-string-you-gave-APP_SHARED_SECRET
```

Host name only, no `https://` (in an xcconfig file `//` starts a comment). Run the app again. Settings → Coach should say "Connected", and the demo-mode banner on the Coach tab disappears.

**Settings you can change** in `backend/wrangler.toml` under `[vars]` (then `npm run deploy`):

| Variable | What it does |
| --- | --- |
| `CLAUDE_MODEL` | Which Claude model answers. |
| `CHAT_EFFORT` | How hard the coach thinks in chat (`low`, `medium`, `high`). `medium` is a good balance of speed and quality. |
| `DIAGNOSE_EFFORT` | Effort for photo checks. `high` by default since a wrong diagnosis costs more than a slow one. |
| `NUDGE_EFFORT` | Effort for rewording nudges in the coach's voice. `low` is plenty. |

The backend opts in to Claude's server-side refusal fallback, so if a safety check ever declines an ordinary garden question, it's retried on a fallback model instead of failing.

**Running it locally** (optional): put the secrets in `backend/.dev.vars` (one `NAME=value` per line; git ignores it) and run `npm run dev`. Point `EB_BACKEND_HOST` at your Mac's address only for testing; the app expects HTTPS.

---

## 3. Turn on David's voice (optional)

When this is set up, each coach reply gets a "Hear David" button, and Settings gets a switch to read replies aloud automatically. Both are off until the gardener turns them on.

1. Create an [ElevenLabs](https://elevenlabs.io/) account. Voice cloning needs a paid plan.
2. Clone David's voice (Voices → Add a new voice). A Professional Voice Clone sounds far closer than an Instant one; see [WHAT-DAVID-PROVIDES.md](WHAT-DAVID-PROVIDES.md#3-a-voice-recording-optional) for the recording.
3. Copy the new voice's **Voice ID** and create an **API key** (Profile → API keys).
4. Add both to the backend:

   ```sh
   cd backend
   npx wrangler secret put ELEVENLABS_API_KEY
   npx wrangler secret put ELEVENLABS_VOICE_ID
   ```

No app change is needed. The app checks the backend when it opens and shows the voice options once both are set. Each reply's audio is cached on the phone, so replaying is free.

---

## 4. Put the app on your friend's iPhone

This needs the [Apple Developer Program](https://developer.apple.com/programs/) ($99 a year). Put that account's Team ID in `EB_DEVELOPMENT_TEAM`.

**TestFlight** is the easiest route for one person:

1. In [App Store Connect](https://appstoreconnect.apple.com/), create a new app with your bundle id (Apps → + → New App).
2. In Xcode, choose "Any iOS Device" as the destination, then Product → Archive. When it finishes, click Distribute App and follow the TestFlight prompts.
3. In App Store Connect → TestFlight, add your friend as an external tester by email. The first build goes through a short Beta App Review (usually a day).
4. Your friend installs the TestFlight app and accepts the invite.

TestFlight builds expire after 90 days. To keep it going, bump `CURRENT_PROJECT_VERSION` in `ios/project.yml`, regenerate, and upload a new build; the friend's garden data carries over.

For something permanent, you can submit the app to the App Store as an **unlisted** app (only people with the link can find it). That needs full App Review and a short privacy policy; the Privacy section in Settings → About the coach is a good starting point.

---

## 5. Edit the coach persona

The coach's personality and knowledge come from the Markdown files in `backend/persona/`. See [backend/persona/README.md](../backend/persona/README.md) for what goes in each file. After editing:

```sh
cd backend
npm run deploy
```

The app picks up the change on the next message; no app update needed. Settings → About the coach lists any files still marked placeholder or starter.

## Replacing the coach photo

Replace `ios/ExemplarBotanicals/Resources/Assets.xcassets/CoachAvatar.imageset/CoachAvatar.png` with a square photo of David (at least 512 × 512 pixels; 1024 is ideal), keeping the file name. The app crops it to a circle. Rebuild the app.

## Changing the background photo

The photo behind the main screens is `ios/ExemplarBotanicals/Resources/Assets.xcassets/GardenBackground.imageset/GardenBackground.jpg`. Replace it with any photo (a JPEG about 1200 pixels on the long side keeps the app small), keeping the file name, and rebuild. The app softens and lightens it automatically so text stays readable; `GardenBackdrop` in `Views/Shared/Components.swift` sets how much (`blur` radius and overlay opacity).

## Troubleshooting

| What you see | What to check |
| --- | --- |
| Coach tab says demo mode | `EB_BACKEND_HOST` and `EB_APP_SECRET` are still example values, or empty. The app treats a host containing `your-` or a secret starting with `paste-` as not set. |
| Settings → Coach: "Server is up but missing its Claude key" | Run `npx wrangler secret put ANTHROPIC_API_KEY`. |
| Coach says "The app's key for the coach doesn't match the server" | `EB_APP_SECRET` doesn't match `APP_SHARED_SECRET`. Set the secret again on the backend or fix the xcconfig, then rebuild. |
| No notifications | Settings → Nudges is off, or iPhone Settings → Notifications → Exemplary Botanicals is off. Weather-based nudges (watering, frost, heat, spray timing) also need a location in Settings → Location. |
| "Hear David" button never appears | Both ElevenLabs secrets must be set. Check `/v1/health` shows `"voiceAvailable":true`. |
| Build error about signing | `EB_DEVELOPMENT_TEAM` is empty or wrong, or the bundle id is taken. Use one that's unique to you. |

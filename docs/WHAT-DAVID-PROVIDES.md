# What David needs to provide

The app is built and runs without any of this, in demo mode with a placeholder coach. These are the pieces only David can supply. They're listed in the order that makes the biggest difference.

## 1. Writing for the coach persona (most important)

The coach can only sound like David if it has David's words. Edit the files in [`backend/persona/`](../backend/persona/README.md), then run `npm run deploy` in `backend/`. No app update is needed, so this can keep improving after your friend has the app.

| File | Status now | What it needs |
| --- | --- | --- |
| `sample-answers.md` | placeholder | **The single most useful file.** 30 to 50 real questions a friend might ask, each answered the way David would answer by text or out loud. Voice memos transcribed word for word are perfect. Include a few where the answer is "I don't know, here's how we'd find out" and a few where a chemical product comes up. |
| `voice.md` | placeholder | How David talks about gardening: tone, typical length, phrases he uses, humor, how he says "you're overthinking it" or "that plant is done." |
| `about.md` | placeholder | Where he gardens (zone, soil, climate), for how long, what he grows, what he's known for. A paragraph or two. |
| `opinions.md` | starter (Claude wrote a reasonable organic starting point) | Read it and change anything David disagrees with. Add pet peeves, things he'd never recommend, beginner mistakes he sees most. |
| `products.md` | starter | His go-to products and brands, each with his own pros, cons and a rough price. Replace or edit the starter list. |

Delete the `<!-- STATUS: ... -->` line at the top of a file when it's done. Settings → About the coach in the app shows which files are still placeholders.

## 2. A photo of David

A square, well-lit headshot, at least 512 × 512 pixels (1024 × 1024 is ideal). The app shows it in a circle, so keep the face centered with a little room around it. It replaces `ios/ExemplarBotanicals/Resources/Assets.xcassets/CoachAvatar.imageset/CoachAvatar.png` (keep the file name), and the app is rebuilt.

## 3. A voice recording (optional)

Only needed for the read-aloud option, which the gardener has to turn on.

- **For an ElevenLabs Professional Voice Clone** (sounds most like David): at least 30 minutes of David speaking naturally, ideally an hour or more. One person, a quiet room, a decent microphone or a recent iPhone held at a steady distance, no music or background voices. Talking through garden tasks or reading his own sample answers aloud works well, because the clone picks up the rhythm of how he explains things.
- **For an Instant Voice Clone** (quicker, less faithful): one to two minutes of the same kind of audio.
- ElevenLabs asks the person whose voice is cloned to confirm it by reading a short prompt, so David needs to do that step himself from his own account (or be present for it).

## 4. Accounts and keys

| What | Why | Cost | Who sets it up |
| --- | --- | --- | --- |
| **Claude API key** ([console.anthropic.com](https://console.anthropic.com/)) | Powers chat, photo checks and nudge wording | Pay per use; set a monthly spend limit in the Console | David |
| **Cloudflare account** ([dash.cloudflare.com](https://dash.cloudflare.com/sign-up)) | Hosts the backend | Free plan is enough | David |
| **Shared app secret** | Keeps strangers from using the backend | Free: run `openssl rand -hex 32` | Made during setup |
| **Apple Developer Program** ([developer.apple.com](https://developer.apple.com/programs/)) | Needed to put the app on your friend's phone (TestFlight) | $99 a year | David |
| **Apple Team ID and a bundle id** | So Xcode can sign the app | Free with the above | From the developer account |
| **ElevenLabs account, API key and Voice ID** ([elevenlabs.io](https://elevenlabs.io/)) | The cloned voice | Paid plan needed for cloning | David (optional) |

Where each one goes is in [SETUP.md](SETUP.md).

## 5. Things worth a quick look

- **Defaults chosen for v1:** at most 2 nudges a day, quiet from 9 PM to 7 AM, routine nudges at 7:30 AM, foliar spray every 14 days. Photo checks show how confident they are and suggest a soil test when unsure. The coach politely holds the organic line if asked about synthetic products. All of these can be changed in the app's Settings except the organic line, which lives in the persona and backend instructions.
- **App name on the home screen:** "Exemplar". Change `CFBundleDisplayName` in `ios/ExemplarBotanicals/Info.plist` if you'd like something else.
- **App icon:** a simple green leaf placeholder in `ios/ExemplarBotanicals/Resources/Assets.xcassets/AppIcon.appiconset/`. Swap in a 1024 × 1024 PNG with no transparency if you want your own.
- **Coach name:** "David", set by `EB_COACH_NAME` in `ios/Config/App.xcconfig`.

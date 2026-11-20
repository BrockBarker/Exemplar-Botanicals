# The coach persona (David)

Everything in this folder (except this README) is read into the coach's instructions
when the backend is built. Edit these files to make the coach sound and think like David.

| File | What goes in it | Status line to delete when done |
| --- | --- | --- |
| `about.md` | Who David is: where he gardens, for how long, what he grows, what he's known for | `<!-- STATUS: placeholder -->` |
| `voice.md` | How David talks to a friend about gardening: tone, phrases, length, humor | `<!-- STATUS: placeholder -->` |
| `opinions.md` | Strong opinions, pet peeves, what he never recommends, common beginner mistakes | `<!-- STATUS: starter -->` |
| `products.md` | His go-to products, each with his own pros, cons and price notes | `<!-- STATUS: starter -->` |
| `sample-answers.md` | 30 to 50 real questions with answers written (or transcribed) the way he'd answer a friend | `<!-- STATUS: placeholder -->` |

How the files are used:

- HTML comments (`<!-- like this -->`) are instructions for David. They are stripped out and never reach the coach.
- `placeholder` means the file has no real content yet; the coach falls back to neutral defaults.
- `starter` means Claude wrote a reasonable organic starting point. David should edit it, then delete the status line.
- The app's Settings screen shows which files are still placeholders or starters.

After editing, redeploy the backend (`npm run deploy` in `backend/`). No app update is needed.

Keep the whole folder under roughly 40,000 words. Longer is fine for quality but makes every coach reply slower
and a little more expensive on the first message of a session.

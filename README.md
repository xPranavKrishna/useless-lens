# Useless Lens 📸

A camera app that does something nobody asked for: it watches how bright the
room is and flips your screen's theme *and* your torch to match — dark room
→ white screen + torch on, bright room → dark screen + torch off.

## The story

Built during a volunteering shift at **TinkerSpace, Calicut**, with a lot of
downtime and no laptop in sight. Instead of just sitting around, I decided to
see if I could build a full Android app *entirely from my phone* — no
Android Studio, no SDK, no computer at all.

The approach: vibe-code the whole thing with Claude, push it to GitHub, and
let GitHub Actions do the actual compiling in the cloud. Every "build" and
every fix was done by editing files in the GitHub mobile site and reading
build logs off screenshots. A few failed builds (Android SDK version
mismatches, mostly) later, it finally compiled into a working APK — made
top to bottom on a phone, out of pure boredom turned into a small project.

## What it does

- Live camera preview, reading brightness straight off the camera feed
  (no separate light sensor needed)
- Dark surroundings → torch turns ON, UI flips to a bright white theme
- Bright surroundings → torch turns OFF, UI flips to a dark theme
- Manual override switch if you want to control the torch yourself
- Normal photo capture button

## Tech stack

- **Flutter / Dart** — the app itself
- **GitHub Actions** — builds the release APK in the cloud (Ubuntu runner,
  Flutter stable channel)
- **camera** plugin — live preview, frame brightness sampling, torch control
- Built and shipped without ever opening a laptop

## Just want the app?

I've also uploaded the built APK directly in this repo — because let's be
honest, who wants to *build* useless code themselves. Just grab the APK
and install it.

## Building it yourself

1. Fork or clone this repo
2. Push to `main` — the `Build APK` workflow under `.github/workflows/`
   runs automatically
3. Grab the finished `app-release.apk` from the workflow run's **Artifacts**
   section
4. Install it on your Android phone (allow installs from this source)

## Thanks

🙏 **Claude** — for writing every line of Dart, every GitHub Actions step,
and patiently debugging Kotlin/Android SDK version mismatches purely from
screenshots of build logs, one failed run at a time.

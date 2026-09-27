# Contributing

> **This fork.** Everything below is upstream's and still applies. On top of
> it, a change to this fork is expected to follow these rules — a pull request
> that doesn't is reworked or declined:
>
> 1. **Fork code lives in `Sources/Search/Fork/`.** New logic goes in a file
>    there, one file per feature. An upstream file only gets the smallest hook
>    that calls into it, marked with a `// Fork:` comment that names the file.
>    Logic written straight into `Browser.swift`, `Side.swift` and the like is
>    what makes every upstream sync a conflict.
> 2. **New behaviour is optional.** Anything that changes how the browser
>    looks or behaves comes with a switch in Settings, and is off by default
>    unless it has been agreed otherwise. Fixes don't need one.
> 3. **One feature per commit, and every commit builds.** A feature, its
>    fixes and its follow-ups are one commit (fold fix-ups in with
>    `git rebase -i --autosquash`); two features are two commits. Each commit
>    passes `swift build` on its own, so any one can be dropped or rebased
>    onto upstream.
> 4. **Messages say what changed, in plain words.** A subject line of what
>    the browser now does ("Clear, above New Tab, closes the loose tabs"),
>    then a body with the fork files and the hooks.
> 5. **`FORK.md` gets a row** for each feature: its fork files, its hooks in
>    upstream files, and any open upstream pull request it overlaps.
> 6. **Upstream's files stay upstream's.** Don't edit `CHANGELOG.md` or
>    `ROADMAP.md`; the fork's notes go in `FORK.md`.
> 7. **Nothing leaves the Mac, nothing weakens what's kept.** No new network
>    calls, and passwords, cookies and anything imported stay in the keychain
>    or WebKit's own stores, as the rest of the app does.
>
> Open pull requests against this fork's `main`. See [FORK.md](FORK.md) for
> how it's kept on upstream.

This is a small, mostly-solo project, reviewed the same way it's written. Contributions are welcome, but a few things make one land faster.

## Before writing code

For anything beyond a small fix, open an issue first describing what you want to change and why. It saves a rewritten pull request later if the direction doesn't fit.

## New features: off until someone turns them on

Search stays small by default. Anything new that changes how the browser
looks or behaves — spaces, groups, a visible address bar, a new panel — is:

- **minimal**: the smallest version that does the job, in the app's own quiet style;
- **optional, and off by default**: someone who never asks for it never sees it;
- **findable**: a switch in Settings, and a mention in the welcome screens if it's a big one, so people know it's there to turn on.

Fixes and things every browser is expected to do (Tab moving between a form's fields, ⌘1–⌘9) don't need a switch. Before building a bigger feature, look at how other browsers do it and read what people asked for on its issue; [ROADMAP.md](ROADMAP.md) lists where each request came from.

## Where things are tracked

- [ROADMAP.md](ROADMAP.md), live at [officecommun.com/search/roadmap](https://officecommun.com/search/roadmap): every idea and report, from issues, pull requests, emails and X, with where it stands — being built, in the next version, next, or not planned. Maintainers keep it with `./ideas`.
- [CHANGELOG.md](CHANGELOG.md): what has changed since the last version. A pull request that fixes or adds something also adds its line under **Unreleased** (and takes its item off the roadmap), so the next update's notes write themselves.

## What tends to get merged

- **Small, focused changes.** One thing per pull request, easy to read start to finish.
- **No new dependencies.** The whole point of this app is staying small; a browser this size doesn't need a package for something Foundation or WebKit already does.
- **Matches the existing style.** Comments here explain *why*, not *what the next line does* — read a couple of existing files before adding a new one. No force-unwraps on anything that can plausibly fail (a network response, a file read, a keychain lookup).
- **Builds clean.** `swift build` with zero warnings you introduced.

## What doesn't

- Rewrites of things that already work, for style reasons alone.
- Anything that phones home, adds analytics, or changes what leaves the app over the network — see the [privacy page](https://officecommun.com/search/privacy) for what that boundary currently is.
- Vendoring Chromium or any other engine. This is a WebKit browser on purpose.

## Review

Pull requests are reviewed by Drice, usually with Claude Code doing a first pass on the diff before a human look. That means a review can be fast even when nobody's watching the repo in real time, but it isn't a guarantee of a same-day answer — this isn't anyone's full-time job. Pinging a stale PR after a couple of weeks is completely fine.

## Reporting a bug

Open an issue with: what you did, what you expected, what happened instead, and your macOS version. A crash log, if there is one, lives at `~/Library/Application Support/Search/crash.log` — it only ever stays on your Mac unless you paste it into the issue yourself.

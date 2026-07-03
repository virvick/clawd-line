# Contributing to clawd-line

Thanks for considering a contribution — this is a small, solo-maintained
project, so keeping things simple matters more than covering every edge
case.

## Before you start

- For anything more than a small fix, open an issue first to check the
  approach before writing code — saves you a rewrite if the direction
  isn't a fit.
- Security issues go through [SECURITY.md](SECURITY.md), not a public
  issue/PR.

## Workflow

1. Fork the repo, branch off `main`.
2. Make your change.
3. Open a PR against `main`. `main` is protected — PRs need at least one
   approval before merging, so expect a review pass.

## Keeping bash and PowerShell in sync

`clawd-line.sh` (macOS/Linux) and `clawd-line.ps1` (Windows) are two
independent implementations of the *same* statusline: same layout, same
gradient math, same mascot bit-patterns and animation states. If your
change touches rendering logic, cost/context/rate-limit parsing, or the
mascot, please port it to **both** files, not just one — a change that
only lands in one leaves the other silently out of sync. If you can only
test on one platform, say so in the PR and it's fine to leave the other
port as a follow-up, just flag it.

## Testing your change

There's no test suite (a statusline's output is inherently visual), so
before opening a PR:

- **bash**: `bash -n clawd-line.sh` (syntax), then pipe a sample JSON
  payload through it and eyeball the output — see the comments at the top
  of `clawd-line.sh` for the expected input shape.
- **PowerShell**: `pwsh -File clawd-line.ps1` the same way. If you don't
  have Windows, `pwsh` runs fine on macOS/Linux for testing purposes
  (`brew install powershell`).
- **install.sh / install.ps1**: these merge into `~/.claude/settings.json`
  — if you change them, test against both an existing settings.json (with
  unrelated keys already in it) and a missing one, and confirm nothing
  outside the `statusLine` key gets touched.

## Style

- Match the existing formatting/naming rather than introducing a new
  convention.
- Comments explain *why*, not *what* — see the existing comments for the
  tone (e.g. why a particular escape sequence is used, why a value is
  clamped).
- No new runtime dependencies without discussion first — part of the
  point of this project is that it needs nothing beyond what's already
  documented in the README's Requirements section.

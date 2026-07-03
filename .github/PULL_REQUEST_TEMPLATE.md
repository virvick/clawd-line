## What changed

<!-- What does this PR do, and why? -->

## Tested on

- [ ] macOS
- [ ] Linux
- [ ] Windows (PowerShell)

## Checklist

- [ ] If this touches rendering/parsing/mascot logic, I updated **both**
      `clawd-line.sh` and `clawd-line.ps1` (or explained why only one)
- [ ] If this touches `install.sh`/`install.ps1`, I tested against both an
      existing `settings.json` (with unrelated keys) and a missing one
- [ ] `bash -n clawd-line.sh` / `install.sh` passes (if changed)
- [ ] `pwsh -File clawd-line.ps1` / `install.ps1` runs without errors (if changed)

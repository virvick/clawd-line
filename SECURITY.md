# Security Policy

clawd-line is distributed as a script you pipe straight into your shell
(`curl | bash`, `irm | iex`). If you find anything that could let a
malicious actor tamper with that install path, execute unexpected code, or
exfiltrate data via the statusline, please report it privately rather than
opening a public issue.

## Reporting a Vulnerability

Please use [GitHub's private vulnerability reporting](https://github.com/virvick/clawd-line/security/advisories/new)
for this repo (Security tab → "Report a vulnerability"). This opens a
private conversation with the maintainer instead of a public issue, so the
report isn't visible until a fix is out.

Please include:
- What you found and why it's a security concern
- Steps to reproduce, if applicable
- Affected file(s) (`clawd-line.sh`, `clawd-line.ps1`, `install.sh`, `install.ps1`)

## Scope

In scope:
- `install.sh` / `install.ps1` (anything that could let a PR smuggle code
  into what gets piped into a user's shell)
- `clawd-line.sh` / `clawd-line.ps1` (the statusline scripts themselves)
- The `.claude-plugin/` marketplace/plugin manifests

Not in scope:
- Issues in Claude Code itself (report those to Anthropic)
- Issues in third-party dependencies (`jq`, `python3`, PowerShell) - report
  upstream

## Response

This is a solo-maintained hobby project, not a funded security effort -
there's no SLA, but reports will be looked at as soon as possible and
credited in the fix unless you'd prefer otherwise.

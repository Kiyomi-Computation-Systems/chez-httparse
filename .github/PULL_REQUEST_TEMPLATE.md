## What

<!-- One or two sentences: what changes, and why. Link the issue if there is one. -->

## Tested on

<!-- CI runs Linux x86-64 only. Say where else you ran `make test`: macOS, Windows, arm64. -->

## Checklist

- [ ] `make test` passes locally
- [ ] A behavior change comes with a test I watched fail without it
- [ ] Expected numbers come from llhttp, not from a run of this parser
- [ ] The title is a Conventional Commit (`feat:`, `fix:`, `docs:`, …)
- [ ] A grammar change is regenerated and committed (`make parser-refresh`)
- [ ] `README.org` and `docs/` match, if what users see changed (`make check-site`)
- [ ] `CHANGELOG.md` has an entry under `[Unreleased]`, if users can see the change
- [ ] NOTICE names any new third-party code or test data
- [ ] A moved pin is on a commit of its own, with `Akku.manifest` and `Akku.lock`

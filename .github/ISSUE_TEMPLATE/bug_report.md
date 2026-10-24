---
name: Bug report
about: Something broke or parsed unexpectedly
labels: bug
---

<!-- A suspected vulnerability? Don't file it here: SECURITY.md says how to
report it privately. -->

**Environment**

- OS and architecture (e.g. macOS 15 arm64, Ubuntu 24.04 x86_64):
- Chez Scheme version (`chez --version`):
- chez-httparse version or commit:

**What happened**

**What you expected**

What does llhttp do with the same bytes, if you know?

**How to reproduce it**

Ideally the bytes you fed, how you split them across `parser-feed!` calls,
and the mode you made the parser with (request or response, lenient flags).

**Does `make test` pass on your machine?**

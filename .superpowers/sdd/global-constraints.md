## Global Constraints

- Toolchain floors: CMake 3.26 declared (preset schema v6 + margin; 4.3.3 is
  what has actually run here), Chez Scheme 10.4.1 (the version this repo's CI
  Linux cell builds from source and the local dev machine runs; discovery
  rejects Petite and anything older).
- Exit-status vocabulary for Scheme lanes: 0 pass, 1 assertion failure(s),
  2 harness/configuration/registration error (includes empty selection and
  launcher refusals), 3 provenance failure. `HTTPARSE_EXIT_STATUS_VOCABULARY`
  is the single source of what an exact-exit registration may assert.
- Launcher diagnostics: refusals exit 2 with prefix `httparse-launcher:`
  (`httparse-fingerprint:` for the manifest launcher); harness output lines
  carry `httparse-harness:`.
- Measured baseline (2026-08-28, Darwin 25.5.0 arm64, Chez 10.4.1 threaded
  tarm64osx, CMake 4.3.3): release preset 35/35; no-scheme preset 9/9;
  CMake mutation suite 1 pass / 73 mutations, all caught or declared;
  Scheme mutation suite 28 passes / 59 mutations, all caught or declared;
  fingerprint sample `1f2902297117b4a3`. Every count that enters a record
  is re-measured on this tree at the time of writing, dated and
  platform-stamped; do not carry these numbers forward by arithmetic.
- Mutation-signature rule: EXPECT_STATUS/EXPECT_OUTPUT_MATCHES only where the
  status/output was measured; EXPECT_SURVIVES only with a written reason the
  suite re-prints; an uncaught mutation strengthens a test, never loosens it.
- Empty selection is failure at every layer: test presets keep
  `noTestsAction: error`, the Makefile keeps `--no-tests=error`, the mutation
  engine refuses an empty suite or stage, the Scheme harness exits 2 on an
  empty selection.
- Conventional Commits. Run the suite before every commit.
- No new dependencies. The byte-machine generator arrives only as the pinned
  submodule decision 0002 describes, and not in Slice 1.

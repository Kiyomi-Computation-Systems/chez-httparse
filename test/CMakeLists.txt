# chez-httparse test tree.
#
# Slice 1 registers the harness and build-layer surface only: the CMake-layer
# specifications (the build's own discovery and registration logic, which
# decides what every later lane can even see), the Scheme harness self lanes,
# the launcher refusals, provenance, and the two mutation suites. Parser lanes
# arrive with the first grammar slice.

# The registration helper decides which tests exist at all, so its functional
# core is specified before anything relies on it.
httparse_add_test(
  NAME httparse.harness.cmake-testing.cmake.direct
  COMMAND "${CMAKE_COMMAND}" -P
          "${CMAKE_CURRENT_LIST_DIR}/support/cmake/HttparseTestingSpec.cmake"
  TIMEOUT 120
  LABELS unit)

# Runtime discovery reads key=value probe output. Reading it wrong yields a
# plausible answer rather than an error, so the accessor is specified before
# either runtime module relies on it.
httparse_add_test(
  NAME httparse.harness.cmake-probe.cmake.direct
  COMMAND "${CMAKE_COMMAND}" -P
          "${CMAKE_CURRENT_LIST_DIR}/support/cmake/HttparseProbeSpec.cmake"
  TIMEOUT 120
  LABELS unit)

# Chez discovery must reject Petite, which cannot run the ahead-of-time lane,
# and must not mistake an unrelated `scheme` on PATH for Chez.
httparse_add_test(
  NAME httparse.harness.cmake-chez.cmake.direct
  COMMAND "${CMAKE_COMMAND}" -P
          "${CMAKE_CURRENT_LIST_DIR}/support/cmake/HttparseChezSpec.cmake"
  TIMEOUT 120
  LABELS unit)

# Every assertion in every specification above routes through SpecSupport, so a
# silent break there would leave all of them green while checking nothing. This
# is the only specification that may not use the helpers it tests.
httparse_add_test(
  NAME httparse.harness.cmake-spec-support.cmake.direct
  COMMAND "${CMAKE_COMMAND}" -P
          "${CMAKE_CURRENT_LIST_DIR}/support/cmake/SpecSupportSpec.cmake"
  TIMEOUT 120
  LABELS unit)

# httparse_mutation_verdict decides whether a mutation was caught, and for
# the declared reason -- the decision every specification in this tree is
# ultimately trusted through, including the mutation suite below, which
# mutates it. Specified here, immediately before that suite, for the same
# reason SpecSupportSpec precedes it: a mutation against machinery a proof
# depends on must not be judged by the very thing it just broke.
httparse_add_test(
  NAME httparse.harness.cmake-mutation-runner.cmake.direct
  COMMAND "${CMAKE_COMMAND}" -P
          "${CMAKE_CURRENT_LIST_DIR}/support/cmake/MutationRunnerSpec.cmake"
  TIMEOUT 120
  LABELS unit)

# A passing specification proves nothing by itself. This breaks each decision in
# each module in turn, on a staged copy, and requires the owning specification to
# notice. It runs under `ctest` because evidence that only exists in someone's
# terminal cannot fail when the code changes.
httparse_add_test(
  NAME httparse.harness.cmake-mutation.cmake.direct
  COMMAND "${CMAKE_COMMAND}" -P
          "${CMAKE_CURRENT_LIST_DIR}/support/cmake/MutationSuite.cmake"
  TIMEOUT 600
  LABELS unit)

# The exact-status assertion decides whether every expected-red test below is
# checking anything at all, so its functional core is specified before any of
# them relies on it.
httparse_add_test(
  NAME httparse.harness.cmake-expect-exit.cmake.direct
  COMMAND "${CMAKE_COMMAND}" -P
          "${CMAKE_CURRENT_LIST_DIR}/support/cmake/HttparseExpectExitSpec.cmake"
  TIMEOUT 120
  LABELS unit)

# A lane's command line decides whether a source lane is really a source lane.
# Specified before any lane is registered against it.
httparse_add_test(
  NAME httparse.harness.cmake-scheme-lane.cmake.direct
  COMMAND "${CMAKE_COMMAND}" -P
          "${CMAKE_CURRENT_LIST_DIR}/support/cmake/HttparseSchemeLaneSpec.cmake"
  TIMEOUT 120
  LABELS unit)

# This harness was ported from another repository under a mechanical rename
# (decision 0001); Slice 1's exit criteria require zero upstream-name
# references in the build/test tree (decision 0003). The audit is a
# registered check rather than a review rule so that the next file copied
# from upstream fails the build, not a review.
httparse_add_test(
  NAME httparse.harness.rename-audit.cmake.direct
  COMMAND "${CMAKE_COMMAND}" -P
          "${CMAKE_CURRENT_LIST_DIR}/support/cmake/RenameAuditSpec.cmake"
  TIMEOUT 120
  LABELS unit)

# The vendored llhttp corpus is upstream's bytes and is never edited
# (decision 0007 item 6). This lane is what makes that true rather than
# merely stated; it needs no Scheme runtime, so it also holds under the
# no-scheme preset.
httparse_add_test(
  NAME httparse.harness.corpus-provenance.cmake.direct
  COMMAND "${CMAKE_COMMAND}" -P
          "${CMAKE_CURRENT_LIST_DIR}/support/cmake/CorpusProvenanceSpec.cmake"
  TIMEOUT 120
  LABELS unit)

# --- Harness paths ---------------------------------------------------------

# The generator arrives as a submodule pinned by gitlink (decisions 0002, 0005).
# Both paths are spelled out once here and referred to by variable everywhere
# else, so the dependency's own name appears in this file twice rather than a
# dozen times -- the two shapes the rename audit declares legitimate (0011).
set(HTTPARSE_GENERATOR_CHEZ_LIBRARY_ROOT "${CMAKE_SOURCE_DIR}/vendor/byte-machine/src")
set(HTTPARSE_GENERATOR_COLLECTION "${CMAKE_SOURCE_DIR}/vendor/byte-machine/src/byte-machine")
set(HTTPARSE_GENERATOR_SOURCES
    "${HTTPARSE_GENERATOR_COLLECTION}/private/conditions.sls"
    "${HTTPARSE_GENERATOR_COLLECTION}/private/names.sls"
    "${HTTPARSE_GENERATOR_COLLECTION}/private/ir.sls"
    "${HTTPARSE_GENERATOR_COLLECTION}/private/normal-ir.sls"
    "${HTTPARSE_GENERATOR_COLLECTION}/runtime.sls"
    "${HTTPARSE_GENERATOR_COLLECTION}/graph.sls"
    "${HTTPARSE_GENERATOR_COLLECTION}/verify.sls"
    "${HTTPARSE_GENERATOR_COLLECTION}/interpret.sls"
    "${HTTPARSE_GENERATOR_COLLECTION}/compile.sls")
set(HTTPARSE_HARNESS_DIR "${CMAKE_CURRENT_LIST_DIR}/support/harness")
set(HTTPARSE_HARNESS_SELF_DIR "${HTTPARSE_HARNESS_DIR}/self")
set(HTTPARSE_HARNESS_CHEZ_LIBRARY_ROOT "${HTTPARSE_HARNESS_DIR}")
set(HTTPARSE_HARNESS_CHEZ_LAUNCHER
    "${CMAKE_CURRENT_LIST_DIR}/support/launchers/chez-source.ss")

# Per-runtime, per-machine object roots for the AOT lane. Keyed this way so a
# parallel build cannot race and an object built by one Chez is never loaded by
# another; nothing is written into the source tree.
set(HTTPARSE_CHEZ_OBJECT_ROOT
    "${CMAKE_BINARY_DIR}/chez-objects/${HTTPARSE_CHEZ_VERSION}/${HTTPARSE_CHEZ_MACHINE_TYPE}")
# The keying above is only as real as these two variables. Empty, every Chez
# version and every machine type would share one object root, a `.so` built by
# a different Chez could be loaded as though it were current, and every AOT
# lane would stay green while proving nothing about the runtime that actually
# ran it -- the exact defect this slice exists to prevent. No task in its plan
# re-derives HTTPARSE_CHEZ_VERSION or HTTPARSE_CHEZ_MACHINE_TYPE to
# catch a regression here, so this is the one place that can. Guarded on
# HTTPARSE_CHEZ_EXECUTABLE: on a host with no Chez neither variable is
# ever set, no AOT lane is registered, and an empty root is inert rather than
# a keying failure.
if(HTTPARSE_CHEZ_EXECUTABLE)
  if(NOT HTTPARSE_CHEZ_VERSION OR NOT HTTPARSE_CHEZ_MACHINE_TYPE)
    message(FATAL_ERROR
      "httparse: HTTPARSE_CHEZ_VERSION ('${HTTPARSE_CHEZ_VERSION}') "
      "and HTTPARSE_CHEZ_MACHINE_TYPE ('${HTTPARSE_CHEZ_MACHINE_TYPE}') "
      "must both be non-empty once a Chez has been discovered. They key "
      "HTTPARSE_CHEZ_OBJECT_ROOT so a compiled object can never outlive "
      "the runtime that produced it; empty, every AOT lane would share one "
      "root across every Chez version and machine type ever built here, and a "
      "stale object could load silently while every lane stayed green.")
  endif()
endif()
set(HTTPARSE_HARNESS_CHEZ_AOT_LAUNCHER
    "${CMAKE_CURRENT_LIST_DIR}/support/launchers/chez-aot.ss")
set(HTTPARSE_HARNESS_CHEZ_COMPILE_LAUNCHER
    "${CMAKE_CURRENT_LIST_DIR}/support/launchers/chez-compile.ss")

# The object guard is what makes the Chez source lane honest: Chez looks for a
# compiled library only in the object half of a library-directories pair, so
# pairing the source root with a directory that is always empty makes a stale
# .so unloadable. It lives in the build tree precisely because nothing may ever
# be written into it.
set(HTTPARSE_HARNESS_OBJECT_GUARD_DIR "${CMAKE_BINARY_DIR}/chez-object-guard")
file(MAKE_DIRECTORY "${HTTPARSE_HARNESS_OBJECT_GUARD_DIR}")

# --- Source tree paths -----------------------------------------------------
#
# Read by httparse_scheme_lane_command. src/ holds the product libraries;
# the harness above is test infrastructure. A lane imports from both, which is
# why the launcher takes repeatable roots. src/ is empty until the first
# parser slice lands; the lane machinery requires the directory to exist.
set(HTTPARSE_SRC_CHEZ_LIBRARY_ROOT "${CMAKE_SOURCE_DIR}/src")

# The sources every harness lane executes -- the two libraries; each lane
# appends its own program. Named once: a lane that listed them itself would
# drift, and a manifest that drifts is one that quietly stops describing the
# run.
set(HTTPARSE_HARNESS_MANIFEST
    "${HTTPARSE_HARNESS_CHEZ_LIBRARY_ROOT}/httparse/test/fingerprint.sls"
    "${HTTPARSE_HARNESS_CHEZ_LIBRARY_ROOT}/httparse/test/harness.sls")

# --- Build-time fingerprint expectations -----------------------------------

set(HTTPARSE_FINGERPRINT_LAUNCHER
    "${CMAKE_CURRENT_LIST_DIR}/support/launchers/fingerprint-manifest.ss")
set(HTTPARSE_FINGERPRINT_DIR "${CMAKE_BINARY_DIR}/fingerprints")

# httparse_expected_fingerprint(<name> <out_var> <source>...)
#
# Produce, at build time, the combined fingerprint the named lane must report,
# and set <out_var> to the file holding it.
#
# A build output rather than a configure-time value, because a registration's
# environment is fixed when CMake configures and this must be recomputed
# whenever a source changes -- which is precisely the case it exists to catch.
# The DEPENDS list is what makes that true, so a source added to a manifest
# without being added there produces an expectation that silently never
# refreshes.
#
# Keyed by a digest of the manifest, not by lane name: the value depends only on
# the manifest, and keying by name would spawn one Chez process per lane to
# produce a handful of distinct answers while hiding which lanes claim to run
# the same text.
function(httparse_expected_fingerprint name out_var)
  if(NOT ARGN)
    message(FATAL_ERROR
      "httparse: '${name}' asked for a fingerprint expectation over no "
      "sources. An empty manifest fingerprints to the seed on every lane, "
      "which would compare equal forever and check nothing.")
  endif()

  string(JOIN "|" manifest ${ARGN})
  string(SHA256 manifest_digest "${manifest}")
  string(SUBSTRING "${manifest_digest}" 0 16 manifest_key)
  set(expect_file "${HTTPARSE_FINGERPRINT_DIR}/${manifest_key}.fingerprint")

  # add_custom_command rejects a second rule for the same OUTPUT, so the first
  # lane to need a manifest creates the rule and the rest reuse it.
  get_property(known GLOBAL PROPERTY HTTPARSE_FINGERPRINT_MANIFESTS)
  if(NOT manifest_key IN_LIST known)
    set_property(GLOBAL APPEND PROPERTY HTTPARSE_FINGERPRINT_MANIFESTS
                 "${manifest_key}")

    add_custom_command(
      OUTPUT "${expect_file}"
      COMMAND "${CMAKE_COMMAND}" -E make_directory "${HTTPARSE_FINGERPRINT_DIR}"
      COMMAND "${HTTPARSE_CHEZ_EXECUTABLE}" --script
              "${HTTPARSE_FINGERPRINT_LAUNCHER}"
              "${HTTPARSE_HARNESS_CHEZ_LIBRARY_ROOT}"
              "${HTTPARSE_HARNESS_OBJECT_GUARD_DIR}"
              "${expect_file}"
              ${ARGN}
      DEPENDS ${ARGN}
              "${HTTPARSE_FINGERPRINT_LAUNCHER}"
              "${HTTPARSE_HARNESS_CHEZ_LIBRARY_ROOT}/httparse/test/fingerprint.sls"
      COMMENT "httparse: fingerprint manifest ${manifest_key} (first needed by ${name})"
      VERBATIM)

    add_custom_target("httparse_fingerprint_${manifest_key}"
                      DEPENDS "${expect_file}")
    if(NOT TARGET httparse_fingerprints)
      add_custom_target(httparse_fingerprints ALL)
    endif()
    add_dependencies(httparse_fingerprints
                     "httparse_fingerprint_${manifest_key}")
  endif()

  set(${out_var} "${expect_file}" PARENT_SCOPE)
endfunction()

# A deliberately wrong expectation, so the provenance check is proved to fire by
# a registered lane rather than by editing a build artifact during a mutation
# gate. It is not a fingerprint of anything and cannot become one: every real
# value is lowercase hex, so no manifest can ever produce this text.
function(httparse_wrong_fingerprint name out_var)
  set(expect_file "${HTTPARSE_FINGERPRINT_DIR}/${name}.wrong")
  file(MAKE_DIRECTORY "${HTTPARSE_FINGERPRINT_DIR}")
  file(WRITE "${expect_file}" "not-a-fingerprint")
  set(${out_var} "${expect_file}" PARENT_SCOPE)
endfunction()

# --- Harness lanes ---------------------------------------------------------

# The harness must be able to fail before it can be trusted to pass. This is
# that proof: a program that fails one assertion, with the exact status
# compared from outside, because a program cannot report its own exit status.
httparse_add_scheme_lane(
  NAME httparse.harness.failing-body.chez.source
  BACKEND chez
  PROGRAM "${HTTPARSE_HARNESS_SELF_DIR}/harness-failing.sps"
  SOURCES ${HTTPARSE_HARNESS_MANIFEST}
          "${HTTPARSE_HARNESS_SELF_DIR}/harness-failing.sps"
  EXPECT_EXIT 1
  TIMEOUT 120
  LABELS expected-red)

# The runner cannot be its own only witness. This judges its primitives with
# raw conditionals, using none of the facilities it is checking.
httparse_add_scheme_lane(
  NAME httparse.harness.bootstrap.chez.source
  BACKEND chez
  PROGRAM "${HTTPARSE_HARNESS_SELF_DIR}/harness-bootstrap.sps"
  SOURCES ${HTTPARSE_HARNESS_MANIFEST}
          "${HTTPARSE_HARNESS_SELF_DIR}/harness-bootstrap.sps"
  TIMEOUT 120)

# The runner tested with the runner. Safe only because the bootstrap already
# established its primitives, and because every deliberate failure here runs
# inside a probe.
httparse_add_scheme_lane(
  NAME httparse.harness.self.chez.source
  BACKEND chez
  PROGRAM "${HTTPARSE_HARNESS_SELF_DIR}/harness-self-tests.sps"
  SOURCES ${HTTPARSE_HARNESS_MANIFEST}
          "${HTTPARSE_HARNESS_SELF_DIR}/harness-self-tests.sps"
  TIMEOUT 120)

# A duplicate id is a defect in the suite, not a failing assertion: one
# registration silently became unreachable. Status 2, distinct from 1.
httparse_add_scheme_lane(
  NAME httparse.harness.duplicate-case.chez.source
  BACKEND chez
  PROGRAM "${HTTPARSE_HARNESS_SELF_DIR}/harness-duplicate-case.sps"
  SOURCES ${HTTPARSE_HARNESS_MANIFEST}
          "${HTTPARSE_HARNESS_SELF_DIR}/harness-duplicate-case.sps"
  EXPECT_EXIT 2
  TIMEOUT 120
  LABELS expected-red)

# A suite that selected nothing must not report success, for the same reason
# the presets refuse an empty CTest selection one layer up.
httparse_add_scheme_lane(
  NAME httparse.harness.empty-selection.chez.source
  BACKEND chez
  PROGRAM "${HTTPARSE_HARNESS_SELF_DIR}/harness-empty-selection.sps"
  SOURCES ${HTTPARSE_HARNESS_MANIFEST}
          "${HTTPARSE_HARNESS_SELF_DIR}/harness-empty-selection.sps"
  EXPECT_EXIT 2
  TIMEOUT 120
  LABELS expected-red
  ENVIRONMENT "HTTPARSE_TEST_FILTER=no-case-has-this-in-its-name")

# --- The verbose pass line -------------------------------------------------
#
# HTTPARSE_TEST_VERBOSE makes the runner announce every passing case.
# Nothing else in this tree sets it, so without this lane the feature would
# never be executed by any test at all: the environment read, the empty-string
# rule, and the print itself would first run for whoever turned the variable on,
# and a typo in any of them would surface there rather than here.
#
# One registration is enough: the decision lives in the runner section of
# harness.sls, which reads nothing runtime-specific to make it, so a second lane
# would not exercise a different code path -- the same argument the mutation
# suite's first pass makes for every other decision in it.
#
# What this lane cannot check is that the line was printed. The adapter
# protocol exposes no output-capture service, and the runner may not reach past
# its protocol for one -- so it has no way to read back its own output, and the
# registration layer asserts exit status, not output. Both decisions are
# therefore declared survivors in SchemeMutationSuite.cmake with their reason
# recorded, alongside probe output suppression, which is unwitnessable for
# exactly the same reason.
httparse_add_scheme_lane(
  NAME httparse.harness.verbose.chez.source
  BACKEND chez
  PROGRAM "${HTTPARSE_HARNESS_SELF_DIR}/harness-self-tests.sps"
  SOURCES ${HTTPARSE_HARNESS_MANIFEST}
          "${HTTPARSE_HARNESS_SELF_DIR}/harness-self-tests.sps"
  TIMEOUT 120
  ENVIRONMENT "HTTPARSE_TEST_VERBOSE=1")

# --- The Chez launcher's refusals ------------------------------------------
#
# The launcher decides whether a lane runs at all, and its object guard is the
# sole mechanism that makes `mode=source` an honest claim. Three places in this
# tree say so -- the spec's section 7.1, HttparseSchemeLane.cmake, and the
# Chez adapter -- and until these lanes existed none of them checked it: every
# decision in the launcher could be deleted, and a file dropped into the guard
# directory, with all twenty tests still green, because a healthy lane never
# reaches a refusal.
#
# One lane per `die` path, each asserting status 2 exactly. Registered through
# the exact-status helper directly rather than through
# httparse_add_scheme_lane, whose whole purpose is to build the one correct
# command line; these three need deliberately wrong ones. Guarded on a
# discovered Chez the same way the mutation suite below is, so
# `ctest --preset no-scheme` stays green on a host with no Scheme runtime.
if(HTTPARSE_CHEZ_EXECUTABLE)
  # A guard directory that has acquired a file is no longer a guard. The file is
  # written into the build tree rather than committed: a file checked into the
  # source tree solely to make a directory non-empty is one every future glob,
  # packaging step, and reader has to be told to ignore.
  set(HTTPARSE_HARNESS_DIRTY_GUARD_DIR
      "${CMAKE_BINARY_DIR}/chez-object-guard-dirty")
  file(MAKE_DIRECTORY "${HTTPARSE_HARNESS_DIRTY_GUARD_DIR}")
  file(WRITE "${HTTPARSE_HARNESS_DIRTY_GUARD_DIR}/stray-object.so"
    "Not a compiled library. Its only job is to stop this directory being empty,\n"
    "so httparse.harness.launcher-dirty-guard.chez.source can prove the\n"
    "launcher refuses a guard directory that has acquired a file.\n")

  # Deliberately never created. The launcher must refuse a guard directory that
  # is not there rather than assume it, since `directory-list` on a missing path
  # raises and would report a crash where a named harness error belongs.
  set(HTTPARSE_HARNESS_ABSENT_GUARD_DIR
      "${CMAKE_BINARY_DIR}/chez-object-guard-absent")

  # A launcher invoked with nothing at all. Replaces the exact-arity refusal the
  # positional protocol had; with flags, "no arguments" is the natural form of
  # the same mistake.
  httparse_add_exit_code_test(
    NAME httparse.harness.launcher-no-program.chez.source
    COMMAND "${HTTPARSE_CHEZ_EXECUTABLE}"
            "--script" "${HTTPARSE_HARNESS_CHEZ_LAUNCHER}"
    EXPECT_EXIT 2
    TIMEOUT 120
    LABELS expected-red)

  httparse_add_exit_code_test(
    NAME httparse.harness.launcher-absent-guard.chez.source
    COMMAND "${HTTPARSE_CHEZ_EXECUTABLE}"
            "--script" "${HTTPARSE_HARNESS_CHEZ_LAUNCHER}"
            "--library-root" "${HTTPARSE_HARNESS_CHEZ_LIBRARY_ROOT}"
            "--object-guard" "${HTTPARSE_HARNESS_ABSENT_GUARD_DIR}"
            "--program" "${HTTPARSE_HARNESS_SELF_DIR}/harness-bootstrap.sps"
    EXPECT_EXIT 2
    TIMEOUT 120
    LABELS expected-red
    ENVIRONMENT "HTTPARSE_EXECUTION_MODE=source")

  httparse_add_exit_code_test(
    NAME httparse.harness.launcher-dirty-guard.chez.source
    COMMAND "${HTTPARSE_CHEZ_EXECUTABLE}"
            "--script" "${HTTPARSE_HARNESS_CHEZ_LAUNCHER}"
            "--library-root" "${HTTPARSE_HARNESS_CHEZ_LIBRARY_ROOT}"
            "--object-guard" "${HTTPARSE_HARNESS_DIRTY_GUARD_DIR}"
            "--program" "${HTTPARSE_HARNESS_SELF_DIR}/harness-bootstrap.sps"
    EXPECT_EXIT 2
    TIMEOUT 120
    LABELS expected-red
    ENVIRONMENT "HTTPARSE_EXECUTION_MODE=source")

  # One lane per parse decision. A correctly set-up lane never reaches a
  # refusal, so nothing else in this tree can notice one being deleted. Each
  # names a real program where it can, so that deleting the refusal produces a
  # lane that runs and exits 0 rather than one that fails for another reason.
  httparse_add_exit_code_test(
    NAME httparse.harness.launcher-unknown-flag.chez.source
    COMMAND "${HTTPARSE_CHEZ_EXECUTABLE}"
            "--script" "${HTTPARSE_HARNESS_CHEZ_LAUNCHER}"
            "--library-root" "${HTTPARSE_HARNESS_CHEZ_LIBRARY_ROOT}"
            "--object-guard" "${HTTPARSE_HARNESS_OBJECT_GUARD_DIR}"
            "--librarie-root" "${HTTPARSE_HARNESS_CHEZ_LIBRARY_ROOT}"
            "--program" "${HTTPARSE_HARNESS_SELF_DIR}/harness-bootstrap.sps"
    EXPECT_EXIT 2
    TIMEOUT 120
    LABELS expected-red
    ENVIRONMENT "HTTPARSE_EXECUTION_MODE=source")

  # A trailing flag. Without this refusal it would mean "no program" and be
  # reported as a missing required flag, sending the reader to the wrong line.
  httparse_add_exit_code_test(
    NAME httparse.harness.launcher-missing-value.chez.source
    COMMAND "${HTTPARSE_CHEZ_EXECUTABLE}"
            "--script" "${HTTPARSE_HARNESS_CHEZ_LAUNCHER}"
            "--library-root" "${HTTPARSE_HARNESS_CHEZ_LIBRARY_ROOT}"
            "--object-guard" "${HTTPARSE_HARNESS_OBJECT_GUARD_DIR}"
            "--program"
    EXPECT_EXIT 2
    TIMEOUT 120
    LABELS expected-red)

  httparse_add_exit_code_test(
    NAME httparse.harness.launcher-repeated-flag.chez.source
    COMMAND "${HTTPARSE_CHEZ_EXECUTABLE}"
            "--script" "${HTTPARSE_HARNESS_CHEZ_LAUNCHER}"
            "--library-root" "${HTTPARSE_HARNESS_CHEZ_LIBRARY_ROOT}"
            "--object-guard" "${HTTPARSE_HARNESS_OBJECT_GUARD_DIR}"
            "--program" "${HTTPARSE_HARNESS_SELF_DIR}/harness-bootstrap.sps"
            "--program" "${HTTPARSE_HARNESS_SELF_DIR}/harness-self-tests.sps"
    EXPECT_EXIT 2
    TIMEOUT 120
    LABELS expected-red
    ENVIRONMENT "HTTPARSE_EXECUTION_MODE=source")

  # The lane above witnesses the single-valued-flag check only through
  # --program; --object-guard has never been exercised as a repeated flag.
  # Both occurrences name the same real, empty guard directory -- the check
  # counts occurrences, not distinct values, so that is enough to trigger it.
  httparse_add_exit_code_test(
    NAME httparse.harness.launcher-repeated-object-guard.chez.source
    COMMAND "${HTTPARSE_CHEZ_EXECUTABLE}"
            "--script" "${HTTPARSE_HARNESS_CHEZ_LAUNCHER}"
            "--library-root" "${HTTPARSE_HARNESS_CHEZ_LIBRARY_ROOT}"
            "--object-guard" "${HTTPARSE_HARNESS_OBJECT_GUARD_DIR}"
            "--object-guard" "${HTTPARSE_HARNESS_OBJECT_GUARD_DIR}"
            "--program" "${HTTPARSE_HARNESS_SELF_DIR}/harness-bootstrap.sps"
    EXPECT_EXIT 2
    TIMEOUT 120
    LABELS expected-red
    ENVIRONMENT "HTTPARSE_EXECUTION_MODE=source")

  # The three remaining required-flag entries. Each is a separate lane because
  # required-flags is a list: an entry dropped from it is invisible to every
  # lane but the one that omits that flag.
  httparse_add_exit_code_test(
    NAME httparse.harness.launcher-no-library-root.chez.source
    COMMAND "${HTTPARSE_CHEZ_EXECUTABLE}"
            "--script" "${HTTPARSE_HARNESS_CHEZ_LAUNCHER}"
            "--object-guard" "${HTTPARSE_HARNESS_OBJECT_GUARD_DIR}"
            "--program" "${HTTPARSE_HARNESS_SELF_DIR}/harness-bootstrap.sps"
    EXPECT_EXIT 2
    TIMEOUT 120
    LABELS expected-red
    ENVIRONMENT "HTTPARSE_EXECUTION_MODE=source")

  httparse_add_exit_code_test(
    NAME httparse.harness.launcher-no-object-guard.chez.source
    COMMAND "${HTTPARSE_CHEZ_EXECUTABLE}"
            "--script" "${HTTPARSE_HARNESS_CHEZ_LAUNCHER}"
            "--library-root" "${HTTPARSE_HARNESS_CHEZ_LIBRARY_ROOT}"
            "--program" "${HTTPARSE_HARNESS_SELF_DIR}/harness-bootstrap.sps"
    EXPECT_EXIT 2
    TIMEOUT 120
    LABELS expected-red
    ENVIRONMENT "HTTPARSE_EXECUTION_MODE=source")
endif()

# A lane that is set up correctly never reaches a launcher refusal, so each one
# needs a lane of its own or a deleted refusal is invisible. The same argument
# the nine chez-source.ss refusals above are registered under.
#
# Three lanes, not one per refusal in these files. The flag-vocabulary
# refusals below the parser, and --source-guard's own absent-directory check,
# are the same shape as refusals chez-source.ss already carries and already
# has lanes for; re-proving a verbatim shape in a new file buys nothing. These
# three are what is actually new here: chez-aot.ss's missing-program check,
# chez-compile.ss's unpaired-roots check, and --source-guard's non-empty-guard
# check -- the one that most directly proves the hazard the flag exists to
# close.
if(HTTPARSE_CHEZ_EXECUTABLE)
  httparse_add_exit_code_test(
    NAME httparse.harness.chez-aot-launcher-missing-program.chez.aot
    COMMAND "${HTTPARSE_CHEZ_EXECUTABLE}" --script
            "${HTTPARSE_HARNESS_CHEZ_AOT_LAUNCHER}"
            --object-dir "${CMAKE_BINARY_DIR}"
            --source-guard "${HTTPARSE_HARNESS_OBJECT_GUARD_DIR}"
            --program "${CMAKE_BINARY_DIR}/no-such-program.so"
    EXPECT_EXIT 2
    TIMEOUT 60
    LABELS expected-red)

  httparse_add_exit_code_test(
    NAME httparse.harness.chez-compile-launcher-unpaired-roots.chez.aot
    COMMAND "${HTTPARSE_CHEZ_EXECUTABLE}" --script
            "${HTTPARSE_HARNESS_CHEZ_COMPILE_LAUNCHER}"
            --library-root "${HTTPARSE_HARNESS_CHEZ_LIBRARY_ROOT}"
            --library-root "${HTTPARSE_SRC_CHEZ_LIBRARY_ROOT}"
            --object-dir "${CMAKE_BINARY_DIR}"
            --program "${HTTPARSE_HARNESS_SELF_DIR}/harness-bootstrap.sps"
            --output "${CMAKE_BINARY_DIR}/unused.so"
    EXPECT_EXIT 2
    TIMEOUT 60
    LABELS expected-red)

  # The one new decision --source-guard's own checks add over chez-source.ss's
  # object-guard shape: chez-source.ss's launcher-dirty-guard.chez.source lane
  # already proves this die branch works when a guard has acquired a file, but
  # only for chez-source.ss's own copy of the check. Reuses
  # HTTPARSE_HARNESS_DIRTY_GUARD_DIR rather than declaring a second dirty
  # directory: both are the same fixture -- a build-tree directory holding one
  # stray file for the sole purpose of not being empty.
  httparse_add_exit_code_test(
    NAME httparse.harness.chez-aot-launcher-dirty-source-guard.chez.aot
    COMMAND "${HTTPARSE_CHEZ_EXECUTABLE}" --script
            "${HTTPARSE_HARNESS_CHEZ_AOT_LAUNCHER}"
            --object-dir "${CMAKE_BINARY_DIR}"
            --source-guard "${HTTPARSE_HARNESS_DIRTY_GUARD_DIR}"
            --program "${HTTPARSE_HARNESS_SELF_DIR}/harness-bootstrap.sps"
    EXPECT_EXIT 2
    TIMEOUT 60
    LABELS expected-red)
endif()

# --- Chez ahead-of-time lanes ----------------------------------------------
#
# Two of the programs the source lanes run, compiled. Nothing about the
# sources changes; what changes is that the text reaching the process came
# out of objects built earlier, which is why these lanes measure the copies
# the compile step kept rather than the repository sources. Two lanes, not
# one per source lane: bootstrap (the runner's primitives with no runner)
# and self (the runner on itself).
httparse_add_scheme_lane(
  NAME httparse.harness.bootstrap.chez.aot
  BACKEND chez
  PROGRAM "${HTTPARSE_HARNESS_SELF_DIR}/harness-bootstrap.sps"
  SOURCES ${HTTPARSE_HARNESS_MANIFEST}
          "${HTTPARSE_HARNESS_SELF_DIR}/harness-bootstrap.sps"
  TIMEOUT 120)

httparse_add_scheme_lane(
  NAME httparse.harness.self.chez.aot
  BACKEND chez
  PROGRAM "${HTTPARSE_HARNESS_SELF_DIR}/harness-self-tests.sps"
  SOURCES ${HTTPARSE_HARNESS_MANIFEST}
          "${HTTPARSE_HARNESS_SELF_DIR}/harness-self-tests.sps"
  TIMEOUT 120)

# --- Mutation proof for the harness ----------------------------------------

# The harness is the instrument every later milestone is measured with, so a
# passing self-test suite is not evidence until something has proved it can
# fail. This breaks each decision in the runner on a staged copy and requires
# the self-tests to notice. Registered only when a Chez was discovered: it runs
# a real lane and cannot be verified under the no-scheme preset.
#
# The self-tests load the fingerprint fixture through adapter-file-bytes; staged
# lanes inherit this process's environment through execute_process, so the
# variable must be set here.
if(HTTPARSE_CHEZ_EXECUTABLE)
  httparse_add_test(
    NAME httparse.harness.scheme-mutation.cmake.direct
    COMMAND "${CMAKE_COMMAND}"
            "-DHTTPARSE_CHEZ_EXECUTABLE=${HTTPARSE_CHEZ_EXECUTABLE}"
            -P "${CMAKE_CURRENT_LIST_DIR}/support/cmake/SchemeMutationSuite.cmake"
    TIMEOUT 900
    LABELS unit
    ENVIRONMENT "HTTPARSE_EXECUTION_MODE=source"
                "HTTPARSE_FINGERPRINT_SAMPLE=${CMAKE_SOURCE_DIR}/test/fixtures/fingerprint-sample.bin")
endif()

# --- Provenance ------------------------------------------------------------
#
# Every lane above checks the fingerprint of the text it ran against the value
# the build computed. These prove that check can fail. Without them the
# mechanism would be a claim: protium recorded two occasions where two of its
# lanes printed different digests for text both said they ran, and the suite
# stayed green, because nothing read the values back.
#
# Status 3 is what makes them falsifiable. Several lanes in this tree
# legitimately expect 1 or 2, so a provenance failure sharing either status
# would be indistinguishable from those fixtures' own expected outcomes.
httparse_add_scheme_lane(
  NAME httparse.harness.provenance.chez.source
  BACKEND chez
  PROGRAM "${HTTPARSE_HARNESS_SELF_DIR}/harness-self-tests.sps"
  SOURCES ${HTTPARSE_HARNESS_MANIFEST}
          "${HTTPARSE_HARNESS_SELF_DIR}/harness-self-tests.sps"
  WRONG_FINGERPRINT
  EXPECT_EXIT 3
  TIMEOUT 120
  LABELS expected-red)

# Two more refusals. Neither is wrapped in if(HTTPARSE_CHEZ_EXECUTABLE):
# each is a BACKEND chez lane, so httparse_add_scheme_lane's own
# no-runtime return already skips it on a Chez-less host, the same mechanism
# that skips the lane above.

# The build never produced this file, and never will: no rule names it as an
# output. That is the "you did not build before running the tests" case, which
# would otherwise escape as a raw I/O condition and a status outside the
# vocabulary.
httparse_add_scheme_lane(
  NAME httparse.harness.provenance-absent-expectation.chez.source
  BACKEND chez
  PROGRAM "${HTTPARSE_HARNESS_SELF_DIR}/harness-self-tests.sps"
  SOURCES ${HTTPARSE_HARNESS_MANIFEST}
          "${HTTPARSE_HARNESS_SELF_DIR}/harness-self-tests.sps"
  EXPECT_EXIT 3
  TIMEOUT 120
  LABELS expected-red
  ENVIRONMENT "HTTPARSE_EXPECT_FINGERPRINT_FILE=${CMAKE_BINARY_DIR}/fingerprints/never-produced.fingerprint")

# A manifest naming a source that is not there. What fails is reading the text,
# before any comparison happens.
httparse_add_scheme_lane(
  NAME httparse.harness.provenance-missing-body.chez.source
  BACKEND chez
  PROGRAM "${HTTPARSE_HARNESS_SELF_DIR}/harness-self-tests.sps"
  SOURCES ${HTTPARSE_HARNESS_MANIFEST}
          "${HTTPARSE_HARNESS_SELF_DIR}/harness-self-tests.sps"
  EXPECT_EXIT 3
  TIMEOUT 120
  LABELS expected-red
  ENVIRONMENT "HTTPARSE_FINGERPRINT_FILES=${CMAKE_BINARY_DIR}/fingerprints/no-such-body.scm")

# Provenance configured and never performed. SOURCES guarantees the
# environment carries a manifest; nothing until now guaranteed anything read
# it. This program reaches harness-summary without ever reaching
# harness-verify-provenance!, which is precisely the shape harness-bootstrap
# would have had if its hand-placed call had been forgotten -- and that would
# have run un-provenanced with nothing failing.
#
# A real manifest, deliberately: with none, the run is a process no lane
# registration started, and skipping is correct rather than a defect.
#
# Not wrapped in if(HTTPARSE_CHEZ_EXECUTABLE): this is a BACKEND chez
# lane, so httparse_add_scheme_lane's own no-runtime return already skips
# it on a Chez-less host.
httparse_add_scheme_lane(
  NAME httparse.harness.unreached-provenance.chez.source
  BACKEND chez
  PROGRAM "${HTTPARSE_HARNESS_SELF_DIR}/harness-unreached-provenance.sps"
  SOURCES ${HTTPARSE_HARNESS_MANIFEST}
          "${HTTPARSE_HARNESS_SELF_DIR}/harness-unreached-provenance.sps"
  EXPECT_EXIT 3
  TIMEOUT 120
  LABELS expected-red)

# An artifact built from text this registration does not declare. The
# expectation comes from the real harness.sls; the compile step resolves
# (httparse test harness) from a divergent fixture copy instead and
# keeps that copy as what the run measures. The two disagree, so the lane
# exits 3. This is the only lane in the tree that can fail when a compiled
# lane's fingerprint stops describing its artifact -- a lane rather than a
# mutation because the Scheme mutation suite stages one already-mutated
# tree per pass and cannot express "built before the edit, run after it"
# (design W12, slice 5a task 6).
httparse_add_scheme_lane(
  NAME httparse.harness.stale-artifact.chez.aot
  BACKEND chez
  PROGRAM "${HTTPARSE_HARNESS_SELF_DIR}/harness-self-tests.sps"
  SOURCES ${HTTPARSE_HARNESS_MANIFEST}
          "${HTTPARSE_HARNESS_SELF_DIR}/harness-self-tests.sps"
  STALE_LIBRARY_ROOT "${CMAKE_CURRENT_LIST_DIR}/fixtures/stale-root"
  EXPECT_EXIT 3
  TIMEOUT 120
  LABELS expected-red)

# --- The corpus harness (M1) ------------------------------------------------
#
# Decision 0008 makes the vendored corpus the oracle, which puts the reading of
# it on the critical path: a decoder that is one byte off makes every offset in
# a fixture wrong, and the failure reads as a parser defect. These lanes judge
# the reading machinery on hand-built inputs, before any HTTP byte is parsed.

set(HTTPARSE_CORPUS_DECODE
    "${HTTPARSE_HARNESS_CHEZ_LIBRARY_ROOT}/httparse/test/corpus-decode.sls")

httparse_add_scheme_lane(
  NAME httparse.unit.corpus-decode.chez.source
  BACKEND chez
  PROGRAM "${CMAKE_CURRENT_LIST_DIR}/common/corpus-decode-tests.sps"
  SOURCES ${HTTPARSE_HARNESS_MANIFEST}
          ${HTTPARSE_CORPUS_DECODE}
          "${CMAKE_CURRENT_LIST_DIR}/common/corpus-decode-tests.sps"
  TIMEOUT 120
  LABELS unit)

httparse_add_scheme_lane(
  NAME httparse.unit.corpus-decode.chez.aot
  BACKEND chez
  PROGRAM "${CMAKE_CURRENT_LIST_DIR}/common/corpus-decode-tests.sps"
  SOURCES ${HTTPARSE_HARNESS_MANIFEST}
          ${HTTPARSE_CORPUS_DECODE}
          "${CMAKE_CURRENT_LIST_DIR}/common/corpus-decode-tests.sps"
  TIMEOUT 120
  LABELS unit)

set(HTTPARSE_CORPUS_LOAD
    "${HTTPARSE_HARNESS_CHEZ_LIBRARY_ROOT}/httparse/test/corpus-load.sls")
set(HTTPARSE_CORPUS_DIR "${CMAKE_CURRENT_LIST_DIR}/vendor/llhttp")

httparse_add_scheme_lane(
  NAME httparse.unit.corpus-load.chez.source
  BACKEND chez
  PROGRAM "${CMAKE_CURRENT_LIST_DIR}/common/corpus-load-tests.sps"
  SOURCES ${HTTPARSE_HARNESS_MANIFEST}
          ${HTTPARSE_CORPUS_DECODE}
          ${HTTPARSE_CORPUS_LOAD}
          "${CMAKE_CURRENT_LIST_DIR}/common/corpus-load-tests.sps"
  ENVIRONMENT "HTTPARSE_CORPUS_DIR=${HTTPARSE_CORPUS_DIR}"
  TIMEOUT 120
  LABELS unit)

httparse_add_scheme_lane(
  NAME httparse.unit.corpus-load.chez.aot
  BACKEND chez
  PROGRAM "${CMAKE_CURRENT_LIST_DIR}/common/corpus-load-tests.sps"
  SOURCES ${HTTPARSE_HARNESS_MANIFEST}
          ${HTTPARSE_CORPUS_DECODE}
          ${HTTPARSE_CORPUS_LOAD}
          "${CMAKE_CURRENT_LIST_DIR}/common/corpus-load-tests.sps"
  ENVIRONMENT "HTTPARSE_CORPUS_DIR=${HTTPARSE_CORPUS_DIR}"
  TIMEOUT 120
  LABELS unit)

set(HTTPARSE_TRACE_FORMAT
    "${HTTPARSE_HARNESS_CHEZ_LIBRARY_ROOT}/httparse/test/trace-format.sls")

# Set here rather than beside the lanes that judge it, because the lanes which
# only USE it come first: a SOURCES entry naming a variable not yet set expands
# to nothing, so the dependency is dropped without a word.
set(HTTPARSE_ADAPTER
    "${HTTPARSE_HARNESS_CHEZ_LIBRARY_ROOT}/httparse/test/adapter.sls")

httparse_add_scheme_lane(
  NAME httparse.unit.trace-format.chez.source
  BACKEND chez
  PROGRAM "${CMAKE_CURRENT_LIST_DIR}/common/trace-format-tests.sps"
  SOURCES ${HTTPARSE_HARNESS_MANIFEST}
          ${HTTPARSE_TRACE_FORMAT}
          "${CMAKE_CURRENT_LIST_DIR}/common/trace-format-tests.sps"
  TIMEOUT 120
  LABELS unit)

httparse_add_scheme_lane(
  NAME httparse.unit.trace-format.chez.aot
  BACKEND chez
  PROGRAM "${CMAKE_CURRENT_LIST_DIR}/common/trace-format-tests.sps"
  SOURCES ${HTTPARSE_HARNESS_MANIFEST}
          ${HTTPARSE_TRACE_FORMAT}
          "${CMAKE_CURRENT_LIST_DIR}/common/trace-format-tests.sps"
  TIMEOUT 120
  LABELS unit)

set(HTTPARSE_CONFORMANCE
    "${HTTPARSE_HARNESS_CHEZ_LIBRARY_ROOT}/httparse/test/conformance.sls")

httparse_add_scheme_lane(
  NAME httparse.unit.conformance.chez.source
  BACKEND chez
  PROGRAM "${CMAKE_CURRENT_LIST_DIR}/common/conformance-tests.sps"
  SOURCES ${HTTPARSE_HARNESS_MANIFEST}
          ${HTTPARSE_CORPUS_LOAD}
          ${HTTPARSE_CONFORMANCE}
          "${CMAKE_CURRENT_LIST_DIR}/common/conformance-tests.sps"
  TIMEOUT 120
  LABELS unit)

httparse_add_scheme_lane(
  NAME httparse.unit.conformance.chez.aot
  BACKEND chez
  PROGRAM "${CMAKE_CURRENT_LIST_DIR}/common/conformance-tests.sps"
  SOURCES ${HTTPARSE_HARNESS_MANIFEST}
          ${HTTPARSE_CORPUS_LOAD}
          ${HTTPARSE_CONFORMANCE}
          "${CMAKE_CURRENT_LIST_DIR}/common/conformance-tests.sps"
  TIMEOUT 120
  LABELS unit)

set(HTTPARSE_RATCHET_LIB
    "${HTTPARSE_HARNESS_CHEZ_LIBRARY_ROOT}/httparse/test/ratchet.sls")
set(HTTPARSE_RATCHET_FILE "${CMAKE_CURRENT_LIST_DIR}/conformance/ratchet.txt")

httparse_add_scheme_lane(
  NAME httparse.unit.ratchet.chez.source
  BACKEND chez
  PROGRAM "${CMAKE_CURRENT_LIST_DIR}/common/ratchet-tests.sps"
  SOURCES ${HTTPARSE_HARNESS_MANIFEST}
          ${HTTPARSE_CORPUS_LOAD}
          ${HTTPARSE_RATCHET_LIB}
          "${CMAKE_CURRENT_LIST_DIR}/common/ratchet-tests.sps"
  ENVIRONMENT "HTTPARSE_CORPUS_DIR=${HTTPARSE_CORPUS_DIR}"
              "HTTPARSE_RATCHET_FILE=${HTTPARSE_RATCHET_FILE}"
  TIMEOUT 120
  LABELS unit)

httparse_add_scheme_lane(
  NAME httparse.unit.ratchet.chez.aot
  BACKEND chez
  PROGRAM "${CMAKE_CURRENT_LIST_DIR}/common/ratchet-tests.sps"
  SOURCES ${HTTPARSE_HARNESS_MANIFEST}
          ${HTTPARSE_CORPUS_LOAD}
          ${HTTPARSE_RATCHET_LIB}
          "${CMAKE_CURRENT_LIST_DIR}/common/ratchet-tests.sps"
  ENVIRONMENT "HTTPARSE_CORPUS_DIR=${HTTPARSE_CORPUS_DIR}"
              "HTTPARSE_RATCHET_FILE=${HTTPARSE_RATCHET_FILE}"
  TIMEOUT 120
  LABELS unit)

# Decision 0005 item 5: the ABI number is re-read, never remembered. Decision
# 0002's ABI clause went stale unnoticed for three weeks because it lived only
# in prose; a lane cannot.
#
# SOURCE ONLY, DELIBERATELY. Every other Scheme lane here is registered twice,
# source and aot, because the pair proves a grammar behaves identically either
# way. This lane asserts nothing about a grammar -- it asks whether the pinned
# dependency is wired up and speaking the ABI this repository targets, which is
# the same question in both modes. The aot twin would compile the whole
# generator per lane to re-answer it. The source/aot pair returns with the
# first real grammar, where it has something to prove.
httparse_add_scheme_lane(
  NAME httparse.unit.generator-abi.chez.source
  BACKEND chez
  PROGRAM "${CMAKE_CURRENT_LIST_DIR}/common/generator-abi-tests.sps"
  SOURCES ${HTTPARSE_HARNESS_MANIFEST}
          ${HTTPARSE_GENERATOR_SOURCES}
          "${CMAKE_CURRENT_LIST_DIR}/common/generator-abi-tests.sps"
  TIMEOUT 180
  LABELS unit)

# --- The grammar (M2) -------------------------------------------------------

set(HTTPARSE_GRAMMAR "${CMAKE_SOURCE_DIR}/src/httparse/grammar.sls")

httparse_add_scheme_lane(
  NAME httparse.unit.request-line.chez.source
  BACKEND chez
  PROGRAM "${CMAKE_CURRENT_LIST_DIR}/common/request-line-tests.sps"
  SOURCES ${HTTPARSE_HARNESS_MANIFEST}
          ${HTTPARSE_GENERATOR_SOURCES}
          ${HTTPARSE_GRAMMAR}
          "${CMAKE_CURRENT_LIST_DIR}/common/request-line-tests.sps"
  TIMEOUT 180
  LABELS unit)

# The source/aot pair the generator-abi lane's comment promised "returns with
# the first real grammar, where it has something to prove". This is it: the
# grammar is a datum built at load time and handed to the verifier, and a lane
# that only ever ran it from source would not notice a compiled twin behaving
# differently.
httparse_add_scheme_lane(
  NAME httparse.unit.request-line.chez.aot
  BACKEND chez
  PROGRAM "${CMAKE_CURRENT_LIST_DIR}/common/request-line-tests.sps"
  SOURCES ${HTTPARSE_HARNESS_MANIFEST}
          ${HTTPARSE_GENERATOR_SOURCES}
          ${HTTPARSE_GRAMMAR}
          "${CMAKE_CURRENT_LIST_DIR}/common/request-line-tests.sps"
  TIMEOUT 180
  LABELS unit)

# --- The header section (M3) ------------------------------------------------
#
# Asserted in llhttp's own trace text, through the same adapter the conformance
# driver uses, so an expectation is a block of lines copied out of a fixture.
foreach(mode source aot)
  httparse_add_scheme_lane(
    NAME httparse.unit.header-section.chez.${mode}
    BACKEND chez
    PROGRAM "${CMAKE_CURRENT_LIST_DIR}/common/header-section-tests.sps"
    SOURCES ${HTTPARSE_HARNESS_MANIFEST}
            ${HTTPARSE_GENERATOR_SOURCES}
            ${HTTPARSE_GRAMMAR}
            ${HTTPARSE_TRACE_FORMAT}
            ${HTTPARSE_ADAPTER}
            "${CMAKE_CURRENT_LIST_DIR}/common/header-section-tests.sps"
    TIMEOUT 180
    LABELS unit)
endforeach()

# --- Chunked bodies (M5) ----------------------------------------------------
#
# One case per distinct chunk shape, in llhttp's own trace text. The ratchet
# runs every chunked fixture at every chunk size; this lane is the literal
# expectation that survives a corpus refresh.
foreach(mode source aot)
  httparse_add_scheme_lane(
    NAME httparse.unit.chunked-body.chez.${mode}
    BACKEND chez
    PROGRAM "${CMAKE_CURRENT_LIST_DIR}/common/chunked-body-tests.sps"
    SOURCES ${HTTPARSE_HARNESS_MANIFEST}
            ${HTTPARSE_GENERATOR_SOURCES}
            ${HTTPARSE_GRAMMAR}
            ${HTTPARSE_TRACE_FORMAT}
            ${HTTPARSE_ADAPTER}
            "${CMAKE_CURRENT_LIST_DIR}/common/chunked-body-tests.sps"
    TIMEOUT 180
    LABELS unit)
endforeach()

# --- The message loop (M6) --------------------------------------------------
#
# What a message leaves behind for the next one: whether it restarts, what it
# forgets when it does, and what it refuses when it does not.
foreach(mode source aot)
  httparse_add_scheme_lane(
    NAME httparse.unit.message-loop.chez.${mode}
    BACKEND chez
    PROGRAM "${CMAKE_CURRENT_LIST_DIR}/common/message-loop-tests.sps"
    SOURCES ${HTTPARSE_HARNESS_MANIFEST}
            ${HTTPARSE_GENERATOR_SOURCES}
            ${HTTPARSE_GRAMMAR}
            ${HTTPARSE_TRACE_FORMAT}
            ${HTTPARSE_ADAPTER}
            "${CMAKE_CURRENT_LIST_DIR}/common/message-loop-tests.sps"
    TIMEOUT 180
    LABELS unit)
endforeach()

# --- The request target's two ends (M6) -------------------------------------
#
# Where the target stops and what follows it: the two behaviours the strict
# request corpus needs from llhttp's url sub-parser, which is otherwise M11's.
foreach(mode source aot)
  httparse_add_scheme_lane(
    NAME httparse.unit.request-target.chez.${mode}
    BACKEND chez
    PROGRAM "${CMAKE_CURRENT_LIST_DIR}/common/request-target-tests.sps"
    SOURCES ${HTTPARSE_HARNESS_MANIFEST}
            ${HTTPARSE_GENERATOR_SOURCES}
            ${HTTPARSE_GRAMMAR}
            ${HTTPARSE_TRACE_FORMAT}
            ${HTTPARSE_ADAPTER}
            "${CMAKE_CURRENT_LIST_DIR}/common/request-target-tests.sps"
    TIMEOUT 180
    LABELS unit)
endforeach()

# --- The response start line (M7) -------------------------------------------
#
# The two things a response does not share with a request: where the protocol
# span opens, and the status. The last group is the shared half -- one keyword
# table serving both start lines, parting at the method check.
foreach(mode source aot)
  httparse_add_scheme_lane(
    NAME httparse.unit.status-line.chez.${mode}
    BACKEND chez
    PROGRAM "${CMAKE_CURRENT_LIST_DIR}/common/status-line-tests.sps"
    SOURCES ${HTTPARSE_HARNESS_MANIFEST}
            ${HTTPARSE_GENERATOR_SOURCES}
            ${HTTPARSE_GRAMMAR}
            ${HTTPARSE_TRACE_FORMAT}
            ${HTTPARSE_ADAPTER}
            "${CMAKE_CURRENT_LIST_DIR}/common/status-line-tests.sps"
    TIMEOUT 180
    LABELS unit)
endforeach()

# --- What a response's framing decides (M7) ---------------------------------
#
# `message_needs_eof` and the five status codes, which is the whole of what a
# response's body decision has that a request's does not -- including the one
# body that ends with the connection rather than with a count.
foreach(mode source aot)
  httparse_add_scheme_lane(
    NAME httparse.unit.response-framing.chez.${mode}
    BACKEND chez
    PROGRAM "${CMAKE_CURRENT_LIST_DIR}/common/response-framing-tests.sps"
    SOURCES ${HTTPARSE_HARNESS_MANIFEST}
            ${HTTPARSE_GENERATOR_SOURCES}
            ${HTTPARSE_GRAMMAR}
            ${HTTPARSE_TRACE_FORMAT}
            ${HTTPARSE_ADAPTER}
            "${CMAKE_CURRENT_LIST_DIR}/common/response-framing-tests.sps"
    TIMEOUT 180
    LABELS unit)
endforeach()

# --- The checked-in generated parser (M2 Slice 4) ---------------------------
#
# A derived artifact, committed so that what this project ships is reviewable as
# a diff and loadable without a generator. The lane re-emits and compares bytes,
# so a grammar edit not followed by `make parser-refresh` reddens rather than
# shipping an artifact that no longer describes its source.
set(HTTPARSE_GENERATED_PARSER
    "${CMAKE_SOURCE_DIR}/src/generated/httparse-message.sls")

httparse_add_scheme_lane(
  NAME httparse.determinism.generated-artifact.chez.source
  BACKEND chez
  PROGRAM "${CMAKE_CURRENT_LIST_DIR}/common/generated-artifact-tests.sps"
  SOURCES ${HTTPARSE_HARNESS_MANIFEST}
          ${HTTPARSE_GENERATOR_SOURCES}
          ${HTTPARSE_GRAMMAR}
          ${HTTPARSE_GENERATED_PARSER}
          "${CMAKE_CURRENT_LIST_DIR}/common/generated-artifact-tests.sps"
  ENVIRONMENT "HTTPARSE_GENERATED_PARSER=${HTTPARSE_GENERATED_PARSER}"
  TIMEOUT 180
  LABELS determinism)

# --- The conformance adapter and driver (M2 Slice 4) ------------------------

# The instrument, judged on hand-built events before any parser runs
# (decision 0008 item 4).
httparse_add_scheme_lane(
  NAME httparse.unit.adapter.chez.source
  BACKEND chez
  PROGRAM "${CMAKE_CURRENT_LIST_DIR}/common/adapter-tests.sps"
  SOURCES ${HTTPARSE_HARNESS_MANIFEST}
          ${HTTPARSE_GENERATOR_SOURCES}
          ${HTTPARSE_TRACE_FORMAT}
          ${HTTPARSE_ADAPTER}
          "${CMAKE_CURRENT_LIST_DIR}/common/adapter-tests.sps"
  TIMEOUT 180
  LABELS unit)

httparse_add_scheme_lane(
  NAME httparse.unit.adapter.chez.aot
  BACKEND chez
  PROGRAM "${CMAKE_CURRENT_LIST_DIR}/common/adapter-tests.sps"
  SOURCES ${HTTPARSE_HARNESS_MANIFEST}
          ${HTTPARSE_GENERATOR_SOURCES}
          ${HTTPARSE_TRACE_FORMAT}
          ${HTTPARSE_ADAPTER}
          "${CMAKE_CURRENT_LIST_DIR}/common/adapter-tests.sps"
  TIMEOUT 180
  LABELS unit)

# The two-way ratchet, driven over the corpus. Decision 0008 item 5 splits the
# chunk-size coverage across the presets, so this is registered TWICE with two
# selections rather than once with a knob: `extremes` (chunk size 1 and the
# whole buffer) runs on every pull request, and `full` (every size from 1 to the
# input length) is a release cost. The full lane carries a `full-scan` label the
# pr preset excludes; a selection chosen from the configure-time environment
# would bake one preset's answer into the other's build tree.
set(HTTPARSE_CONFORMANCE_SOURCES
    ${HTTPARSE_HARNESS_MANIFEST}
    ${HTTPARSE_GENERATOR_SOURCES}
    ${HTTPARSE_GRAMMAR}
    ${HTTPARSE_GENERATED_PARSER}
    ${HTTPARSE_CORPUS_DECODE}
    ${HTTPARSE_CORPUS_LOAD}
    ${HTTPARSE_TRACE_FORMAT}
    ${HTTPARSE_CONFORMANCE}
    ${HTTPARSE_RATCHET_LIB}
    ${HTTPARSE_ADAPTER}
    "${CMAKE_CURRENT_LIST_DIR}/common/conformance-driver-tests.sps")

httparse_add_scheme_lane(
  NAME httparse.conformance.message.chez.source
  BACKEND chez
  PROGRAM "${CMAKE_CURRENT_LIST_DIR}/common/conformance-driver-tests.sps"
  SOURCES ${HTTPARSE_CONFORMANCE_SOURCES}
  ENVIRONMENT "HTTPARSE_CORPUS_DIR=${HTTPARSE_CORPUS_DIR}"
              "HTTPARSE_RATCHET_FILE=${HTTPARSE_RATCHET_FILE}"
              "HTTPARSE_SCAN_SELECTION=extremes"
  TIMEOUT 900
  LABELS conformance)

httparse_add_scheme_lane(
  NAME httparse.conformance.message-full-scan.chez.source
  BACKEND chez
  PROGRAM "${CMAKE_CURRENT_LIST_DIR}/common/conformance-driver-tests.sps"
  SOURCES ${HTTPARSE_CONFORMANCE_SOURCES}
  ENVIRONMENT "HTTPARSE_CORPUS_DIR=${HTTPARSE_CORPUS_DIR}"
              "HTTPARSE_RATCHET_FILE=${HTTPARSE_RATCHET_FILE}"
              "HTTPARSE_SCAN_SELECTION=full"
  TIMEOUT 900
  LABELS conformance full-scan)

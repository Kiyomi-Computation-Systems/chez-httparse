# chez-httparse test tree.
#
# The harness and build-layer surface comes first: the CMake-layer
# specifications (the build's own discovery and registration logic, which
# decides what every later lane can even see), the Scheme harness self lanes,
# the launcher refusals, provenance, and the two mutation suites. The parser's
# own lanes follow.

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

# This harness was ported from another repository under a mechanical rename,
# and the build/test tree carries no reference to the upstream name outside
# the declared dependency forms. The audit is a registered check rather than a
# review rule so that the next file copied from upstream fails the build, not
# a review.
httparse_add_test(
  NAME httparse.harness.rename-audit.cmake.direct
  COMMAND "${CMAKE_COMMAND}" -P
          "${CMAKE_CURRENT_LIST_DIR}/support/cmake/RenameAuditSpec.cmake"
  TIMEOUT 120
  LABELS unit)

# The vendored llhttp corpus is upstream's bytes and is never edited: a
# fixture believed wrong becomes a ratchet entry, not a change to the bytes.
# This lane is what makes that true rather than merely stated; it needs no
# Scheme runtime, so it also holds under the no-scheme preset.
httparse_add_test(
  NAME httparse.harness.corpus-provenance.cmake.direct
  COMMAND "${CMAKE_COMMAND}" -P
          "${CMAKE_CURRENT_LIST_DIR}/support/cmake/CorpusProvenanceSpec.cmake"
  TIMEOUT 120
  LABELS unit)

# A script run with `cmake -P` inherits none of this project's policies, so
# each one declares the floor itself. Without it, CMake 3 leaves CMP0057 unset
# and reads `IN_LIST` as a syntax error, while CMake 4, which has no old
# behaviour left for that policy, passes the same script. Running the scripts
# cannot see this on CMake 4, so this checks it as text.
# It needs no Scheme runtime, so it also holds under the no-scheme preset.
httparse_add_test(
  NAME httparse.harness.script-policy-floor.cmake.direct
  COMMAND "${CMAKE_COMMAND}" -P
          "${CMAKE_CURRENT_LIST_DIR}/support/cmake/ScriptPolicyFloorSpec.cmake"
  TIMEOUT 120
  LABELS unit)

# --- Harness paths ---------------------------------------------------------

# The generator arrives as a submodule pinned by gitlink. Both paths are
# spelled out once here and referred to by variable everywhere else, so the
# dependency's own name appears in this file twice rather than a dozen times,
# and only in the path form the rename audit accepts.
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
# ran it -- the exact defect the per-runtime keying exists to prevent. No lane
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
# why the launcher takes repeatable roots.
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
# sole mechanism that makes `mode=source` an honest claim. A healthy lane never
# reaches a refusal, so without these lanes every decision in the launcher
# could be deleted, and a file dropped into the guard directory, with every
# other lane still green.
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

  # A launcher invoked with nothing at all: with flags, "no arguments" is the
  # natural form of a launcher invoked wrongly.
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

# The harness is the instrument every parser lane is measured with, so a
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
# mechanism would be a claim: two lanes can print different digests for text
# both say they ran, and the suite stays green, because nothing reads the
# values back.
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
# environment carries a manifest; this lane guarantees something reads it.
# This program reaches harness-summary without ever reaching
# harness-verify-provenance!, which is precisely the shape harness-bootstrap
# would have if its hand-placed call were forgotten -- and that would run
# un-provenanced with nothing failing.
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
# tree per pass and cannot express "built before the edit, run after it".
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

# --- The corpus harness -----------------------------------------------------
#
# The vendored corpus is the oracle, which puts the reading of it on the
# critical path: a decoder that is one byte off makes every offset in a fixture
# wrong, and the failure reads as a parser defect. These lanes judge the
# reading machinery on hand-built inputs, before any HTTP byte is parsed.

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

# The pure mode tables, imported by the grammar AND by the harness: llhttp's
# lenient bits and message-type numbers. Set here, above every lane, for the
# reason the next comment gives -- an unset variable in SOURCES expands to
# nothing and the dependency vanishes without a word.
set(HTTPARSE_MODES "${CMAKE_SOURCE_DIR}/src/httparse/modes.sls")

# The pure method table, imported by the grammar and readable by an embedder:
# llhttp's 47 method names and the number it prints for each. Set here for the
# same reason as HTTPARSE_MODES above -- an unset variable in SOURCES expands to
# nothing and the dependency vanishes without a word.
set(HTTPARSE_METHODS "${CMAKE_SOURCE_DIR}/src/httparse/methods.sls")

# The pure keep-alive / needs-eof decisions and the FLAGS bits they read,
# imported by the grammar (which SETS those bits) and readable by an embedder
# (which decides keep-alive vs close). Set here for the same reason as the two
# tables above.
set(HTTPARSE_DECISIONS "${CMAKE_SOURCE_DIR}/src/httparse/decisions.sls")

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
# Defined here rather than beside the generated-input lanes that also use it,
# because the conformance driver below needs it and a variable read before its
# `set` expands to NOTHING with no warning -- the lane still runs, still
# passes, and has silently dropped the dependency.
set(HTTPARSE_DRIVE
    "${HTTPARSE_HARNESS_CHEZ_LIBRARY_ROOT}/httparse/test/drive.sls")

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

# The generated ABI number is re-read, never remembered: an ABI stated only in
# prose goes stale without anyone noticing, and a lane cannot.
#
# SOURCE ONLY, DELIBERATELY. Every other Scheme lane here is registered twice,
# source and aot, because the pair proves a grammar behaves identically either
# way. This lane asserts nothing about a grammar -- it asks whether the pinned
# dependency is wired up and speaking the ABI this repository targets, which is
# the same question in both modes. The aot twin would compile the whole
# generator per lane to re-answer it. The source/aot pair belongs to the
# grammar lanes, where it has something to prove.
httparse_add_scheme_lane(
  NAME httparse.unit.generator-abi.chez.source
  BACKEND chez
  PROGRAM "${CMAKE_CURRENT_LIST_DIR}/common/generator-abi-tests.sps"
  SOURCES ${HTTPARSE_HARNESS_MANIFEST}
          ${HTTPARSE_GENERATOR_SOURCES}
          "${CMAKE_CURRENT_LIST_DIR}/common/generator-abi-tests.sps"
  TIMEOUT 180
  LABELS unit)

# --- The mode tables --------------------------------------------------------
#
# Pure data with real invariants: distinct bits, llhttp's order, and every
# combination representable in the width the grammar declares the field at.
# It has its own lane because three consumers read it and none of them would
# notice a table that drifted -- a duplicated bit makes two flags one flag,
# and every fixture typed for either still passes.
foreach(mode source aot)
  httparse_add_scheme_lane(
    NAME httparse.unit.modes.chez.${mode}
    BACKEND chez
    PROGRAM "${CMAKE_CURRENT_LIST_DIR}/common/modes-tests.sps"
    SOURCES ${HTTPARSE_HARNESS_MANIFEST}
            ${HTTPARSE_MODES}
            "${CMAKE_CURRENT_LIST_DIR}/common/modes-tests.sps"
    TIMEOUT 120
    LABELS unit)
endforeach()

# --- The method table -------------------------------------------------------
#
# Pure data with real invariants, like the mode tables above: 47 distinct
# names, a dense 0..46 numbering with no gap or repeat, and two accessors that
# are inverse across the whole table. It has its own lane because the grammar
# and an embedder both import it and neither would notice a table that drifted
# -- a duplicated number collides two methods onto one, and a fixture typed for
# either still passes.
foreach(mode source aot)
  httparse_add_scheme_lane(
    NAME httparse.unit.methods.chez.${mode}
    BACKEND chez
    PROGRAM "${CMAKE_CURRENT_LIST_DIR}/common/methods-tests.sps"
    SOURCES ${HTTPARSE_HARNESS_MANIFEST}
            ${HTTPARSE_METHODS}
            "${CMAKE_CURRENT_LIST_DIR}/common/methods-tests.sps"
    TIMEOUT 120
    LABELS unit)
endforeach()

# --- The connection decisions -----------------------------------------------
#
# Pure functions with real invariants, like the tables above: llhttp's
# should_keep_alive / message_needs_eof and the FLAGS bits they read. Its own
# lane because the grammar sets the bits and an embedder reads them, and no
# corpus fixture exercises the version comparison at all -- so the quadrant
# rows here are the only thing that pins `major>0 && minor>0` against a naive
# `>= 1.1`.
foreach(mode source aot)
  httparse_add_scheme_lane(
    NAME httparse.unit.decisions.chez.${mode}
    BACKEND chez
    PROGRAM "${CMAKE_CURRENT_LIST_DIR}/common/decisions-tests.sps"
    SOURCES ${HTTPARSE_HARNESS_MANIFEST}
            ${HTTPARSE_DECISIONS}
            "${CMAKE_CURRENT_LIST_DIR}/common/decisions-tests.sps"
    TIMEOUT 120
    LABELS unit)
endforeach()

# --- The grammar ------------------------------------------------------------

# The grammar imports (httparse modes), (httparse methods) and (httparse
# decisions), so a lane that has the grammar but not all three pure libraries
# would compile against a stale one. All three come first, in dependency order
# (each depends only on (rnrs)). The url sub-parser's grammar rides along rather
# than getting a variable of its own -- it is a second machine in the same
# build-time layer, and every lane that needs one builder needs the other.
set(HTTPARSE_GRAMMAR ${HTTPARSE_MODES}
                     ${HTTPARSE_METHODS}
                     ${HTTPARSE_DECISIONS}
                     "${CMAKE_SOURCE_DIR}/src/httparse/grammar.sls"
                     "${CMAKE_SOURCE_DIR}/src/httparse/url-grammar.sls")

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

# The compiled twin of the lane above. The grammar is a datum built at load
# time and handed to the verifier, and a lane that only ever ran it from source
# would not notice a compiled twin behaving differently.
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

# --- The header section -----------------------------------------------------
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

# --- Chunked bodies ---------------------------------------------------------
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

# --- The message loop -------------------------------------------------------
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

# --- The request target's two ends ------------------------------------------
#
# Where the target stops and what follows it: the target's boundary, as
# distinct from its structure, which is the url sub-parser's.
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

# --- The response start line ------------------------------------------------
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

# --- What a response's framing decides --------------------------------------
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

# --- The checked-in generated parser ----------------------------------------
#
# A derived artifact, committed so that what this project ships is reviewable as
# a diff and loadable without a generator. The lane re-emits and compares bytes,
# so a grammar edit not followed by `make parser-refresh` reddens rather than
# shipping an artifact that no longer describes its source.
# TWO artifacts: the message parser and the url sub-parser. Both are
# emitted by one script and both are checked by one lane, so neither can be
# refreshed while the other silently goes stale.
set(HTTPARSE_GENERATED_MESSAGE_PARSER
    "${CMAKE_SOURCE_DIR}/src/generated/httparse-message.sls")
set(HTTPARSE_GENERATED_URL_PARSER
    "${CMAKE_SOURCE_DIR}/src/generated/httparse-url.sls")
set(HTTPARSE_GENERATED_PARSER ${HTTPARSE_GENERATED_MESSAGE_PARSER}
                              ${HTTPARSE_GENERATED_URL_PARSER})

httparse_add_scheme_lane(
  NAME httparse.determinism.generated-artifact.chez.source
  BACKEND chez
  PROGRAM "${CMAKE_CURRENT_LIST_DIR}/common/generated-artifact-tests.sps"
  SOURCES ${HTTPARSE_HARNESS_MANIFEST}
          ${HTTPARSE_GENERATOR_SOURCES}
          ${HTTPARSE_GRAMMAR}
          ${HTTPARSE_GENERATED_PARSER}
          "${CMAKE_CURRENT_LIST_DIR}/common/generated-artifact-tests.sps"
  ENVIRONMENT "HTTPARSE_GENERATED_PARSER=${HTTPARSE_GENERATED_MESSAGE_PARSER}"
              "HTTPARSE_GENERATED_URL_PARSER=${HTTPARSE_GENERATED_URL_PARSER}"
  TIMEOUT 180
  LABELS determinism)

# --- The conformance adapter and driver -------------------------------------

# The instrument, judged on hand-built events before any parser runs: an
# uncalibrated trace formatter cannot measure the parser.
httparse_add_scheme_lane(
  NAME httparse.unit.adapter.chez.source
  BACKEND chez
  PROGRAM "${CMAKE_CURRENT_LIST_DIR}/common/adapter-tests.sps"
  SOURCES ${HTTPARSE_HARNESS_MANIFEST}
          ${HTTPARSE_GENERATOR_SOURCES}
          ${HTTPARSE_TRACE_FORMAT}
          ${HTTPARSE_MODES}
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
          ${HTTPARSE_MODES}
          ${HTTPARSE_ADAPTER}
          "${CMAKE_CURRENT_LIST_DIR}/common/adapter-tests.sps"
  TIMEOUT 180
  LABELS unit)

# The two-way ratchet, driven over the corpus. Chunk-size coverage is split
# across the presets, so this is registered TWICE with two selections rather than once with a knob: `extremes` (chunk size 1 and the
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
    ${HTTPARSE_DRIVE}
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

# --- Generated input: the generator, the oracle reader, and the properties --
#
# Three lanes that need no llhttp, plus the opt-in differential below that
# does. The order is deliberate: an instrument is calibrated before anything
# is measured with it, so the generator and the oracle reader are specified
# first and the lanes that use them come after.

set(HTTPARSE_GENERATE
    "${HTTPARSE_HARNESS_CHEZ_LIBRARY_ROOT}/httparse/test/generate.sls")
set(HTTPARSE_ORACLE
    "${HTTPARSE_HARNESS_CHEZ_LIBRARY_ROOT}/httparse/test/oracle.sls")
set(HTTPARSE_PRNG
    "${HTTPARSE_HARNESS_CHEZ_LIBRARY_ROOT}/httparse/test/prng.sls")

foreach(mode source aot)
  httparse_add_scheme_lane(
    NAME httparse.unit.generate.chez.${mode}
    BACKEND chez
    PROGRAM "${CMAKE_CURRENT_LIST_DIR}/common/generate-tests.sps"
    SOURCES ${HTTPARSE_HARNESS_MANIFEST}
            ${HTTPARSE_MODES}
            ${HTTPARSE_PRNG}
            ${HTTPARSE_GENERATE}
            "${CMAKE_CURRENT_LIST_DIR}/common/generate-tests.sps"
    TIMEOUT 180
    LABELS unit)
endforeach()

# The oracle reader's calibration is the corpus, so this lane needs the
# fixtures even though it never runs a parser.
foreach(mode source aot)
  httparse_add_scheme_lane(
    NAME httparse.unit.oracle.chez.${mode}
    BACKEND chez
    PROGRAM "${CMAKE_CURRENT_LIST_DIR}/common/oracle-tests.sps"
    SOURCES ${HTTPARSE_HARNESS_MANIFEST}
            ${HTTPARSE_CORPUS_LOAD}
            ${HTTPARSE_TRACE_FORMAT}
            ${HTTPARSE_ORACLE}
            "${CMAKE_CURRENT_LIST_DIR}/common/oracle-tests.sps"
    ENVIRONMENT "HTTPARSE_CORPUS_DIR=${HTTPARSE_CORPUS_DIR}"
    TIMEOUT 180
    LABELS unit)
endforeach()

httparse_add_scheme_lane(
  NAME httparse.property.generated-input.chez.source
  BACKEND chez
  PROGRAM "${CMAKE_CURRENT_LIST_DIR}/common/property-tests.sps"
  SOURCES ${HTTPARSE_HARNESS_MANIFEST}
          ${HTTPARSE_GENERATOR_SOURCES}
          ${HTTPARSE_GRAMMAR}
          ${HTTPARSE_GENERATED_PARSER}
          ${HTTPARSE_CORPUS_DECODE}
          ${HTTPARSE_CORPUS_LOAD}
          ${HTTPARSE_TRACE_FORMAT}
          ${HTTPARSE_CONFORMANCE}
          ${HTTPARSE_ADAPTER}
          ${HTTPARSE_PRNG}
          ${HTTPARSE_GENERATE}
          ${HTTPARSE_DRIVE}
          "${CMAKE_CURRENT_LIST_DIR}/common/property-tests.sps"
  ENVIRONMENT "HTTPARSE_CORPUS_DIR=${HTTPARSE_CORPUS_DIR}"
  TIMEOUT 600
  LABELS property)

# --- Pausing ----------------------------------------------------------------
#
# Registered here rather than beside the other unit lanes because it needs
# HTTPARSE_DRIVE, and a CMake variable read before its `set` expands to
# nothing with no warning -- a lane whose SOURCES silently lost a dependency
# still runs and still passes.
foreach(mode source aot)
  httparse_add_scheme_lane(
    NAME httparse.unit.pausing.chez.${mode}
    BACKEND chez
    PROGRAM "${CMAKE_CURRENT_LIST_DIR}/common/pausing-tests.sps"
    SOURCES ${HTTPARSE_HARNESS_MANIFEST}
            ${HTTPARSE_GENERATOR_SOURCES}
            ${HTTPARSE_GRAMMAR}
            ${HTTPARSE_TRACE_FORMAT}
            ${HTTPARSE_CONFORMANCE}
            ${HTTPARSE_ADAPTER}
            ${HTTPARSE_DRIVE}
            "${CMAKE_CURRENT_LIST_DIR}/common/pausing-tests.sps"
    TIMEOUT 180
    LABELS unit)
endforeach()

# --- Lenient modes ----------------------------------------------------------
#
# The eleven lenient flags: a bitset the embedder writes before the first byte.
foreach(mode source aot)
  httparse_add_scheme_lane(
    NAME httparse.unit.lenient.chez.${mode}
    BACKEND chez
    PROGRAM "${CMAKE_CURRENT_LIST_DIR}/common/lenient-tests.sps"
    SOURCES ${HTTPARSE_HARNESS_MANIFEST}
            ${HTTPARSE_GENERATOR_SOURCES}
            ${HTTPARSE_GRAMMAR}
            ${HTTPARSE_TRACE_FORMAT}
            ${HTTPARSE_CONFORMANCE}
            ${HTTPARSE_ADAPTER}
            ${HTTPARSE_DRIVE}
            "${CMAKE_CURRENT_LIST_DIR}/common/lenient-tests.sps"
    TIMEOUT 180
    LABELS unit)
endforeach()

# --- Skip body --------------------------------------------------------------
#
# The one callback whose return value upstream reads. Needs HTTPARSE_DRIVE for
# the same reason the pausing lane does.
foreach(mode source aot)
  httparse_add_scheme_lane(
    NAME httparse.unit.skip-body.chez.${mode}
    BACKEND chez
    PROGRAM "${CMAKE_CURRENT_LIST_DIR}/common/skip-body-tests.sps"
    SOURCES ${HTTPARSE_HARNESS_MANIFEST}
            ${HTTPARSE_GENERATOR_SOURCES}
            ${HTTPARSE_GRAMMAR}
            ${HTTPARSE_TRACE_FORMAT}
            ${HTTPARSE_CONFORMANCE}
            ${HTTPARSE_ADAPTER}
            ${HTTPARSE_DRIVE}
            "${CMAKE_CURRENT_LIST_DIR}/common/skip-body-tests.sps"
    TIMEOUT 180
    LABELS unit)
endforeach()

# --- The url sub-parser -----------------------------------------------------
#
# One case per distinct SHAPE, plus the exits `url.md` cannot reach: none of
# its 21 inputs holds a space, a CR or an LF, and upstream gives every node
# inside a URL an edge for each. Those expectations come from a purpose-built
# url oracle, never from this parser.
foreach(mode source aot)
  httparse_add_scheme_lane(
    NAME httparse.unit.url.chez.${mode}
    BACKEND chez
    PROGRAM "${CMAKE_CURRENT_LIST_DIR}/common/url-tests.sps"
    SOURCES ${HTTPARSE_HARNESS_MANIFEST}
            ${HTTPARSE_GENERATOR_SOURCES}
            ${HTTPARSE_GRAMMAR}
            ${HTTPARSE_TRACE_FORMAT}
            ${HTTPARSE_ADAPTER}
            "${CMAKE_CURRENT_LIST_DIR}/common/url-tests.sps"
    TIMEOUT 180
    LABELS unit)
endforeach()

# --- The documented example -------------------------------------------------
#
# README.org shows this code. It runs here so the README cannot drift: a
# documented example nothing executes is a claim about an older version.

foreach(mode source aot)
  httparse_add_scheme_lane(
    NAME httparse.example.parse-request.chez.${mode}
    BACKEND chez
    PROGRAM "${CMAKE_CURRENT_LIST_DIR}/common/example-tests.sps"
    SOURCES ${HTTPARSE_HARNESS_MANIFEST}
            ${HTTPARSE_GENERATOR_SOURCES}
            ${HTTPARSE_GENERATED_PARSER}
            "${CMAKE_CURRENT_LIST_DIR}/common/example-tests.sps"
    TIMEOUT 180
    LABELS example)
endforeach()

# --- The API reference ------------------------------------------------------
#
# docs/reference.md is written by hand; this checks that it is complete. Every
# export of this repository's public libraries must have exactly one entry,
# and every entry for the generator's runtime must name a real export of it.
# The public libraries are globbed rather than listed, so a new one fails this
# lane until the page documents it. The two grammars are excluded by name:
# they build the machines and are never imported by an embedder.

file(GLOB HTTPARSE_REFERENCE_EXACT_SOURCES
     "${CMAKE_SOURCE_DIR}/src/httparse/*.sls"
     "${CMAKE_SOURCE_DIR}/src/generated/*.sls")
list(REMOVE_ITEM HTTPARSE_REFERENCE_EXACT_SOURCES
     "${CMAKE_SOURCE_DIR}/src/httparse/grammar.sls"
     "${CMAKE_SOURCE_DIR}/src/httparse/url-grammar.sls")
list(SORT HTTPARSE_REFERENCE_EXACT_SOURCES)
list(JOIN HTTPARSE_REFERENCE_EXACT_SOURCES "|" HTTPARSE_REFERENCE_EXACT_JOINED)
set(HTTPARSE_REFERENCE_LIBRARY
    "${HTTPARSE_HARNESS_CHEZ_LIBRARY_ROOT}/httparse/test/reference.sls")

foreach(mode source aot)
  httparse_add_scheme_lane(
    NAME httparse.docs.reference.chez.${mode}
    BACKEND chez
    PROGRAM "${CMAKE_CURRENT_LIST_DIR}/common/reference-tests.sps"
    SOURCES ${HTTPARSE_HARNESS_MANIFEST}
            ${HTTPARSE_REFERENCE_LIBRARY}
            "${CMAKE_CURRENT_LIST_DIR}/common/reference-tests.sps"
    ENVIRONMENT "HTTPARSE_REFERENCE_DOC=${CMAKE_SOURCE_DIR}/docs/reference.md"
                "HTTPARSE_REFERENCE_EXACT_SOURCES=${HTTPARSE_REFERENCE_EXACT_JOINED}"
                "HTTPARSE_REFERENCE_SUBSET_SOURCES=${HTTPARSE_GENERATOR_COLLECTION}/runtime.sls"
    TIMEOUT 120
    LABELS docs)
endforeach()

# --- The Akku manifest -----------------------------------------------------
#
# Akku.manifest is what `akku publish` sends to the index. Its version must be
# the latest release in CHANGELOG.md, and each dependency's range must start
# at the version vendored under vendor/, the copy every other lane runs
# against. Nothing is loaded from vendor/: the lane reads changelogs only.
foreach(mode source aot)
  httparse_add_scheme_lane(
    NAME httparse.docs.akku-manifest.chez.${mode}
    BACKEND chez
    PROGRAM "${CMAKE_CURRENT_LIST_DIR}/common/akku-manifest-tests.sps"
    SOURCES ${HTTPARSE_HARNESS_MANIFEST}
            "${CMAKE_CURRENT_LIST_DIR}/common/akku-manifest-tests.sps"
    ENVIRONMENT "HTTPARSE_AKKU_MANIFEST=${CMAKE_SOURCE_DIR}/Akku.manifest"
                "HTTPARSE_AKKU_LOCK=${CMAKE_SOURCE_DIR}/Akku.lock"
                "HTTPARSE_CHANGELOG=${CMAKE_SOURCE_DIR}/CHANGELOG.md"
                "HTTPARSE_VENDOR_ROOT=${CMAKE_SOURCE_DIR}/vendor"
    TIMEOUT 120
    LABELS docs)
endforeach()

# --- Finishing a close-delimited body ---------------------------------------
#
# The one completion the corpus cannot reach: `parser-finish!` on a body the
# connection ends. It drives the COMMITTED parser (like the example above), so
# it carries GENERATED_PARSER rather than the grammar -- the finish callback is
# a property of what ships, and this lane is red until the artifact is
# refreshed to match a grammar that fires it.
foreach(mode source aot)
  httparse_add_scheme_lane(
    NAME httparse.unit.finish.chez.${mode}
    BACKEND chez
    PROGRAM "${CMAKE_CURRENT_LIST_DIR}/common/finish-tests.sps"
    SOURCES ${HTTPARSE_HARNESS_MANIFEST}
            ${HTTPARSE_GENERATOR_SOURCES}
            ${HTTPARSE_GENERATED_PARSER}
            "${CMAKE_CURRENT_LIST_DIR}/common/finish-tests.sps"
    TIMEOUT 180
    LABELS unit)
endforeach()

# --- The upgrade field ------------------------------------------------------
#
# `upgrade` is documented as llhttp's `llhttp_get_upgrade`, and no trace line
# prints it -- on a 101 nothing inside the machine reads it either -- so this
# lane is its only witness. It drives the COMMITTED parser over every plain
# request and response fixture, whole and a byte at a time, and compares the
# field at each `on-headers-complete` with llhttp's rule applied to the method,
# status and flags the fixture's own log records.
foreach(mode source aot)
  httparse_add_scheme_lane(
    NAME httparse.unit.upgrade-field.chez.${mode}
    BACKEND chez
    PROGRAM "${CMAKE_CURRENT_LIST_DIR}/common/upgrade-field-tests.sps"
    SOURCES ${HTTPARSE_HARNESS_MANIFEST}
            ${HTTPARSE_CORPUS_DECODE}
            ${HTTPARSE_CORPUS_LOAD}
            ${HTTPARSE_MODES}
            ${HTTPARSE_METHODS}
            ${HTTPARSE_DECISIONS}
            ${HTTPARSE_GENERATOR_SOURCES}
            ${HTTPARSE_GENERATED_PARSER}
            "${CMAKE_CURRENT_LIST_DIR}/common/upgrade-field-tests.sps"
    ENVIRONMENT "HTTPARSE_CORPUS_DIR=${HTTPARSE_CORPUS_DIR}"
    TIMEOUT 180
    LABELS unit)
endforeach()

# --- The invalid-transfer-encoding node names -------------------------------
#
# docs/errors.md names the node `parser-error-node-name` returns for each of the
# four ways a request fails with `invalid-transfer-encoding`. Node names are
# ours, so no trace prints them. This lane drives the COMMITTED parser over
# every strict request fixture that ends in code 15, and holds each to the
# node the document names for llhttp's recorded reason. It also reads the
# artifact's error table, so a fifth reason under the code fails it even when
# no fixture reaches that reason.
foreach(mode source aot)
  httparse_add_scheme_lane(
    NAME httparse.unit.te-error-nodes.chez.${mode}
    BACKEND chez
    PROGRAM "${CMAKE_CURRENT_LIST_DIR}/common/te-error-nodes-tests.sps"
    SOURCES ${HTTPARSE_HARNESS_MANIFEST}
            ${HTTPARSE_CORPUS_DECODE}
            ${HTTPARSE_CORPUS_LOAD}
            ${HTTPARSE_MODES}
            ${HTTPARSE_TRACE_FORMAT}
            ${HTTPARSE_ADAPTER}
            ${HTTPARSE_CONFORMANCE}
            ${HTTPARSE_DRIVE}
            ${HTTPARSE_GENERATOR_SOURCES}
            ${HTTPARSE_GENERATED_PARSER}
            "${CMAKE_CURRENT_LIST_DIR}/common/te-error-nodes-tests.sps"
    ENVIRONMENT "HTTPARSE_CORPUS_DIR=${HTTPARSE_CORPUS_DIR}"
                "HTTPARSE_GENERATED_PARSER=${HTTPARSE_GENERATED_MESSAGE_PARSER}"
    TIMEOUT 180
    LABELS unit)
endforeach()

# --- What parser-stream-offset answers inside a callback ---------------------
#
# docs/callbacks.md says what a callback reads there: the bytes taken before an
# event, and the end of a span's fragment. Every other lane that reads the
# offset inside a span callback feeds one buffer from index 0, where the
# fragment's end and `to` are the same number, so a runtime that handed the
# callback `to` instead would pass all of them. This lane feeds each chunk from a
# buffer of its own, drives the COMMITTED parser over every fixture in the
# corpus, and holds each event to its log's `off=` and each fragment to the
# driver's own arithmetic.
foreach(mode source aot)
  httparse_add_scheme_lane(
    NAME httparse.unit.stream-offset.chez.${mode}
    BACKEND chez
    PROGRAM "${CMAKE_CURRENT_LIST_DIR}/common/stream-offset-tests.sps"
    SOURCES ${HTTPARSE_HARNESS_MANIFEST}
            ${HTTPARSE_CORPUS_DECODE}
            ${HTTPARSE_CORPUS_LOAD}
            ${HTTPARSE_MODES}
            ${HTTPARSE_TRACE_FORMAT}
            ${HTTPARSE_ADAPTER}
            ${HTTPARSE_GENERATOR_SOURCES}
            ${HTTPARSE_GENERATED_PARSER}
            "${CMAKE_CURRENT_LIST_DIR}/common/stream-offset-tests.sps"
    ENVIRONMENT "HTTPARSE_CORPUS_DIR=${HTTPARSE_CORPUS_DIR}"
    TIMEOUT 180
    LABELS unit)
endforeach()

# --- What parsing costs -----------------------------------------------------
#
# The allocation audit asserts a SHAPE and runs on every pull request; the
# benchmark prints numbers and carries a label the pull-request preset does
# not select, because a measured rate that gates a merge is a lane that fails
# for reasons which are not about this code.
#
# BOTH MODES, AND THEY AGREE -- WHICH IS THE POINT, NOT A DISAPPOINTMENT.
# A "source" lane does not interpret. Measured against Chez 10.4.1, a hot
# loop of 20,000,000 iterations: 27ms under `--script` from source, 28ms
# under `--program` from a compile-program object, and 455ms from that same
# source with `(current-eval interpret)`. Chez compiles on load; what
# ahead-of-time compilation buys is STARTUP, not throughput -- visible here
# as the allocation lane's wall time, 0.72s from source against 0.17s
# compiled, while the measured region inside it is identical to the byte.
#
# So what the aot half adds is not a faster number. It is the observation
# that the cost claims hold in the configuration this project actually ships,
# rather than the inference that they must. Both programs print the execution
# mode beside every figure; the release log carries the two runs side by side
# and a reader compares them there. That comparison is NOT machine-checked:
# no cross-lane comparison exists in this tree, and the failure it would
# catch -- a parser whose cost depends on when it was compiled -- is not
# worth inventing one for.
foreach(mode source aot)
  httparse_add_scheme_lane(
    NAME httparse.property.allocation.chez.${mode}
    BACKEND chez
    PROGRAM "${CMAKE_CURRENT_LIST_DIR}/common/allocation-tests.sps"
    SOURCES ${HTTPARSE_HARNESS_MANIFEST}
            ${HTTPARSE_GENERATOR_SOURCES}
            ${HTTPARSE_GENERATED_PARSER}
            "${CMAKE_CURRENT_LIST_DIR}/common/allocation-tests.sps"
    TIMEOUT 300
    LABELS property)

  httparse_add_scheme_lane(
    NAME httparse.benchmark.throughput.chez.${mode}
    BACKEND chez
    PROGRAM "${CMAKE_CURRENT_LIST_DIR}/common/benchmark-tests.sps"
    SOURCES ${HTTPARSE_HARNESS_MANIFEST}
            ${HTTPARSE_GENERATOR_SOURCES}
            ${HTTPARSE_GENERATED_PARSER}
            "${CMAKE_CURRENT_LIST_DIR}/common/benchmark-tests.sps"
    TIMEOUT 300
    LABELS benchmark)
endforeach()

# --- The live llhttp differential: local, opt-in, never a merge gate --------
#
# The vendored corpus is the oracle CI runs; this one needs Node and a C
# toolchain, so it stays local. Its job is generated input, where no recorded
# trace can exist. The checkout is named by a variable and the lane is ABSENT
# when it is unset -- not skipped, not failing, not registered at all. Point
# it at a built llhttp checkout to turn the lane on:
#
#   cmake --preset dev -DHTTPARSE_LLHTTP_ROOT=/path/to/llhttp
#
# The checkout must have had `npm install` run in it; the oracle binaries are
# built by llhttp's OWN test harness, which is the program that produced the
# vendored corpus.
set(HTTPARSE_LLHTTP_ROOT "" CACHE PATH
    "A built llhttp checkout; enables the local live-oracle differential lane")

if(HTTPARSE_LLHTTP_ROOT)
  # Asked for and unbuildable is an error, not a silent absence: a lane that
  # quietly fails to register is how a green run stops meaning anything.
  find_program(HTTPARSE_NODE_EXECUTABLE NAMES node
               DOC "Node.js, used to build and drive the llhttp oracle")
  if(NOT HTTPARSE_NODE_EXECUTABLE)
    message(FATAL_ERROR
      "HTTPARSE_LLHTTP_ROOT is set but no `node` was found. The live-oracle "
      "lane builds llhttp with its own Node harness. Install Node, or "
      "reconfigure with -UHTTPARSE_LLHTTP_ROOT to leave the lane out.")
  endif()
  if(NOT EXISTS "${HTTPARSE_LLHTTP_ROOT}/node_modules/llparse-test-fixture")
    message(FATAL_ERROR
      "HTTPARSE_LLHTTP_ROOT=${HTTPARSE_LLHTTP_ROOT} has no node_modules/"
      "llparse-test-fixture. Run `npm install` in that checkout, or "
      "reconfigure with -UHTTPARSE_LLHTTP_ROOT to leave the lane out.")
  endif()

  set(HTTPARSE_ORACLE_BIN_DIR "${CMAKE_BINARY_DIR}/llhttp-oracle")
  set(HTTPARSE_ORACLE_BUILD "${CMAKE_SOURCE_DIR}/tools/oracle/build-oracle.mjs")
  set(HTTPARSE_ORACLE_RUNNER "${CMAKE_SOURCE_DIR}/tools/oracle/run-oracle.mjs")

  # Built in the checkout's own directory so that `--import tsx` and every
  # bare import inside llhttp's harness resolve against its node_modules
  # rather than against this project, which has neither.
  # THREE BINARIES, BECAUSE THERE ARE TWO PARSERS AND TWO MESSAGE KINDS.
  # `url-url-c` is llhttp's URL sub-parser built standalone -- the program
  # `url.md` was recorded from -- and it is listed here so that a checkout
  # whose url build fails is a build error rather than a differential run
  # that quietly compares only requests and responses.
  add_custom_command(
    OUTPUT "${HTTPARSE_ORACLE_BIN_DIR}/http-request-c"
           "${HTTPARSE_ORACLE_BIN_DIR}/http-response-c"
           "${HTTPARSE_ORACLE_BIN_DIR}/url-url-c"
           "${HTTPARSE_ORACLE_BIN_DIR}/http-modes-c"
           "${HTTPARSE_ORACLE_BIN_DIR}/http-request-lenient-headers-c"
           "${HTTPARSE_ORACLE_BIN_DIR}/VERSION"
    COMMAND "${HTTPARSE_NODE_EXECUTABLE}" --import tsx
            "${HTTPARSE_ORACLE_BUILD}" "${HTTPARSE_LLHTTP_ROOT}"
            "${HTTPARSE_ORACLE_BIN_DIR}"
    WORKING_DIRECTORY "${HTTPARSE_LLHTTP_ROOT}"
    DEPENDS "${HTTPARSE_ORACLE_BUILD}"
            "${CMAKE_SOURCE_DIR}/tools/oracle/lenient-init.c"
    COMMENT "httparse: building the live llhttp oracle binaries"
    VERBATIM)
  add_custom_target(httparse_llhttp_oracle ALL
    DEPENDS "${HTTPARSE_ORACLE_BIN_DIR}/http-request-c"
            "${HTTPARSE_ORACLE_BIN_DIR}/http-response-c"
            "${HTTPARSE_ORACLE_BIN_DIR}/url-url-c"
            "${HTTPARSE_ORACLE_BIN_DIR}/http-modes-c"
            "${HTTPARSE_ORACLE_BIN_DIR}/http-request-lenient-headers-c"
            "${HTTPARSE_ORACLE_BIN_DIR}/VERSION")

  httparse_add_scheme_lane(
    NAME httparse.differential.llhttp.chez.source
    BACKEND chez
    PROGRAM "${CMAKE_CURRENT_LIST_DIR}/common/differential-tests.sps"
    SOURCES ${HTTPARSE_HARNESS_MANIFEST}
            ${HTTPARSE_GENERATOR_SOURCES}
            ${HTTPARSE_GRAMMAR}
            ${HTTPARSE_GENERATED_PARSER}
            ${HTTPARSE_CORPUS_DECODE}
            ${HTTPARSE_CORPUS_LOAD}
            ${HTTPARSE_TRACE_FORMAT}
            ${HTTPARSE_CONFORMANCE}
            ${HTTPARSE_ADAPTER}
            ${HTTPARSE_PRNG}
            ${HTTPARSE_GENERATE}
            ${HTTPARSE_DRIVE}
            ${HTTPARSE_ORACLE}
            "${CMAKE_CURRENT_LIST_DIR}/common/differential-tests.sps"
    ENVIRONMENT "HTTPARSE_CORPUS_DIR=${HTTPARSE_CORPUS_DIR}"
                "HTTPARSE_ORACLE_BIN_DIR=${HTTPARSE_ORACLE_BIN_DIR}"
                "HTTPARSE_ORACLE_RUNNER=${HTTPARSE_ORACLE_RUNNER}"
                "HTTPARSE_ORACLE_NODE=${HTTPARSE_NODE_EXECUTABLE}"
    TIMEOUT 900
    LABELS differential)
endif()

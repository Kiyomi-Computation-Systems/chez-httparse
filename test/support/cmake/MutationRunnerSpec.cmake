# Specification for the verdict decision in
# test/support/cmake/MutationRunner.cmake.
#
# Every specification in this repository is trusted through one decision it
# never made for itself: whether a verify command's result counts as catching
# a mutation, and whether it caught it for the declared reason
# (httparse_mutation_verdict). The suites whose mutations it judges cannot
# also specify it -- the same blind spot SpecSupportSpec.cmake closes for the
# two assertion helpers every other specification depends on. This file
# closes it one layer down, for the runner underneath SpecSupport and every
# specification alike.
#
# Without it, deleting the branch that turns a caught-for-the-wrong-reason
# result into a failure leaves the whole CMake-layer mutation suite green,
# because nothing else mutates the mechanism that reads EXPECT_STATUS and
# EXPECT_OUTPUT_MATCHES. This file, and the mutations in MutationSuite.cmake
# that target it, are what close that gap.

cmake_minimum_required(VERSION 3.26)

include("${CMAKE_CURRENT_LIST_DIR}/MutationRunner.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/SpecSupport.cmake")

set(SPEC_SELF "${CMAKE_CURRENT_LIST_FILE}")

if(DEFINED HTTPARSE_SPEC_CASE)
  set(c "${HTTPARSE_SPEC_CASE}")

  # httparse_mutation has no project-context dependency to stub: on
  # acceptance it only parses arguments and writes GLOBAL properties, both
  # fine under a bare `cmake -P`. Neither victim case below is ever run
  # through httparse_mutation_run, so FILE and SPEC name nothing real.
  if(c STREQUAL "mutation-rejects-survives-with-expect-status")
    httparse_mutation(
      FILE "${SPEC_SELF}" SPEC "${SPEC_SELF}"
      LABEL "victim" FIND [[x]] REPLACE [[y]]
      EXPECT_SURVIVES "a reason"
      EXPECT_STATUS 1)
  elseif(c STREQUAL "mutation-rejects-survives-with-expect-output-matches")
    httparse_mutation(
      FILE "${SPEC_SELF}" SPEC "${SPEC_SELF}"
      LABEL "victim" FIND [[x]] REPLACE [[y]]
      EXPECT_SURVIVES "a reason"
      EXPECT_OUTPUT_MATCHES "pattern")
  elseif(c STREQUAL "run-fails-a-wrong-reason-mutation")
    # Everything above tests httparse_mutation_verdict directly: pure,
    # no execute_process, no filesystem. What it cannot reach is whether
    # httparse_mutation_run's imperative shell actually *acts* on a
    # `wrong-reason` verdict by failing, rather than computing it correctly
    # and discarding the answer -- a branch that can be deleted with the real
    # CMake-layer suite staying green, because nothing declared there is
    # genuinely caught for the wrong reason. Closing that means
    # running the real thing: a real staged mutation, a real spec, and a
    # deliberately unsatisfiable EXPECT_OUTPUT_MATCHES, so whatever this
    # mutation is caught by, it is caught for the wrong reason by
    # construction -- no need to know or guess the real exit status.
    #
    # SpecSupport.cmake/SpecSupportSpec.cmake is the fixture: small, fast,
    # and already staged by HTTPARSE_MUTATION_STAGE_DIRS's own default.
    # The FIND/REPLACE is the same one MutationSuite.cmake already declares
    # for "spec-support: spec_check_equal never fails" -- a real, known-caught
    # mutation reused here rather than invented, and independent of it: this
    # runs in its own staged copy under its own EXPECT_OUTPUT_MATCHES.
    if(DEFINED ENV{HTTPARSE_TEST_TMPDIR})
      set(fixture_work_dir "$ENV{HTTPARSE_TEST_TMPDIR}/shell-wrong-reason-check")
    else()
      get_filename_component(_fixture_source_root "${CMAKE_CURRENT_LIST_DIR}/../../.." ABSOLUTE)
      set(fixture_work_dir "${_fixture_source_root}/build/mutation-runner-spec-shell-check")
    endif()
    get_filename_component(fixture_source_root "${CMAKE_CURRENT_LIST_DIR}/../../.." ABSOLUTE)
    file(REMOVE_RECURSE "${fixture_work_dir}")

    # Narrowed to just this one directory: SpecSupportSpec.cmake includes
    # nothing from cmake/, and staging that tree too would only add cost.
    set(HTTPARSE_MUTATION_STAGE_DIRS "test/support/cmake")

    httparse_mutation(
      FILE test/support/cmake/SpecSupport.cmake SPEC SpecSupportSpec.cmake
      LABEL "fixture: a real, known-caught mutation given an unsatisfiable EXPECT_OUTPUT_MATCHES"
      FIND [[  if(NOT actual STREQUAL expected)]]
      REPLACE [[  if(FALSE)]]
      EXPECT_OUTPUT_MATCHES "HTTPARSE-SENTINEL-NEVER-PRODUCED-BY-SPECSUPPORTSPEC")

    httparse_mutation_run("${fixture_source_root}" "${fixture_work_dir}/stage")
    file(REMOVE_RECURSE "${fixture_work_dir}")
  else()
    message(FATAL_ERROR "httparse-spec: unknown case '${c}'")
  endif()

  message(FATAL_ERROR "httparse-spec: case '${c}' was accepted but must be rejected")
endif()

# --- httparse_mutation_verdict ------------------------------------------
#
# Pure: no execute_process, no filesystem. rc and output stand in for what
# httparse_mutation_run_spec would have returned from a real verify run;
# expect_status and expect_output_matches stand in for what a mutation
# declared.

# rc 0 is not-caught, whatever was declared. EXPECT_STATUS and
# EXPECT_OUTPUT_MATCHES narrow what a *nonzero* result has to look like to
# count; they do not manufacture a catch out of a zero exit.
httparse_mutation_verdict("0" "" "" "" verdict reason)
spec_check_equal("${verdict}" "not-caught" "rc 0 with nothing declared is not-caught")

httparse_mutation_verdict("0" "irrelevant output" "1" "irrelevant" verdict reason)
spec_check_equal("${verdict}" "not-caught"
  "rc 0 is not-caught even when EXPECT_STATUS and EXPECT_OUTPUT_MATCHES are both declared")

# Neither declared: plain nonzero-means-caught, the default rule.
httparse_mutation_verdict("1" "" "" "" verdict reason)
spec_check_equal("${verdict}" "caught" "nonzero with neither declared is caught")

# EXPECT_STATUS declared alone.
httparse_mutation_verdict("2" "" "2" "" verdict reason)
spec_check_equal("${verdict}" "caught" "a satisfied EXPECT_STATUS alone is caught")

set(verdict "sentinel")
set(reason "sentinel")
httparse_mutation_verdict("2" "" "1" "" verdict reason)
spec_check_equal("${verdict}" "wrong-reason" "a status mismatch is wrong-reason")
spec_check_equal("${reason}" "expected the verify command to exit 1, got 2"
  "the wrong-reason message names both the expected and the actual status")

# EXPECT_OUTPUT_MATCHES declared alone.
httparse_mutation_verdict("1" "hello caught world" "" "caught" verdict reason)
spec_check_equal("${verdict}" "caught" "a satisfied EXPECT_OUTPUT_MATCHES alone is caught")

httparse_mutation_verdict("1" "hello world" "" "needle" verdict reason)
spec_check_equal("${verdict}" "wrong-reason" "an output mismatch is wrong-reason")
spec_check_equal("${reason}"
  "expected the verify command's output to match 'needle', but it did not"
  "the wrong-reason message names the pattern that did not match")

# Both declared and both satisfied: caught.
httparse_mutation_verdict("2" "hello caught world" "2" "caught" verdict reason)
spec_check_equal("${verdict}" "caught"
  "both EXPECT_STATUS and EXPECT_OUTPUT_MATCHES satisfied is caught")

# A satisfied EXPECT_STATUS must not excuse a failed EXPECT_OUTPUT_MATCHES.
httparse_mutation_verdict("2" "hello world" "2" "needle" verdict reason)
spec_check_equal("${verdict}" "wrong-reason"
  "a satisfied EXPECT_STATUS does not excuse a failed EXPECT_OUTPUT_MATCHES")

# "0" is a legitimate regex matching a literal zero, and CMake reads it as
# false. Truthiness on expect_output_matches would silently skip this case and
# report caught; only a presence test written as STREQUAL "" enforces it.
httparse_mutation_verdict("1" "no digits here" "" "0" verdict reason)
spec_check_equal("${verdict}" "wrong-reason"
  "an EXPECT_OUTPUT_MATCHES pattern that reads as CMake-false ('0') is still enforced")

# Seeded, so a function that writes nothing cannot satisfy the assertion by
# coincidence: an unseeded "verdict" could already hold "caught" or
# "not-caught" from an earlier call in this same process.
set(verdict "sentinel-verdict")
set(reason "sentinel-reason")
httparse_mutation_verdict("0" "" "" "" verdict reason)
spec_check_equal("${verdict}" "not-caught" "rc 0 overwrites a seeded verdict")
spec_check_equal("${reason}" "" "rc 0 clears a seeded reason")

set(reason "sentinel-reason")
httparse_mutation_verdict("1" "" "" "" verdict reason)
spec_check_equal("${reason}" "" "a plain caught verdict clears a seeded reason")

# --- httparse_mutation: EXPECT_SURVIVES beside EXPECT_STATUS/EXPECT_OUTPUT_MATCHES ---
#
# httparse_mutation_run judges a declared survivor only by whether the
# verify command exited zero -- its `survives` branch checks the verdict only
# against `not-caught`. EXPECT_STATUS and EXPECT_OUTPUT_MATCHES would be
# parsed and stored for such a mutation but never read. Declaring the
# combination is refused at registration rather than silently meaning less
# than it says.
spec_expect_all_rejected("${SPEC_SELF}"
  "mutation-rejects-survives-with-expect-status|declares EXPECT_SURVIVES together with EXPECT_STATUS or EXPECT_OUTPUT_MATCHES"
  "mutation-rejects-survives-with-expect-output-matches|declares EXPECT_SURVIVES together with EXPECT_STATUS or EXPECT_OUTPUT_MATCHES")

# --- httparse_mutation_run: a wrong-reason verdict must cause a failure ---
#
# httparse_mutation_verdict computing `wrong-reason` correctly, checked
# directly above, is only half of what makes EXPECT_STATUS and
# EXPECT_OUTPUT_MATCHES mean anything: httparse_mutation_run has to act on
# that verdict by failing. Deleting that branch leaves the real CMake-layer
# suite green, because nothing declared there is genuinely caught for a
# different reason than the one it names. The case dispatched to above is
# built to be exactly that on purpose, so this is a real staged run, not a
# direct call: httparse_mutation_run is the imperative shell under test,
# and it cannot be exercised any other way.
spec_expect_rejected("${SPEC_SELF}" "run-fails-a-wrong-reason-mutation"
  "but for the wrong reason -- expected the verify command's output to match 'HTTPARSE-SENTINEL-NEVER-PRODUCED-BY-SPECSUPPORTSPEC'")

spec_finish("MutationRunner")

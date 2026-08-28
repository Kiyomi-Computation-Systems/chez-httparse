# Specification for SpecSupport.cmake.
#
# WHY THIS FILE EXISTS
#
# Every positive assertion and every negative case in every other specification
# routes through two functions in SpecSupport.cmake. Neither was tested. Breaking
# either one left all four specifications green, which meant the whole suite
# could report success while checking nothing -- the one failure mode that no
# amount of care in the specifications themselves would reveal.
#
# WHY IT CANNOT USE THE HELPERS IT TESTS
#
# A specification that asserted with spec_check_equal would be checking the
# helper using the helper: neuter it and both the subject and the instrument
# fail silently together. The driver below therefore implements its own minimal
# exit-status assertion and deliberately does not call into SpecSupport. That
# duplication is the point, not an oversight.
#
# HOW IT WORKS
#
# The helpers signal failure with message(SEND_ERROR), which cannot be caught
# in-process -- it sets the script's exit status and keeps going. So each
# scenario runs in a child `cmake -P` of this file and is judged by its exit
# status. Some scenarios are victims: children that exist only to be rejected by
# a helper running one level up.

cmake_minimum_required(VERSION 3.26)

set(SPEC_SELF "${CMAKE_CURRENT_LIST_FILE}")

# A message long enough that CMake wraps it across several lines when it is
# printed. spec_flatten exists so an assertion survives that wrapping; without a
# case whose expected text spans a wrap, that flattening is never exercised.
set(LONG_MESSAGE "httparse: this diagnostic is deliberately long enough that CMake will wrap it across more than one line when it is printed to stderr, which is exactly the condition spec_flatten exists to absorb")

if(DEFINED HTTPARSE_SPEC_CASE)
  include("${CMAKE_CURRENT_LIST_DIR}/SpecSupport.cmake")
  set(c "${HTTPARSE_SPEC_CASE}")

  # --- victims: children invoked by a helper one level up -------------------
  if(c STREQUAL "victim-succeeds")
    # Exits 0. A helper asked to prove this child was rejected must complain.
  elseif(c STREQUAL "victim-fails-known")
    message(FATAL_ERROR "httparse: the known failure")
  elseif(c STREQUAL "victim-fails-otherwise")
    message(FATAL_ERROR "httparse: a completely unrelated problem")
  elseif(c STREQUAL "victim-fails-wrapped")
    message(FATAL_ERROR "${LONG_MESSAGE}")

  # --- spec_check_equal -----------------------------------------------------
  elseif(c STREQUAL "check-equal-accepts-equal")
    spec_check_equal("tarm64osx" "tarm64osx" "equal values")
  elseif(c STREQUAL "check-equal-rejects-unequal")
    spec_check_equal("tarm64osx" "ta6osx" "unequal values")
  elseif(c STREQUAL "check-equal-rejects-empty-vs-value")
    # The shape a stale-returning accessor produces; it must not read as equal.
    spec_check_equal("" "tarm64osx" "empty against a value")

  # --- spec_expect_rejected -------------------------------------------------
  elseif(c STREQUAL "rejected-accepts-correct-rejection")
    spec_expect_rejected("${SPEC_SELF}" "victim-fails-known" "httparse: the known failure")
  elseif(c STREQUAL "rejected-complains-when-child-succeeds")
    spec_expect_rejected("${SPEC_SELF}" "victim-succeeds" "httparse: the known failure")
  elseif(c STREQUAL "rejected-complains-on-wrong-message")
    spec_expect_rejected("${SPEC_SELF}" "victim-fails-otherwise" "httparse: the known failure")
  elseif(c STREQUAL "banner-after-failure")
    # One failed assertion, then a close. The banner must not claim success.
    spec_check_equal("a" "b" "a deliberately failed assertion")
    spec_finish("SomeSubject")
  elseif(c STREQUAL "banner-after-success")
    spec_check_equal("a" "a" "a passing assertion")
    spec_finish("SomeSubject")
  elseif(c STREQUAL "rejected-tolerates-wrapped-message")
    spec_expect_rejected("${SPEC_SELF}" "victim-fails-wrapped" "${LONG_MESSAGE}")

  else()
    message(FATAL_ERROR "httparse-spec: unknown case '${c}'")
  endif()

  return()
endif()

# --- Driver ----------------------------------------------------------------
#
# Deliberately does not use SpecSupport. See the header.

set(spec_support_failures 0)

# must_exit(<case> zero|nonzero <what> [<expected diagnostic fragment>])
#
# Exit status alone is too coarse here. spec_expect_rejected has two distinct
# complaints -- "the child did not fail" and "the child failed for a different
# reason" -- and each is a different thing to tell whoever is debugging. Worse,
# either one masks the loss of the other: disable the exit-status check and the
# message check still rejects the case, so the case still exits nonzero and the
# defect goes unnoticed. Mutation testing found exactly that. Pinning the
# expected diagnostic is what separates them.
#
# The local flatten is deliberate duplication of spec_flatten: this driver must
# not depend on the file it is testing.
function(must_exit case expectation what)
  execute_process(
    COMMAND "${CMAKE_COMMAND}" "-DHTTPARSE_SPEC_CASE=${case}" -P "${SPEC_SELF}"
    RESULT_VARIABLE rc
    OUTPUT_VARIABLE out
    ERROR_VARIABLE err)

  if(expectation STREQUAL "zero" AND NOT rc EQUAL 0)
    message(SEND_ERROR
      "httparse-spec: ${what}: expected SpecSupport to accept this, but case "
      "'${case}' exited ${rc}.\n--- stderr ---\n${err}")
    return()
  elseif(expectation STREQUAL "nonzero" AND rc EQUAL 0)
    message(SEND_ERROR
      "httparse-spec: ${what}: expected SpecSupport to reject this, but case "
      "'${case}' exited 0. The assertion helper is not asserting.")
    return()
  endif()

  if(ARGC GREATER 3)
    string(REGEX REPLACE "[ \t\r\n]+" " " flat_err "${err}")
    string(REGEX REPLACE "[ \t\r\n]+" " " flat_want "${ARGV3}")
    if(NOT flat_err MATCHES "${flat_want}")
      message(SEND_ERROR
        "httparse-spec: ${what}: case '${case}' failed, but not with the "
        "diagnostic it should have. Expected text containing:\n  ${flat_want}\n"
        "--- stderr ---\n${flat_err}")
    endif()
  endif()
endfunction()

# spec_check_equal must accept what is equal and reject what is not. Without the
# second of these, every positive assertion in every specification is decoration.
must_exit(check-equal-accepts-equal          zero    "spec_check_equal accepts equal values")
must_exit(check-equal-rejects-unequal        nonzero
  "spec_check_equal rejects unequal values"
  "expected .ta6osx., got .tarm64osx.")
must_exit(check-equal-rejects-empty-vs-value nonzero "spec_check_equal rejects empty against a value")

# spec_expect_rejected must accept a correct rejection, and must complain both
# when the child did not fail at all and when it failed for a different reason.
# The last of those is what stops a typo in a case name from reading as a pass.
must_exit(rejected-accepts-correct-rejection   zero    "spec_expect_rejected accepts a correct rejection")
must_exit(rejected-complains-when-child-succeeds nonzero
  "spec_expect_rejected complains when the child exits 0"
  "exited 0 but must be rejected")
must_exit(rejected-complains-on-wrong-message  nonzero
  "spec_expect_rejected complains when the child fails for another reason"
  "failed for the wrong reason")

# CMake wraps message() output at its own width. An assertion that matched
# literally would pass or fail depending on how long an interpolated path
# happened to be, so the flattening must absorb the wrapping.
must_exit(rejected-tolerates-wrapped-message zero "spec_expect_rejected tolerates CMake's line wrapping")

# A specification that failed must not sign off as verified. SEND_ERROR keeps
# executing, so the closing banner is reached either way; the exit status is
# correct but the transcript is what people actually read.
function(must_say case wanted unwanted what)
  execute_process(
    COMMAND "${CMAKE_COMMAND}" "-DHTTPARSE_SPEC_CASE=${case}" -P "${SPEC_SELF}"
    OUTPUT_VARIABLE out ERROR_VARIABLE err RESULT_VARIABLE rc)
  set(all "${out}${err}")
  if(NOT wanted STREQUAL "" AND NOT all MATCHES "${wanted}")
    message(SEND_ERROR "httparse-spec: ${what}: expected output containing '${wanted}'.\n${all}")
  endif()
  if(NOT unwanted STREQUAL "" AND all MATCHES "${unwanted}")
    message(SEND_ERROR "httparse-spec: ${what}: output must not contain '${unwanted}'.\n${all}")
  endif()
endfunction()

must_say(banner-after-failure "FAILED 1 assertion" "SomeSubject verified"
  "a failed specification does not sign off as verified")
must_say(banner-after-success "SomeSubject verified" "FAILED"
  "a passing specification still signs off")

message(STATUS "httparse-spec: SpecSupport verified")

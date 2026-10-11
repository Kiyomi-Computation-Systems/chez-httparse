# Specification for cmake/HttparseExpectExit.cmake.
#
# CTest's WILL_FAIL only distinguishes zero from nonzero, so it accepts a crash,
# a missing library, or a failure to launch as proof that an assertion failed.
# This module compares the exact status instead, which means it has to say what
# the legal statuses even are -- and has to tell an out-of-vocabulary status
# apart from a wrong one, because those are different defects. Under Chez
# 10.4.1, `--script` naming a file that does not exist exits 255; reporting
# that as "expected 1, got 255" would send a reader looking for a failed
# assertion that never ran.

cmake_minimum_required(VERSION 3.26)

include("${CMAKE_CURRENT_LIST_DIR}/../../../cmake/HttparseExpectExit.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/SpecSupport.cmake")

set(SPEC_SELF "${CMAKE_CURRENT_LIST_FILE}")

if(DEFINED HTTPARSE_SPEC_CASE)
  set(c "${HTTPARSE_SPEC_CASE}")

  # httparse_add_test belongs to a project context this script does not
  # have. Stubbing it is what lets the registration function's own validation be
  # exercised: without this case, deleting the classify call from the registrar
  # would leave every assertion below green.
  function(httparse_add_test)
  endfunction()

  if(c STREQUAL "registration-rejects-undeclared-status")
    httparse_add_exit_code_test(
      NAME httparse.harness.example.chez.source
      COMMAND "/bin/true"
      EXPECT_EXIT 7
      TIMEOUT 10)
  elseif(c STREQUAL "registration-rejects-non-numeric-status")
    httparse_add_exit_code_test(
      NAME httparse.harness.example.chez.source
      COMMAND "/bin/true"
      EXPECT_EXIT "one"
      TIMEOUT 10)
  elseif(c STREQUAL "registration-requires-expectation")
    httparse_add_exit_code_test(
      NAME httparse.harness.example.chez.source
      COMMAND "/bin/true"
      TIMEOUT 10)
  else()
    message(FATAL_ERROR "httparse-spec: unknown case '${c}'")
  endif()

  message(FATAL_ERROR "httparse-spec: case '${c}' was accepted but must be rejected")
endif()

# --- Driver ----------------------------------------------------------------

# The vocabulary is the whole point of the module; assert it explicitly so a
# silent widening is visible here rather than in a test that starts passing.
spec_check_equal("${HTTPARSE_EXIT_STATUS_VOCABULARY}" "0;1;2;3"
  "declared exit-status vocabulary")

foreach(code 0 1 2 3)
  httparse_expect_exit_classify("${code}" status message)
  spec_check_equal("${status}" "ok" "classify accepts declared status ${code}")
endforeach()

httparse_expect_exit_classify("7" status message)
spec_check_equal("${status}" "not-declared" "classify rejects 7")

set(status "seed")
httparse_expect_exit_classify("77" status message)
spec_check_equal("${status}" "not-declared" "classify rejects 77")

httparse_expect_exit_classify("one" status message)
spec_check_equal("${status}" "not-a-number" "classify rejects a non-number")

# Seeded, so a classifier that never writes its output is distinguishable from
# one that writes the right thing. An assertion against an unseeded variable is
# satisfied by a function that does nothing at all.
set(message "seed")
httparse_expect_exit_classify("0" status message)
spec_check_equal("${message}" "" "classify clears the message on success")

httparse_expect_exit_verdict("1" "1" verdict message)
spec_check_equal("${verdict}" "ok" "verdict: exact match")

httparse_expect_exit_verdict("1" "2" verdict message)
spec_check_equal("${verdict}" "mismatch" "verdict: a declared but wrong status is a mismatch")

# 255 is out of vocabulary, the same as a crash below. It must not be
# reported as a wrong assertion outcome.
httparse_expect_exit_verdict("1" "255" verdict message)
spec_check_equal("${verdict}" "out-of-vocabulary" "verdict: 255 is out of vocabulary")

set(verdict "seed")
httparse_expect_exit_verdict("0" "139" verdict message)
spec_check_equal("${verdict}" "out-of-vocabulary" "verdict: a crash is out of vocabulary")

# execute_process reports a failure to run at all as a non-numeric result.
httparse_expect_exit_verdict("0" "Process terminated due to timeout" verdict message)
spec_check_equal("${verdict}" "did-not-run" "verdict: a non-numeric result did not run")

set(message "seed")
httparse_expect_exit_verdict("2" "2" verdict message)
spec_check_equal("${message}" "" "verdict clears the message on success")

# --- Registration (httparse_add_exit_code_test): WORKING_DIRECTORY -----
#
# httparse_add_test belongs to a project context this script does not
# have, so it is stubbed here too -- but every case above that reaches
# httparse_add_exit_code_test does so only to prove a rejection, and each
# one is rejected before the registrar at the bottom of that function is ever
# called (the stub inside the HTTPARSE_SPEC_CASE block above stands aside
# for exactly that reason). Nothing here previously drove a valid registration
# through to that final call, so the WORKING_DIRECTORY-forwarding block in
# HttparseExpectExit.cmake -- the same conditional-forwarding shape
# httparse_add_scheme_lane uses, and CMP0174-motivated for the same reason
# -- was exercised by nothing at all. This stub records what it was handed,
# the same two ways HttparseSchemeLaneSpec.cmake does: the value
# cmake_parse_arguments extracted, and whether the literal "WORKING_DIRECTORY"
# keyword appears anywhere in the raw arguments, since a keyword present with
# an empty value and a keyword never given can both leave the parsed variable
# unset at this project's 3.26 floor.
function(httparse_add_test)
  cmake_parse_arguments(PARSE_ARGV 0 s "" "NAME;TIMEOUT;WORKING_DIRECTORY" "COMMAND;LABELS;ENVIRONMENT")
  set_property(GLOBAL PROPERTY HTTPARSE_SPEC_WORKING_DIRECTORY "${s_WORKING_DIRECTORY}")
  list(FIND ARGN "WORKING_DIRECTORY" wd_at)
  if(wd_at EQUAL -1)
    set_property(GLOBAL PROPERTY HTTPARSE_SPEC_WORKING_DIRECTORY_KEYWORD "absent")
  else()
    set_property(GLOBAL PROPERTY HTTPARSE_SPEC_WORKING_DIRECTORY_KEYWORD "present")
  endif()
endfunction()

set_property(GLOBAL PROPERTY HTTPARSE_SPEC_WORKING_DIRECTORY "sentinel")
set_property(GLOBAL PROPERTY HTTPARSE_SPEC_WORKING_DIRECTORY_KEYWORD "sentinel")
httparse_add_exit_code_test(
  NAME httparse.harness.example.chez.source
  COMMAND "/bin/true"
  EXPECT_EXIT 1
  TIMEOUT 10
  WORKING_DIRECTORY "/h/run")
get_property(wd GLOBAL PROPERTY HTTPARSE_SPEC_WORKING_DIRECTORY)
spec_check_equal("${wd}" "/h/run"
  "a WORKING_DIRECTORY given to the registrar is forwarded with its value")
get_property(wd_keyword GLOBAL PROPERTY HTTPARSE_SPEC_WORKING_DIRECTORY_KEYWORD)
spec_check_equal("${wd_keyword}" "present"
  "the WORKING_DIRECTORY keyword reaches the registrar when the caller gave one")

set_property(GLOBAL PROPERTY HTTPARSE_SPEC_WORKING_DIRECTORY "sentinel")
set_property(GLOBAL PROPERTY HTTPARSE_SPEC_WORKING_DIRECTORY_KEYWORD "sentinel")
httparse_add_exit_code_test(
  NAME httparse.harness.example.chez.source
  COMMAND "/bin/true"
  EXPECT_EXIT 1
  TIMEOUT 10)
get_property(wd_keyword GLOBAL PROPERTY HTTPARSE_SPEC_WORKING_DIRECTORY_KEYWORD)
spec_check_equal("${wd_keyword}" "absent"
  "no WORKING_DIRECTORY keyword reaches the registrar when the caller did not give one")

spec_expect_all_rejected("${SPEC_SELF}"
  "registration-rejects-undeclared-status|is not a declared harness status"
  "registration-rejects-non-numeric-status|must be a whole number"
  "registration-requires-expectation|must declare EXPECT_EXIT")

spec_finish("HttparseExpectExit")

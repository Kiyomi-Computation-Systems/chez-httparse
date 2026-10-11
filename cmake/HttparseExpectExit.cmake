# Assert the exact exit status of a command.
#
# WHY NOT WILL_FAIL
#
# CTest's WILL_FAIL only distinguishes zero from nonzero. The harness gives each
# status a distinct meaning (0 passed, 1 an assertion failed, 2 a harness or
# registration error, 3 a provenance refusal), so a test proving "an assertion
# failed" must compare 1 exactly: under WILL_FAIL a segfault, a missing
# library, or a launcher that never started would all count as proof, and the
# test would keep passing after the thing it was written to check stopped
# happening.
#
# WHY AN OUT-OF-VOCABULARY STATUS IS ITS OWN VERDICT
#
# A status outside the declared set means the process died before the harness
# could report -- an uncaught top-level raise, a crash, or a program file the
# runtime could not find (Chez 10.4.1 exits 255 for the last). Reporting that
# as "expected 1, got 255" sends the reader looking for a failed assertion
# that never ran. Naming it separately points at the real defect.
#
# This file is both the module and the runner. Included, it defines functions.
# Run with `cmake -P` and -DHTTPARSE_EXPECT_COMMAND=..., it performs the
# check. One file means the registration and the execution cannot drift apart.

include_guard(GLOBAL)

# Run under -P, this file inherits no project policies, and the functions
# below record theirs where they are defined -- so the floor comes before
# them. Included, it sets the version the project already declared.
cmake_policy(VERSION 3.26)

# Every status the harness is allowed to produce. 3 is lane provenance: the
# run could not confirm it executed the intended text. 77 is deliberately
# absent: httparse has no optional lane to declare inapplicable.
set(HTTPARSE_EXIT_STATUS_VOCABULARY 0 1 2 3)

# --- Functional core -------------------------------------------------------

# httparse_expect_exit_classify(<code> <out_status> <out_message>)
#
# Decide whether a code is a legal *expectation*. Status is `ok`,
# `not-a-number`, or `not-declared`. The message omits the "httparse: "
# prefix; whoever raises it adds that.
function(httparse_expect_exit_classify code out_status out_message)
  set(${out_message} "" PARENT_SCOPE)

  if(NOT code MATCHES "^[0-9]+$")
    set(${out_status} "not-a-number" PARENT_SCOPE)
    set(${out_message}
      "EXPECT_EXIT must be a whole number, got '${code}'."
      PARENT_SCOPE)
    return()
  endif()

  if(NOT code IN_LIST HTTPARSE_EXIT_STATUS_VOCABULARY)
    set(${out_status} "not-declared" PARENT_SCOPE)
    set(${out_message}
      "EXPECT_EXIT ${code} is not a declared harness status. The harness produces only ${HTTPARSE_EXIT_STATUS_VOCABULARY}, so expecting anything else asserts something that cannot happen and would pass or fail for reasons unrelated to the test."
      PARENT_SCOPE)
    return()
  endif()

  set(${out_status} "ok" PARENT_SCOPE)
endfunction()

# httparse_expect_exit_verdict(<expected> <actual> <out_status> <out_message>)
#
# Judge an observed status against an expectation. Status is `ok`,
# `did-not-run`, `out-of-vocabulary`, or `mismatch`.
function(httparse_expect_exit_verdict expected actual out_status out_message)
  set(${out_message} "" PARENT_SCOPE)

  # execute_process reports a failure to run at all -- a timeout, a binary that
  # is not executable -- as a non-numeric RESULT_VARIABLE.
  if(NOT actual MATCHES "^[0-9]+$")
    set(${out_status} "did-not-run" PARENT_SCOPE)
    set(${out_message}
      "the command did not run to completion (${actual}). It either failed to launch or was killed before it could report."
      PARENT_SCOPE)
    return()
  endif()

  # Checked before the vocabulary test: an expectation is always in the
  # vocabulary, so a match is a match.
  if(actual EQUAL expected)
    set(${out_status} "ok" PARENT_SCOPE)
    return()
  endif()

  if(NOT actual IN_LIST HTTPARSE_EXIT_STATUS_VOCABULARY)
    set(${out_status} "out-of-vocabulary" PARENT_SCOPE)
    set(${out_message}
      "exit status ${actual} is not in the declared vocabulary (${HTTPARSE_EXIT_STATUS_VOCABULARY}); ${expected} was expected. The process died before the harness could report: an uncaught top-level raise, a crash, or a program file the runtime could not find. That is a different defect from a failed assertion."
      PARENT_SCOPE)
    return()
  endif()

  set(${out_status} "mismatch" PARENT_SCOPE)
  set(${out_message} "expected exit ${expected}, got ${actual}." PARENT_SCOPE)
endfunction()

# --- Imperative shell ------------------------------------------------------

# httparse_add_exit_code_test(NAME <name> COMMAND <cmd>... EXPECT_EXIT <code>
#                                 TIMEOUT <seconds> [WORKING_DIRECTORY <dir>]
#                                 [LABELS ...] [ENVIRONMENT ...])
#
# The command is packed with `|` rather than passed as a list because it has to
# survive a trip through -D into a child cmake, where a `;` would be re-read as
# a list separator. No path in this project contains `|`.
function(httparse_add_exit_code_test)
  cmake_parse_arguments(PARSE_ARGV 0 arg ""
    "NAME;EXPECT_EXIT;TIMEOUT;WORKING_DIRECTORY" "COMMAND;LABELS;ENVIRONMENT")

  if(arg_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR
      "httparse: unexpected arguments to httparse_add_exit_code_test: ${arg_UNPARSED_ARGUMENTS}")
  endif()
  if(NOT arg_NAME)
    message(FATAL_ERROR "httparse: NAME is required for httparse_add_exit_code_test.")
  endif()
  if(NOT arg_COMMAND)
    message(FATAL_ERROR "httparse: COMMAND is required for '${arg_NAME}'.")
  endif()
  if(NOT DEFINED arg_EXPECT_EXIT)
    message(FATAL_ERROR
      "httparse: '${arg_NAME}' must declare EXPECT_EXIT. A test registered "
      "through this helper exists to assert one exact status; without it there "
      "is nothing to compare and the registration should use httparse_add_test.")
  endif()

  httparse_expect_exit_classify("${arg_EXPECT_EXIT}" status message)
  if(NOT status STREQUAL "ok")
    message(FATAL_ERROR "httparse: ${message} (test '${arg_NAME}')")
  endif()

  string(JOIN "|" packed ${arg_COMMAND})

  # Forward WORKING_DIRECTORY only when the caller gave one, rather than
  # forwarding an empty value unconditionally. The keyword followed by an
  # empty string is what makes cmake_parse_arguments() print a CMP0174
  # developer warning on every configure that reaches this call; that policy
  # does not exist at this project's declared 3.26 floor (it arrives in
  # 3.31), so setting it would be a no-op here. Omitting the keyword when
  # there is nothing to say is version-independent instead.
  set(working_directory_args "")
  if(arg_WORKING_DIRECTORY)
    set(working_directory_args WORKING_DIRECTORY "${arg_WORKING_DIRECTORY}")
  endif()

  httparse_add_test(
    NAME "${arg_NAME}"
    COMMAND "${CMAKE_COMMAND}"
            "-DHTTPARSE_EXPECT_EXIT=${arg_EXPECT_EXIT}"
            "-DHTTPARSE_EXPECT_COMMAND=${packed}"
            -P "${CMAKE_CURRENT_FUNCTION_LIST_FILE}"
    TIMEOUT "${arg_TIMEOUT}"
    LABELS ${arg_LABELS}
    ${working_directory_args}
    ENVIRONMENT ${arg_ENVIRONMENT})
endfunction()

# --- Runner ----------------------------------------------------------------
#
# Reached only under `cmake -P`. The child's output is echoed unconditionally:
# when the status is wrong, the inner run's own diagnostics are the only thing
# that says why, and CTest shows this process's output, not the grandchild's.

if(DEFINED HTTPARSE_EXPECT_COMMAND)
  string(REPLACE "|" ";" _hp_command "${HTTPARSE_EXPECT_COMMAND}")

  execute_process(
    COMMAND ${_hp_command}
    RESULT_VARIABLE _hp_rc
    OUTPUT_VARIABLE _hp_out
    ERROR_VARIABLE _hp_err)

  message(STATUS "httparse: --- command output ---\n${_hp_out}${_hp_err}")

  httparse_expect_exit_verdict(
    "${HTTPARSE_EXPECT_EXIT}" "${_hp_rc}" _hp_verdict _hp_message)

  if(NOT _hp_verdict STREQUAL "ok")
    message(FATAL_ERROR "httparse: ${_hp_message}")
  endif()

  message(STATUS "httparse: exited ${_hp_rc} as expected")
endif()

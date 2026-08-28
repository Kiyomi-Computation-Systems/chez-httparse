# Shared assertions for the CMake-layer specifications.
#
# WHY DIAGNOSTICS ARE FLATTENED BEFORE MATCHING
#
# CMake wraps the text of message() at its own width and indents continuation
# lines. A specification that matches a rejection's diagnostic literally is
# therefore asserting on that wrapping: the same message passes or fails
# depending on how long the interpolated path happened to be. Both the observed
# stderr and the expected fragment are collapsed to single-spaced text before
# comparison, so what is being asserted is the wording, which the module
# controls, rather than the layout, which it does not.

include_guard(GLOBAL)

# WHY FAILURES ARE COUNTED
#
# message(SEND_ERROR) records a failure and keeps going, which is what lets a
# specification report every broken assertion in one run instead of stopping at
# the first. The cost is that execution reaches the end of the file either way,
# so an unconditional closing "verified" banner is printed by a run that failed.
# The exit status is still correct and CTest still goes red, but the transcript
# says the opposite of the truth, and transcripts are what people read. The
# counter exists so spec_finish can tell the two apart.
set_property(GLOBAL PROPERTY HTTPARSE_SPEC_FAILURES 0)

function(spec_record_failure)
  get_property(n GLOBAL PROPERTY HTTPARSE_SPEC_FAILURES)
  math(EXPR n "${n} + 1")
  set_property(GLOBAL PROPERTY HTTPARSE_SPEC_FAILURES "${n}")
endfunction()

# spec_finish(<subject>)
#
# Close a specification. Prints the success banner only when nothing failed.
function(spec_finish subject)
  get_property(n GLOBAL PROPERTY HTTPARSE_SPEC_FAILURES)
  if(n EQUAL 0)
    message(STATUS "httparse-spec: ${subject} verified")
  else()
    message(STATUS "httparse-spec: ${subject} FAILED ${n} assertion(s)")
  endif()
endfunction()

# spec_check_equal(<actual> <expected> <what>)
function(spec_check_equal actual expected what)
  if(NOT actual STREQUAL expected)
    spec_record_failure()
    message(SEND_ERROR "httparse-spec: ${what}: expected '${expected}', got '${actual}'")
  endif()
endfunction()

# spec_flatten(<text> <out_var>)
#
# Collapse every run of whitespace to one space, so wrapped and unwrapped
# renderings of one message compare equal.
function(spec_flatten text out_var)
  string(REGEX REPLACE "[ \t\r\n]+" " " flattened "${text}")
  string(STRIP "${flattened}" flattened)
  set(${out_var} "${flattened}" PARENT_SCOPE)
endfunction()

# spec_expect_rejected(<spec_file> <case> <expected_message>)
#
# Re-invoke the calling specification as a child process with one case selected.
# The child must exit nonzero *and* print the declared diagnostic: a case that
# fails for the wrong reason is not a passing case, and without the message
# check a typo in the case dispatch would look like a successful rejection.
function(spec_expect_rejected spec_file case expected_message)
  execute_process(
    COMMAND "${CMAKE_COMMAND}" "-DHTTPARSE_SPEC_CASE=${case}" -P "${spec_file}"
    RESULT_VARIABLE rc
    OUTPUT_VARIABLE out
    ERROR_VARIABLE err)

  if(rc EQUAL 0)
    spec_record_failure()
    message(SEND_ERROR "httparse-spec: case '${case}' exited 0 but must be rejected")
    return()
  endif()

  spec_flatten("${err}" flat_err)
  spec_flatten("${expected_message}" flat_expected)

  if(NOT flat_err MATCHES "${flat_expected}")
    spec_record_failure()
    message(SEND_ERROR
      "httparse-spec: case '${case}' failed for the wrong reason. "
      "Expected a diagnostic containing:\n  ${flat_expected}\n"
      "--- stderr ---\n${flat_err}")
  endif()
endfunction()

# spec_expect_all_rejected(<spec_file> <case|message> ...)
function(spec_expect_all_rejected spec_file)
  foreach(entry IN LISTS ARGN)
    string(REPLACE "|" ";" parts "${entry}")
    list(GET parts 0 case)
    list(GET parts 1 expected_message)
    spec_expect_rejected("${spec_file}" "${case}" "${expected_message}")
  endforeach()
endfunction()

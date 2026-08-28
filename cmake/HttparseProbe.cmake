# Read key=value fields out of a runtime probe's output.
#
# Every runtime httparse supports is interrogated by running a small script
# that prints `key=value` lines. Reading those lines back is a quieter hazard
# than it looks. `string(REGEX MATCH)` reports success nowhere: it sets
# CMAKE_MATCH_1 on a hit and leaves the previous regex's captures untouched on a
# miss. Code of the shape
#
#     string(REGEX MATCH "machine-type=([^\n]*)" _ "${output}")
#     set(MACHINE "${CMAKE_MATCH_1}")
#
# therefore yields a machine type belonging to some earlier question when the
# field is absent, and configuration continues with a plausible wrong answer.
# Both accessors here fail loudly or return nothing; neither can return stale
# data.
#
# Matching is anchored to the start of a line, so a request for `version` is not
# satisfied by a `full-version` line -- which, on Chez, would return the whole
# banner and look almost right.

include_guard(GLOBAL)

# httparse_probe_normalize(<output> <out_var>)
#
# Strip carriage returns so a child process on Windows does not yield values
# with a trailing \r that compare unequal to everything.
function(httparse_probe_normalize output out_var)
  string(REPLACE "\r\n" "\n" normalized "${output}")
  string(REPLACE "\r" "\n" normalized "${normalized}")
  set(${out_var} "${normalized}" PARENT_SCOPE)
endfunction()

# httparse_probe_field(<output> <key> <out_var> <context>)
#
# Required field. A missing or empty value is fatal, and the message names both
# the field and who was asked, because by the time this fails the reader has
# usually forgotten which of several probes is being parsed.
function(httparse_probe_field output key out_var context)
  httparse_probe_normalize("${output}" normalized)

  if(NOT normalized MATCHES "(^|\n)${key}=([^\n]*)")
    message(FATAL_ERROR
      "httparse: ${context} produced no '${key}' field. This usually means "
      "the binary is not the runtime it was taken for.\n"
      "--- probe output ---\n${output}\n--- end ---")
  endif()
  set(value "${CMAKE_MATCH_2}")

  if(value STREQUAL "")
    message(FATAL_ERROR
      "httparse: ${context} reported an empty '${key}' field.\n"
      "--- probe output ---\n${output}\n--- end ---")
  endif()

  set(${out_var} "${value}" PARENT_SCOPE)
endfunction()

# httparse_probe_field_optional(<output> <key> <out_var>)
#
# Optional field: absent yields the empty string. The explicit clear is the
# whole point -- without it the caller would read whatever the last regex in
# scope happened to capture.
function(httparse_probe_field_optional output key out_var)
  httparse_probe_normalize("${output}" normalized)

  if(normalized MATCHES "(^|\n)${key}=([^\n]*)")
    set(${out_var} "${CMAKE_MATCH_2}" PARENT_SCOPE)
  else()
    set(${out_var} "" PARENT_SCOPE)
  endif()
endfunction()

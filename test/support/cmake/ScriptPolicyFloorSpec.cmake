# Specification: every script the build runs with `cmake -P` declares the
# project's policy floor before it does anything else.
#
# A script run with -P does not inherit the project's cmake_minimum_required.
# Its policies are whatever that CMake defaults to in script mode, and CMake 3
# leaves a policy unset there unless the script asks. CMake 4 removed the OLD
# behaviour of every policy older than 3.5, so the same script behaves
# differently under the two. CorpusProvenanceSpec shipped that way: its
# `if(NOT ... IN_LIST ...)` needs CMP0057, it passed on every CMake 4 machine
# that ran it, and the Linux runner's CMake 3 read it as a syntax error the
# first time CI got that far.
#
# RUNNING THE SCRIPTS CANNOT CATCH THIS ON A CMAKE 4 MACHINE, because the
# behaviour it would need to see does not exist there. So the floor is checked
# as text: the first command, after an optional include_guard, must be
# cmake_minimum_required or cmake_policy at the VERSION the top-level
# CMakeLists.txt declares. First, because a function records its policies
# where it is defined, so a floor set after an include() leaves the included
# functions without it.
#
# WHICH SCRIPTS: every path test/CMakeLists.txt hands to -P, every script the
# Makefile hands to -P, and every module that runs itself under -P through
# CMAKE_CURRENT_FUNCTION_LIST_FILE. The extraction is the part that fails
# silently, by matching less than it should, so it is held to an invariant it
# did not produce: every *Spec.cmake in this directory is registered under -P,
# and each source must yield at least one script.
#
# A script that opens with a multi-line bracket comment is read as starting
# with that comment's text and refused. That is a loud false alarm rather
# than a silent pass, and no script here does it.

cmake_minimum_required(VERSION 3.26)

include("${CMAKE_CURRENT_LIST_DIR}/SpecSupport.cmake")

set(SPEC_SELF "${CMAKE_CURRENT_LIST_FILE}")

get_filename_component(_floor_root "${CMAKE_CURRENT_LIST_DIR}/../../.." ABSOLUTE)

# --- The audit, as a function of text --------------------------------------
#
# floor_audit_script(<text> <floor> <label> <out-findings>)
#
# Findings are computed from a script's text alone, which is what lets the
# witness cases below drive this same code with synthetic scripts.
function(floor_audit_script text floor label out_findings)
  # One element per line. Semicolons would split a line in two, and nothing
  # this reads depends on them.
  string(REPLACE ";" "," text "${text}")
  string(REPLACE "\n" ";" lines "${text}")

  set(first "")
  foreach(line IN LISTS lines)
    string(STRIP "${line}" line)
    if(line STREQUAL "" OR line MATCHES "^#")
      continue()
    endif()
    if(first STREQUAL "" AND line MATCHES "^include_guard\\(")
      set(first "include_guard")
      continue()
    endif()
    set(first "${line}")
    break()
  endforeach()

  string(REPLACE "." "\\." floor_re "${floor}")
  set(findings "")
  if(NOT first MATCHES "^(cmake_minimum_required|cmake_policy)\\(VERSION ${floor_re}\\)$")
    if(first STREQUAL "" OR first STREQUAL "include_guard")
      set(first "nothing")
    endif()
    list(APPEND findings
         "${label}: runs under cmake -P, but its first command is '${first}', not cmake_minimum_required(VERSION ${floor}) or cmake_policy(VERSION ${floor})")
  endif()
  set(${out_findings} "${findings}" PARENT_SCOPE)
endfunction()

# --- Witness cases ---------------------------------------------------------
#
# Driven as child processes by the driver below. Each feeds the audit a
# synthetic script that must be rejected; without these, an audit that
# accepted everything would leave this lane green.
if(DEFINED HTTPARSE_SPEC_CASE)
  set(c "${HTTPARSE_SPEC_CASE}")

  if(c STREQUAL "rejects-a-script-with-no-floor")
    set(script "# a spec\ninclude_guard(GLOBAL)\ninclude(SpecSupport.cmake)\n")
  elseif(c STREQUAL "rejects-a-floor-after-another-command")
    set(script "include_guard(GLOBAL)\ninclude(SpecSupport.cmake)\ncmake_minimum_required(VERSION 3.26)\n")
  elseif(c STREQUAL "rejects-a-floor-at-another-version")
    set(script "cmake_minimum_required(VERSION 3.5)\n")
  elseif(c STREQUAL "rejects-an-empty-script")
    set(script "# nothing but comments\n\n")
  else()
    message(FATAL_ERROR "httparse-spec: unknown case '${c}'")
  endif()

  floor_audit_script("${script}" "3.26" "synthetic script" findings)
  if(findings)
    list(JOIN findings "\n  " joined)
    message(FATAL_ERROR "httparse-spec: script policy floor audit rejected this case:\n  ${joined}")
  endif()
  message(FATAL_ERROR "httparse-spec: case '${c}' was accepted but must be rejected")
endif()

# --- Driver ----------------------------------------------------------------

# The floor the project declares, read rather than restated.
file(READ "${_floor_root}/CMakeLists.txt" _floor_top)
string(REGEX MATCH "cmake_minimum_required\\(VERSION ([0-9.]+)" _floor_match "${_floor_top}")
set(_floor "${CMAKE_MATCH_1}")
if(_floor STREQUAL "")
  spec_record_failure()
  message(SEND_ERROR
    "httparse-spec: the top-level CMakeLists.txt declares no cmake_minimum_required "
    "VERSION, so there is no floor to hold the scripts to.")
endif()

# The two shapes a script must be accepted in: a floor first, and a floor
# after include_guard, each behind comments and blank lines.
floor_audit_script("# c\n\ncmake_minimum_required(VERSION 3.26)\ninclude(x)\n" "3.26" "accepted" _ok1)
floor_audit_script("include_guard(GLOBAL)\n# c\ncmake_policy(VERSION 3.26)\n" "3.26" "accepted" _ok2)
spec_check_equal("${_ok1}" "" "a floor that comes first is accepted")
spec_check_equal("${_ok2}" "" "a floor that follows include_guard is accepted")

set(_floor_scripts "")

# (1) Every path test/CMakeLists.txt hands to -P.
file(READ "${_floor_root}/test/CMakeLists.txt" _floor_tests)
string(REGEX MATCHALL
       "-P[ \t\r\n]+\"[$][{]CMAKE_CURRENT_LIST_DIR[}]/support/cmake/[A-Za-z0-9_]+\\.cmake\""
       _floor_registered "${_floor_tests}")
foreach(_m IN LISTS _floor_registered)
  string(REGEX REPLACE ".*/support/cmake/([A-Za-z0-9_]+\\.cmake)\"$" "test/support/cmake/\\1" _rel "${_m}")
  list(APPEND _floor_scripts "${_rel}")
endforeach()
set(_floor_from_tests ${_floor_scripts})

# (2) Every script the Makefile hands to -P.
file(READ "${_floor_root}/Makefile" _floor_make)
string(REGEX MATCHALL "-P[ \t]+[A-Za-z0-9_./-]+\\.cmake" _floor_make_found "${_floor_make}")
set(_floor_from_make "")
foreach(_m IN LISTS _floor_make_found)
  string(REGEX REPLACE "^-P[ \t]+" "" _rel "${_m}")
  list(APPEND _floor_from_make "${_rel}")
endforeach()

# (3) Every module that runs itself under -P.
file(GLOB _floor_modules RELATIVE "${_floor_root}" "${_floor_root}/cmake/*.cmake")
set(_floor_from_self "")
foreach(_rel IN LISTS _floor_modules)
  file(READ "${_floor_root}/${_rel}" _t)
  if(_t MATCHES "-P[ \t\r\n]+\"[$][{]CMAKE_CURRENT_FUNCTION_LIST_FILE[}]\"")
    list(APPEND _floor_from_self "${_rel}")
  endif()
endforeach()

foreach(_source IN ITEMS tests make self)
  if(NOT _floor_from_${_source})
    spec_record_failure()
    message(SEND_ERROR
      "httparse-spec: no -P script was found from source '${_source}', so the "
      "recogniser no longer describes the tree. Fix the extraction before "
      "trusting this lane.")
  endif()
endforeach()

list(APPEND _floor_scripts ${_floor_from_make} ${_floor_from_self})
list(REMOVE_DUPLICATES _floor_scripts)

# The invariant the extraction did not produce: every specification in this
# directory is run under -P, so every one must have been found.
file(GLOB _floor_specs RELATIVE "${_floor_root}" "${_floor_root}/test/support/cmake/*Spec.cmake")
foreach(_spec IN LISTS _floor_specs)
  if(NOT _spec IN_LIST _floor_scripts)
    spec_record_failure()
    message(SEND_ERROR
      "httparse-spec: ${_spec} is a specification but was not found among the "
      "scripts test/CMakeLists.txt runs with -P. Either it is not registered, or "
      "the recogniser misses its registration.")
  endif()
endforeach()

list(LENGTH _floor_scripts _floor_count)
foreach(_rel IN LISTS _floor_scripts)
  file(READ "${_floor_root}/${_rel}" _t)
  floor_audit_script("${_t}" "${_floor}" "${_rel}" _findings)
  foreach(_f IN LISTS _findings)
    spec_record_failure()
    message(SEND_ERROR "httparse-spec: ${_f}")
  endforeach()
endforeach()

spec_expect_all_rejected("${SPEC_SELF}"
  "rejects-a-script-with-no-floor|its first command is 'include\\(SpecSupport.cmake\\)'"
  "rejects-a-floor-after-another-command|its first command is 'include\\(SpecSupport.cmake\\)'"
  "rejects-a-floor-at-another-version|cmake_minimum_required\\(VERSION 3.5\\)', not"
  "rejects-an-empty-script|its first command is 'nothing'")

spec_finish("script policy floor (${_floor_count} scripts held to VERSION ${_floor})")

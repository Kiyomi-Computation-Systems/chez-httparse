# Machinery for proving that the specifications are not vacuous.
#
# A specification that passes tells you nothing on its own: it might be checking
# the code, or it might be checking nothing at all. The only way to know is to
# break the code deliberately and confirm the specification notices. This file
# is that check, made reproducible and runnable in CI rather than performed once
# by hand and written up afterwards.
#
# WHY THE SOURCE TREE IS NEVER TOUCHED
#
# The obvious implementation edits a module in place, runs its specification,
# and edits it back. That leaves the repository corrupt if the run is
# interrupted -- by a timeout, a signal, or a failing assertion that aborts the
# script -- and the corruption is a subtly wrong module rather than an obvious
# one. Everything here operates on a staged copy inside the build tree instead.
# The source tree is only ever read.
#
# WHY THE BASELINE IS CHECKED FIRST
#
# "The specification failed after I broke the code" only means something if the
# specification passed before. If the staging is wrong -- a missed file, a
# broken relative include -- every specification fails for that reason and every
# mutation looks caught, which is the exact false confidence this file exists to
# eliminate. The baseline run is therefore a hard precondition, not a courtesy.

include_guard(GLOBAL)

set(_hp_mutation_count 0)

# Which trees are copied into the scratch tree. The default is what the
# CMake-layer suite needs; the Scheme suite adds the harness and the launchers,
# whose library roots and program paths resolve against their relative layout
# and would break if the tree were flattened.
set(HTTPARSE_MUTATION_STAGE_DIRS "cmake" "test/support/cmake")

# What decides whether a mutation was caught. Empty keeps the original
# behaviour: run the named specification under `cmake -P` inside the stage. The
# Scheme suite replaces it with a real execution lane, because a Scheme defect
# is only visible to something that runs Scheme.
set(HTTPARSE_MUTATION_VERIFY_COMMAND "")

# Where the verify command runs. Empty means the stage directory, which is what
# every pass wants. The one caller that ever set it was the include-era
# working-directory matrix, which needed a pass per launch directory because
# what it asserted was that the launch directory does not matter -- a claim no
# command run from one fixed place can make. That matrix retired with the
# include mechanism (upstream decision 0006); the hook is kept for the next caller that
# has to run a verify command from somewhere other than the stage.
set(HTTPARSE_MUTATION_VERIFY_WORKING_DIRECTORY "")

# httparse_mutation(FILE <repo-relative> SPEC <spec basename> LABEL <text>
#                       FIND <text> REPLACE <text> [SITES <n>]
#                       [EXPECT_SURVIVES <reason>]
#                       [EXPECT_STATUS <code>] [EXPECT_OUTPUT_MATCHES <regex>])
#
# Declare one mutation. FIND and REPLACE are literal text, not regexes; pass
# them as bracket arguments so quotes, backslashes, and ${...} survive intact.
#
# SITES defaults to 1 and is asserted exactly: a pattern that stops matching
# because the module was refactored must be a loud failure, not a silently
# skipped mutation. That is the failure mode that would quietly hollow this
# suite out over time.
#
# EXPECT_SURVIVES inverts the expectation for a mutation the specifications
# knowingly cannot catch, and requires a reason. Such a mutation must still
# survive: if one starts being caught, the recorded limitation is stale and the
# suite says so rather than letting the documentation drift.
#
# A nonzero result from the verify command means only that it noticed
# *something*; by itself that is not evidence it noticed the decision this
# mutation names, and a mutation can be "caught" by an unrelated crash just as
# easily as by the refusal it is meant to prove. EXPECT_STATUS and
# EXPECT_OUTPUT_MATCHES narrow "caught" to "caught for this reason": when
# either is given, a nonzero result whose exit code or combined stdout+stderr
# does not also satisfy the declared expectation is reported separately, as
# caught for the wrong reason, and counted the same as UNCAUGHT. Neither is
# consulted when the verify command exits 0 -- that is simply not caught, the
# ordinary way. Apply them only where the wrong-reason risk is real; most
# mutations need neither.
#
# EXPECT_SURVIVES is mutually exclusive with EXPECT_STATUS and
# EXPECT_OUTPUT_MATCHES: a declared survivor is judged in
# httparse_mutation_run only by whether the verify command exited zero, so
# the other two would be parsed, stored, and never consulted -- silently inert
# rather than enforced. Declaring both is refused rather than left to quietly
# mean less than it says.
function(httparse_mutation)
  cmake_parse_arguments(PARSE_ARGV 0 arg "" "FILE;SPEC;LABEL;FIND;REPLACE;SITES;EXPECT_SURVIVES;EXPECT_STATUS;EXPECT_OUTPUT_MATCHES" "")

  if(arg_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR "httparse-mutation: unexpected arguments: ${arg_UNPARSED_ARGUMENTS}")
  endif()
  foreach(required FILE SPEC LABEL FIND REPLACE)
    if(NOT DEFINED arg_${required})
      message(FATAL_ERROR "httparse-mutation: ${required} is required (label '${arg_LABEL}').")
    endif()
  endforeach()
  if(NOT DEFINED arg_SITES)
    set(arg_SITES 1)
  endif()

  # DEFINED, not a truthiness or STREQUAL test on the raw arg_* variable: an
  # undefined cmake_parse_arguments output used bare inside if() is treated as
  # the literal string "arg_EXPECT_SURVIVES" rather than as empty, so a
  # STREQUAL "" test on it would silently invert. DEFINED has no such trap.
  if(DEFINED arg_EXPECT_SURVIVES AND (DEFINED arg_EXPECT_STATUS OR DEFINED arg_EXPECT_OUTPUT_MATCHES))
    message(FATAL_ERROR
      "httparse-mutation: '${arg_LABEL}' declares EXPECT_SURVIVES together "
      "with EXPECT_STATUS or EXPECT_OUTPUT_MATCHES. A declared survivor is "
      "judged only by whether the verify command exits zero, so the other two "
      "would be silently unconsulted rather than enforced. Declare one or the "
      "other.")
  endif()

  math(EXPR next "${_hp_mutation_count} + 1")
  set(_hp_mutation_count "${next}" PARENT_SCOPE)

  set_property(GLOBAL PROPERTY _hp_mut_${next}_file "${arg_FILE}")
  set_property(GLOBAL PROPERTY _hp_mut_${next}_spec "${arg_SPEC}")
  set_property(GLOBAL PROPERTY _hp_mut_${next}_label "${arg_LABEL}")
  set_property(GLOBAL PROPERTY _hp_mut_${next}_find "${arg_FIND}")
  set_property(GLOBAL PROPERTY _hp_mut_${next}_replace "${arg_REPLACE}")
  set_property(GLOBAL PROPERTY _hp_mut_${next}_sites "${arg_SITES}")
  set_property(GLOBAL PROPERTY _hp_mut_${next}_survives "${arg_EXPECT_SURVIVES}")
  set_property(GLOBAL PROPERTY _hp_mut_${next}_expect_status "${arg_EXPECT_STATUS}")
  set_property(GLOBAL PROPERTY _hp_mut_${next}_expect_output_matches "${arg_EXPECT_OUTPUT_MATCHES}")
endfunction()

# httparse_mutation_stage(<source_root> <stage_dir>)
#
# Copy every declared tree into a scratch tree, preserving the relative layout
# the specifications' includes and the libraries' resolution depend on.
function(httparse_mutation_stage source_root stage_dir)
  file(REMOVE_RECURSE "${stage_dir}")

  foreach(rel IN LISTS HTTPARSE_MUTATION_STAGE_DIRS)
    file(MAKE_DIRECTORY "${stage_dir}/${rel}")
    file(GLOB entries "${source_root}/${rel}/*")
    if(NOT entries)
      message(FATAL_ERROR
        "httparse-mutation: staging found nothing under '${rel}' in "
        "'${source_root}'. Refusing to run: an empty stage would make every "
        "mutation look caught, which is the exact false confidence this file "
        "exists to eliminate.")
    endif()
    # Directories are copied whole, so a tree such as the harness keeps the
    # layout its library roots resolve against.
    file(COPY ${entries} DESTINATION "${stage_dir}/${rel}")
  endforeach()
endfunction()

# httparse_mutation_run_spec(<stage_dir> <spec> <out_rc> <out_output>)
#
# A non-numeric result -- a command that could not be launched at all -- would
# compare unequal to 0 and count as caught. That is safe only because the
# baseline run happens first: if the verify command cannot run, the baseline
# fails and nothing below is trusted.
#
# out_output is stdout and stderr concatenated, in that order, with nothing
# else interleaved -- execute_process captures each as a whole, not as an
# interleaved stream, so this is an approximation of what a terminal would have
# shown, not a byte-accurate transcript. Good enough for EXPECT_OUTPUT_MATCHES,
# which looks for a fixed marker rather than reconstructing ordering.
function(httparse_mutation_run_spec stage_dir spec out_rc out_output)
  if(HTTPARSE_MUTATION_VERIFY_COMMAND)
    set(command ${HTTPARSE_MUTATION_VERIFY_COMMAND})
  else()
    set(command "${CMAKE_COMMAND}" -P "${stage_dir}/test/support/cmake/${spec}")
  endif()

  set(verify_cwd "${stage_dir}")
  if(HTTPARSE_MUTATION_VERIFY_WORKING_DIRECTORY)
    set(verify_cwd "${HTTPARSE_MUTATION_VERIFY_WORKING_DIRECTORY}")
  endif()

  execute_process(
    COMMAND ${command}
    WORKING_DIRECTORY "${verify_cwd}"
    RESULT_VARIABLE rc
    OUTPUT_VARIABLE out
    ERROR_VARIABLE err)
  set(${out_rc} "${rc}" PARENT_SCOPE)
  set(${out_output} "${out}${err}" PARENT_SCOPE)
endfunction()

# httparse_mutation_verdict(<rc> <output> <expect_status> <expect_output_matches>
#                               <out_verdict> <out_reason>)
#
# The decision every mutation is ultimately judged by, and every specification
# in this tree is trusted through: did the verify command's result count as
# catching the mutation, and for the declared reason? Pure -- no
# execute_process, no filesystem -- so it is directly specifiable under
# `cmake -P` rather than only observable through a real staged run.
#
# out_verdict is one of:
#   not-caught    rc was 0. EXPECT_STATUS and EXPECT_OUTPUT_MATCHES narrow what
#                 a *nonzero* result has to look like to count; neither
#                 manufactures a catch out of a zero exit, so they are not even
#                 consulted here.
#   wrong-reason  rc was nonzero, but a declared expectation was not met.
#                 out_reason explains which one.
#   caught        rc was nonzero and every declared expectation was met. With
#                 neither EXPECT_STATUS nor EXPECT_OUTPUT_MATCHES given, this is
#                 the whole rule: any nonzero result is caught, the ordinary,
#                 pre-slice-3 way.
#
# expect_status and expect_output_matches are both tested for "was this
# declared at all" with STREQUAL "", not truthiness: a status is a small
# integer, so 0 would never occur here in practice, but a regex is
# user-supplied text, and a regex that happens to read as CMake-false --
# "0", OFF, NOTFOUND, anything ending "-NOTFOUND" -- is still a regex someone
# declared. Truthiness would silently skip the check it names; STREQUAL does
# not.
function(httparse_mutation_verdict rc output expect_status expect_output_matches out_verdict out_reason)
  set(${out_reason} "" PARENT_SCOPE)

  if(rc EQUAL 0)
    set(${out_verdict} "not-caught" PARENT_SCOPE)
    return()
  endif()

  if(NOT expect_status STREQUAL "" AND NOT rc EQUAL expect_status)
    set(${out_verdict} "wrong-reason" PARENT_SCOPE)
    set(${out_reason}
      "expected the verify command to exit ${expect_status}, got ${rc}"
      PARENT_SCOPE)
    return()
  endif()

  if(NOT expect_output_matches STREQUAL "" AND NOT output MATCHES "${expect_output_matches}")
    set(${out_verdict} "wrong-reason" PARENT_SCOPE)
    set(${out_reason}
      "expected the verify command's output to match '${expect_output_matches}', but it did not"
      PARENT_SCOPE)
    return()
  endif()

  set(${out_verdict} "caught" PARENT_SCOPE)
endfunction()

# httparse_mutation_reset()
#
# Discard the declared mutations so a second set can run under a different
# verify command in the same script. Used by the Scheme suite, which mutates
# several different files in one pass and must start a fresh batch each time
# the file being mutated -- and the specification meant to catch it -- changes.
function(httparse_mutation_reset)
  set(_hp_mutation_count 0 PARENT_SCOPE)
endfunction()

# httparse_mutation_run(<source_root> <stage_dir>)
function(httparse_mutation_run source_root stage_dir)
  httparse_mutation_stage("${source_root}" "${stage_dir}")

  if(_hp_mutation_count EQUAL 0)
    message(FATAL_ERROR
      "httparse-mutation: no mutations declared. An empty suite passes "
      "trivially and would report the specifications as verified.")
  endif()

  # Accumulated in a GLOBAL property, not a variable, because a suite that
  # verifies several decisions through several lanes calls this function once
  # per pass rather than once overall (SchemeMutationSuite.cmake, for one).
  # Both this counter and _hp_mutation_count are written with PARENT_SCOPE,
  # which reaches only the immediate caller -- and different passes call from
  # different scopes: bare script scope for a simple pass, a helper function's
  # own scope for a repeated one (httparse_slice3_launcher_pass, for
  # instance, called once per launcher parse decision). A plain variable would
  # not survive that; a global property has no scope to lose. The caller reads
  # the total back with httparse_mutation_totals once every pass has run.
  get_property(_hp_total_passes GLOBAL PROPERTY HTTPARSE_MUTATION_TOTAL_PASSES)
  if(NOT _hp_total_passes)
    set(_hp_total_passes 0)
  endif()
  math(EXPR _hp_total_passes "${_hp_total_passes} + 1")
  set_property(GLOBAL PROPERTY HTTPARSE_MUTATION_TOTAL_PASSES "${_hp_total_passes}")

  get_property(_hp_total_mutations GLOBAL PROPERTY HTTPARSE_MUTATION_TOTAL_MUTATIONS)
  if(NOT _hp_total_mutations)
    set(_hp_total_mutations 0)
  endif()
  math(EXPR _hp_total_mutations "${_hp_total_mutations} + ${_hp_mutation_count}")
  set_property(GLOBAL PROPERTY HTTPARSE_MUTATION_TOTAL_MUTATIONS "${_hp_total_mutations}")

  # --- Baseline: every specification a mutation targets must pass unmutated ---
  set(specs_used "")
  foreach(i RANGE 1 ${_hp_mutation_count})
    get_property(spec GLOBAL PROPERTY _hp_mut_${i}_spec)
    list(APPEND specs_used "${spec}")
  endforeach()
  list(REMOVE_DUPLICATES specs_used)

  foreach(spec IN LISTS specs_used)
    httparse_mutation_run_spec("${stage_dir}" "${spec}" rc baseline_output)
    if(NOT rc EQUAL 0)
      message(FATAL_ERROR
        "httparse-mutation: baseline failure. '${spec}' does not pass on the "
        "staged, unmutated tree (exit ${rc}), so every mutation against it would "
        "look caught for the wrong reason. Fix the staging or the specification "
        "before trusting any result below.")
    endif()
  endforeach()
  message(STATUS "httparse-mutation: baseline green for ${specs_used}")

  # --- Mutations ---------------------------------------------------------
  set(uncaught 0)
  foreach(i RANGE 1 ${_hp_mutation_count})
    get_property(rel GLOBAL PROPERTY _hp_mut_${i}_file)
    get_property(spec GLOBAL PROPERTY _hp_mut_${i}_spec)
    get_property(label GLOBAL PROPERTY _hp_mut_${i}_label)
    get_property(find GLOBAL PROPERTY _hp_mut_${i}_find)
    get_property(replace GLOBAL PROPERTY _hp_mut_${i}_replace)
    get_property(sites GLOBAL PROPERTY _hp_mut_${i}_sites)
    get_property(survives GLOBAL PROPERTY _hp_mut_${i}_survives)
    get_property(expect_status GLOBAL PROPERTY _hp_mut_${i}_expect_status)
    get_property(expect_output_matches GLOBAL PROPERTY _hp_mut_${i}_expect_output_matches)

    set(pristine_path "${source_root}/${rel}")
    set(staged_path "${stage_dir}/${rel}")
    if(NOT EXISTS "${pristine_path}")
      message(SEND_ERROR "httparse-mutation: '${label}': no such file '${rel}'")
      math(EXPR uncaught "${uncaught} + 1")
      continue()
    endif()

    file(READ "${pristine_path}" pristine)

    # Count occurrences literally. string(FIND) does no regex interpretation, so
    # patterns full of quotes, backslashes, and ${...} need no escaping and no
    # sentinel character.
    string(LENGTH "${find}" find_length)
    set(found 0)
    set(remaining "${pristine}")
    string(FIND "${remaining}" "${find}" at)
    while(NOT at EQUAL -1)
      math(EXPR found "${found} + 1")
      math(EXPR cut "${at} + ${find_length}")
      string(SUBSTRING "${remaining}" ${cut} -1 remaining)
      string(FIND "${remaining}" "${find}" at)
    endwhile()

    if(NOT found EQUAL sites)
      message(SEND_ERROR
        "httparse-mutation: '${label}': pattern occurs ${found} times in "
        "${rel}, expected ${sites}. The module was probably refactored; update "
        "the mutation rather than deleting it, or this check silently stops "
        "covering that code.")
      math(EXPR uncaught "${uncaught} + 1")
      continue()
    endif()

    string(REPLACE "${find}" "${replace}" mutated "${pristine}")
    file(WRITE "${staged_path}" "${mutated}")
    httparse_mutation_run_spec("${stage_dir}" "${spec}" rc output)
    file(WRITE "${staged_path}" "${pristine}")

    # The pure decision -- caught, not-caught, or caught for the wrong reason
    # -- lives in httparse_mutation_verdict. What is left here is turning
    # that verdict into the recorded outcome, which also depends on
    # EXPECT_SURVIVES: a fact about how this mutation was declared that the
    # verdict function does not see, and is never given alongside EXPECT_STATUS
    # or EXPECT_OUTPUT_MATCHES (httparse_mutation refuses that combination).
    httparse_mutation_verdict(
      "${rc}" "${output}" "${expect_status}" "${expect_output_matches}"
      verdict reason)

    if(survives)
      if(verdict STREQUAL "not-caught")
        message(STATUS "httparse-mutation: SURVIVES (expected) ${label} -- ${survives}")
      else()
        message(SEND_ERROR
          "httparse-mutation: '${label}' is recorded as knowingly uncaught "
          "(${survives}) but the specification caught it. The recorded "
          "limitation is stale: remove EXPECT_SURVIVES and update the decision "
          "record that cites it.")
        math(EXPR uncaught "${uncaught} + 1")
      endif()
    elseif(verdict STREQUAL "not-caught")
      message(SEND_ERROR
        "httparse-mutation: UNCAUGHT ${label} -- ${spec} still passes with "
        "${rel} broken. That specification is not testing this behaviour.")
      math(EXPR uncaught "${uncaught} + 1")
    elseif(verdict STREQUAL "wrong-reason")
      message(SEND_ERROR
        "httparse-mutation: '${label}' exited nonzero (${rc}) but for the "
        "wrong reason -- ${reason}. That is caught by coincidence, not by "
        "the decision this mutation names, and proves nothing about it.")
      math(EXPR uncaught "${uncaught} + 1")
    else()
      message(STATUS "httparse-mutation: caught ${label}")
    endif()
  endforeach()

  if(uncaught EQUAL 0)
    message(STATUS
      "httparse-mutation: ${_hp_mutation_count} mutations, all accounted for")
  endif()
endfunction()

# httparse_mutation_totals(<out_passes> <out_mutations>)
#
# The running total across every httparse_mutation_run call made so far in
# this process. A suite calls this once, after its last pass, and compares the
# result against the count its own header comment declares -- the only thing
# that would otherwise notice a whole pass, or a single mutation within one,
# being quietly deleted: httparse_mutation_run's own uncaught-count check
# is per pass and cannot see a pass that never ran at all.
function(httparse_mutation_totals out_passes out_mutations)
  get_property(passes GLOBAL PROPERTY HTTPARSE_MUTATION_TOTAL_PASSES)
  get_property(mutations GLOBAL PROPERTY HTTPARSE_MUTATION_TOTAL_MUTATIONS)
  if(NOT passes)
    set(passes 0)
  endif()
  if(NOT mutations)
    set(mutations 0)
  endif()
  set(${out_passes} "${passes}" PARENT_SCOPE)
  set(${out_mutations} "${mutations}" PARENT_SCOPE)
endfunction()

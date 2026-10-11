# Locate and validate the Chez Scheme runtime used by the test lanes.
#
# Binary naming is not portable. Upstream installs the full system as `scheme`;
# Homebrew installs it as `chez` and reserves `petite` for the interpreter-only
# build; some distributions use `chezscheme`. A `scheme` on PATH is not
# necessarily Chez at all, so every candidate is interrogated before use.
#
# WHY CANDIDATES ARE TRIED IN TURN
#
# find_program(NAMES scheme chez chezscheme) returns the first of those names it
# finds and stops. On a host with MIT/GNU Scheme installed alongside Chez it
# returns MIT's `scheme`, and a discovery that treated one rejection as fatal
# would refuse to build even though a perfectly good `chez` sits next to it.
# So rejection is a per-candidate verdict, not a verdict on the host: each name
# is probed and classified in turn, and only exhausting all of them is fatal.
# The aggregate failure then reports what every candidate actually said, since
# "no Chez found" is useless when three were tried.
#
# WHY PETITE IS REJECTED
#
# Petite has no `compile-program`, so the ahead-of-time lane cannot run there.
# A Petite that passed discovery would produce a suite that silently covers one
# fewer execution mode than it claims.
#
# WHY THREADING IS NOT CHECKED
#
# httparse has no threads anywhere in its design, so it runs on threaded and
# non-threaded Chez alike; gating on a threaded build would refuse runtimes the
# library works on. The flag is recorded as portability evidence, not enforced.
#
# This module defines functions and does not run discovery on include, so its
# functional core is specifiable under `cmake -P` without a Chez present. Call
# httparse_chez_discover() to run the imperative half.

include_guard(GLOBAL)

# By explicit path, not module path: this module is included directly by its
# specification under `cmake -P`, where CMAKE_MODULE_PATH is not set.
include("${CMAKE_CURRENT_LIST_DIR}/HttparseProbe.cmake")

# The floor is what this project has actually verified, not what it guesses it
# could tolerate: CI builds exactly this version from source on Linux, and
# macOS is verified locally on an arm64 host rather than on a hosted runner.
# Lowering the pin means CI has verified something older; raising it needs a
# reason of its own, since it costs every embedder on an older runtime.
set(HTTPARSE_CHEZ_MINIMUM_VERSION "10.4.1")

# Searched in this order. `scheme` is first because it is what upstream installs,
# but it is also the name most likely to belong to something else, which is why
# no single name is decisive.
set(HTTPARSE_CHEZ_CANDIDATE_NAMES scheme chez chezscheme)
set(HTTPARSE_CHEZ_PROBE "${CMAKE_CURRENT_LIST_DIR}/chez-probe.ss")
set(HTTPARSE_CHEZ_PROBE_TIMEOUT 20)

# --- Functional core -------------------------------------------------------

# httparse_chez_classify(<probe_output> <path>
#                            <out_status> <out_message>
#                            <out_full_version> <out_version>
#                            <out_machine_type> <out_threaded>)
#
# Decide whether probe output came from a usable Chez, and extract the banner,
# the bare version, the machine type, and the threading flag.
#
# This is the pure core and it never fails fatally: a rejection is a returned
# status and a message, so a caller iterating over candidate binaries can record
# why one was unsuitable and go on to the next. Status is one of `ok`,
# `missing-field`, `not-chez`, `petite`, `unreadable-version`, or `too-old`.
# The message omits the "httparse: " prefix; whoever raises it adds that.
function(httparse_chez_classify output path
         out_status out_message
         out_full_version out_version out_machine_type out_threaded)
  # Cleared up front so no output is ever the caller's previous value.
  set(${out_message} "" PARENT_SCOPE)
  set(${out_full_version} "" PARENT_SCOPE)
  set(${out_version} "" PARENT_SCOPE)
  set(${out_machine_type} "" PARENT_SCOPE)
  set(${out_threaded} "" PARENT_SCOPE)

  httparse_probe_normalize("${output}" normalized)

  set(context "the chez probe of '${path}'")
  httparse_probe_field_optional("${normalized}" "full-version" full_version)
  if(full_version STREQUAL "")
    set(${out_status} "missing-field" PARENT_SCOPE)
    set(${out_message}
      "${context} produced no 'full-version' field. This usually means the binary is not the runtime it was taken for."
      PARENT_SCOPE)
    return()
  endif()

  if(NOT full_version MATCHES "Chez Scheme")
    set(${out_status} "not-chez" PARENT_SCOPE)
    set(${out_message}
      "'${path}' is not Chez Scheme; it reports '${full_version}'. The name 'scheme' on PATH belongs to several unrelated implementations. Set HTTPARSE_CHEZ_EXECUTABLE to an absolute path."
      PARENT_SCOPE)
    return()
  endif()

  # Checked after the Chez test, because Petite's banner also contains
  # 'Chez Scheme' and the more specific diagnostic is the more useful one.
  if(full_version MATCHES "Petite")
    set(${out_status} "petite" PARENT_SCOPE)
    set(${out_message}
      "Petite Chez is not a supported configuration ('${full_version}'). The ahead-of-time lane needs compile-program, which Petite does not provide. Set HTTPARSE_CHEZ_EXECUTABLE to the full system."
      PARENT_SCOPE)
    return()
  endif()

  # Read over the banner rather than a probe field, so it is checked in place.
  # Anchored to the banner's "Version" keyword rather than taking the first
  # dotted number anywhere in the string: a banner that mentioned any other
  # version first -- a build identifier, a bundled library -- would otherwise be
  # compared against the floor as if it were the release.
  if(NOT full_version MATCHES "Version ([0-9]+\\.[0-9]+\\.[0-9]+)")
    set(${out_status} "unreadable-version" PARENT_SCOPE)
    set(${out_message}
      "could not read a version number out of Chez's banner '${full_version}'. Portability evidence compares exact versions, so an unreadable one is a configuration failure rather than a blank field."
      PARENT_SCOPE)
    return()
  endif()
  set(version "${CMAKE_MATCH_1}")

  # A floor, not an equality: an embedder on a newer Chez is supported, so
  # exact-matching would refuse a runtime the project claims to accept.
  # The floor must be present before it can be enforced. `if(x VERSION_LESS "")`
  # evaluates FALSE in CMake, so an unset or out-of-scope minimum would accept
  # every version silently -- the one guard behind this project's portability
  # claim, failing open. Checked rather than assumed.
  if(NOT HTTPARSE_CHEZ_MINIMUM_VERSION MATCHES "^[0-9]+\\.[0-9]+")
    set(${out_status} "no-floor" PARENT_SCOPE)
    set(${out_message}
      "HTTPARSE_CHEZ_MINIMUM_VERSION is '${HTTPARSE_CHEZ_MINIMUM_VERSION}', which is not a version. The floor cannot be enforced, and comparing against an empty value would accept every release."
      PARENT_SCOPE)
    return()
  endif()

  if(version VERSION_LESS HTTPARSE_CHEZ_MINIMUM_VERSION)
    set(${out_status} "too-old" PARENT_SCOPE)
    set(${out_message}
      "Chez ${version} is older than the verified floor ${HTTPARSE_CHEZ_MINIMUM_VERSION}. The floor records what this project has actually run, not what it guesses it could tolerate; lower it only with CI evidence from the older release."
      PARENT_SCOPE)
    return()
  endif()

  foreach(key machine-type threaded)
    httparse_probe_field_optional("${normalized}" "${key}" value)
    if(value STREQUAL "")
      set(${out_status} "missing-field" PARENT_SCOPE)
      set(${out_message}
        "${context} produced no '${key}' field. This usually means the binary is not the runtime it was taken for."
        PARENT_SCOPE)
      return()
    endif()
    set(field_${key} "${value}")
  endforeach()

  set(${out_status} "ok" PARENT_SCOPE)
  set(${out_full_version} "${full_version}" PARENT_SCOPE)
  set(${out_version} "${version}" PARENT_SCOPE)
  set(${out_machine_type} "${field_machine-type}" PARENT_SCOPE)
  set(${out_threaded} "${field_threaded}" PARENT_SCOPE)
endfunction()

# httparse_chez_identity(<probe_output> <path>
#                            <out_full_version> <out_version>
#                            <out_machine_type> <out_threaded>)
#
# Classify, and raise whatever the classifier rejected. This is the form used
# when the caller named one specific binary and there is no next candidate to
# try, so a rejection really is the end of the road.
function(httparse_chez_identity output path
         out_full_version out_version out_machine_type out_threaded)
  httparse_chez_classify("${output}" "${path}"
    status message full_version version machine_type threaded)

  if(NOT status STREQUAL "ok")
    message(FATAL_ERROR "httparse: ${message}")
  endif()

  set(${out_full_version} "${full_version}" PARENT_SCOPE)
  set(${out_version} "${version}" PARENT_SCOPE)
  set(${out_machine_type} "${machine_type}" PARENT_SCOPE)
  set(${out_threaded} "${threaded}" PARENT_SCOPE)
endfunction()

# --- Imperative shell ------------------------------------------------------

# httparse_chez_probe(<binary> <out_output> <out_status> <out_message>)
#
# Run the probe. Non-fatal by design, for the same reason the classifier is: a
# candidate that cannot even be executed is a verdict on that candidate, not on
# the host, and the search has to be able to move on to the next name.
#
# A raising probe would let a `chezscheme` on PATH that is a symlink to a
# Petite binary abort the entire search -- Chez locates its boot files from
# argv[0], so the wrong name makes it die rather than answer -- and a perfectly
# good `chez` two entries later would never be reached.
#
# Status is `ok` or `no-answer`. execute_process reports a failure to run at all
# as a non-numeric RESULT_VARIABLE, which covers both a timeout and a subprocess
# that aborted, so the message names both possibilities rather than guessing.
function(httparse_chez_probe binary out_output out_status out_message)
  set(${out_output} "" PARENT_SCOPE)
  set(${out_message} "" PARENT_SCOPE)

  execute_process(
    COMMAND "${binary}" --script "${HTTPARSE_CHEZ_PROBE}"
    TIMEOUT "${HTTPARSE_CHEZ_PROBE_TIMEOUT}"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error
    OUTPUT_STRIP_TRAILING_WHITESPACE)

  if(NOT result MATCHES "^[0-9]+$")
    set(${out_status} "no-answer" PARENT_SCOPE)
    set(${out_message}
      "'${binary}' did not answer the Chez probe (${result}). It either aborted, or waited for input instead of reading the file and hit the ${HTTPARSE_CHEZ_PROBE_TIMEOUT}s timeout."
      PARENT_SCOPE)
    return()
  endif()

  # Deliberately not gated on exit status; the content check in
  # httparse_chez_classify is the real gate.
  set(${out_status} "ok" PARENT_SCOPE)
  set(${out_output} "${output}\n${error}" PARENT_SCOPE)
endfunction()

# httparse_chez_search(<out_path> <out_report>)
#
# Probe each candidate name in turn and return the first that classifies as a
# usable Chez. Unsuitable candidates are accumulated into a human-readable
# report rather than ending the search, because the next name may well be the
# right one -- see the header.
function(httparse_chez_search out_path out_report)
  set(report "")
  foreach(name IN LISTS HTTPARSE_CHEZ_CANDIDATE_NAMES)
    # find_program skips the search when its result variable already holds a
    # value, so without this the first candidate found would be reported for
    # every remaining name.
    unset(candidate)
    find_program(candidate NAMES "${name}" NO_CACHE)

    if(NOT candidate)
      string(APPEND report "  ${name}: not found on PATH\n")
      continue()
    endif()

    httparse_chez_probe("${candidate}" output probe_status probe_message)
    if(NOT probe_status STREQUAL "ok")
      string(APPEND report "  ${candidate}: ${probe_message}\n")
      continue()
    endif()

    httparse_chez_classify("${output}" "${candidate}"
      status message full_version version machine_type threaded)

    if(status STREQUAL "ok")
      set(${out_path} "${candidate}" PARENT_SCOPE)
      set(${out_report} "${report}" PARENT_SCOPE)
      return()
    endif()

    string(APPEND report "  ${candidate}: ${message}\n")
  endforeach()

  set(${out_path} "" PARENT_SCOPE)
  set(${out_report} "${report}" PARENT_SCOPE)
endfunction()

macro(httparse_chez_discover)
  if(NOT HTTPARSE_CHEZ_EXECUTABLE)
    httparse_chez_search(_httparse_chez_found _httparse_chez_report)
    if(_httparse_chez_found)
      set(HTTPARSE_CHEZ_EXECUTABLE "${_httparse_chez_found}" CACHE FILEPATH
        "Full Chez Scheme executable. Must not be Petite.")
    else()
      message(FATAL_ERROR
        "httparse: no usable Chez Scheme found. Each candidate name was "
        "probed and rejected:\n${_httparse_chez_report}"
        "Install Chez ${HTTPARSE_CHEZ_MINIMUM_VERSION} or newer, or set "
        "-DHTTPARSE_CHEZ_EXECUTABLE=/absolute/path/to/scheme.")
    endif()
  endif()

  # A value supplied on the command line reaches here without having been
  # searched for, so it is checked separately.
  if(NOT EXISTS "${HTTPARSE_CHEZ_EXECUTABLE}")
    message(FATAL_ERROR
      "httparse: the Chez executable '${HTTPARSE_CHEZ_EXECUTABLE}' does "
      "not exist. HTTPARSE_CHEZ_EXECUTABLE must be an absolute path.")
  endif()

  # Deliberately the fatal form even when the path came from the search: one
  # named binary has no next candidate, and re-validating the winner keeps the
  # reported fields and the accepted binary provably the same one.
  httparse_chez_probe("${HTTPARSE_CHEZ_EXECUTABLE}"
    _httparse_chez_output _httparse_chez_probe_status _httparse_chez_probe_message)
  if(NOT _httparse_chez_probe_status STREQUAL "ok")
    message(FATAL_ERROR "httparse: ${_httparse_chez_probe_message}")
  endif()
  httparse_chez_identity(
    "${_httparse_chez_output}" "${HTTPARSE_CHEZ_EXECUTABLE}"
    HTTPARSE_CHEZ_FULL_VERSION HTTPARSE_CHEZ_VERSION
    HTTPARSE_CHEZ_MACHINE_TYPE HTTPARSE_CHEZ_THREADED)

  message(STATUS
    "httparse Chez: ${HTTPARSE_CHEZ_EXECUTABLE} "
    "(${HTTPARSE_CHEZ_FULL_VERSION}, machine "
    "${HTTPARSE_CHEZ_MACHINE_TYPE}, threaded ${HTTPARSE_CHEZ_THREADED})")
endmacro()

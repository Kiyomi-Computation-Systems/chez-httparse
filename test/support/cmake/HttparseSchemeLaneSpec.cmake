# Specification for cmake/HttparseSchemeLane.cmake.
#
# A lane's command line is where a source lane quietly stops being a source
# lane. Chez needs its object-guard pair to make a compiled object unloadable.
# That is invisible when it is missing: the lane still runs and still passes,
# having proved something other than what it claims.

cmake_minimum_required(VERSION 3.26)

include("${CMAKE_CURRENT_LIST_DIR}/../../../cmake/HttparseSchemeLane.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/SpecSupport.cmake")

set(SPEC_SELF "${CMAKE_CURRENT_LIST_FILE}")

if(DEFINED HTTPARSE_SPEC_CASE)
  set(c "${HTTPARSE_SPEC_CASE}")

  # Neither registrar belongs to a project context this script does not have
  # -- add_test is not scriptable under cmake -P. Stubbing both is what keeps
  # a rejection that stopped rejecting from crashing on that unrelated error
  # instead of falling through to the "must be rejected" check below, which is
  # what actually proves the case.
  function(httparse_add_test)
  endfunction()
  function(httparse_add_exit_code_test)
  endfunction()

  if(c STREQUAL "lane-rejects-unparsed-arguments")
    httparse_add_scheme_lane(
      NAME httparse.harness.example.chez.source
      BACKEND chez
      PROGRAM "${SPEC_SELF}"
      TIMEOUT 10
      unexpected-extra-argument)
  elseif(c STREQUAL "lane-requires-name")
    httparse_add_scheme_lane(
      BACKEND chez
      PROGRAM "${SPEC_SELF}"
      TIMEOUT 10)
  elseif(c STREQUAL "lane-requires-backend")
    httparse_add_scheme_lane(
      NAME httparse.harness.example.chez.source
      PROGRAM "${SPEC_SELF}"
      TIMEOUT 10)
  elseif(c STREQUAL "lane-requires-program")
    httparse_add_scheme_lane(
      NAME httparse.harness.example.chez.source
      BACKEND chez
      TIMEOUT 10)
  elseif(c STREQUAL "lane-requires-timeout")
    httparse_add_scheme_lane(
      NAME httparse.harness.example.chez.source
      BACKEND chez
      PROGRAM "${SPEC_SELF}")
  elseif(c STREQUAL "lane-requires-sources")
    httparse_add_scheme_lane(
      NAME httparse.harness.example.chez.source
      BACKEND chez
      PROGRAM "${SPEC_SELF}"
      TIMEOUT 10)
  elseif(c STREQUAL "lane-requires-existing-program")
    httparse_add_scheme_lane(
      NAME httparse.harness.example.chez.source
      BACKEND chez
      PROGRAM "/h/self/does-not-exist.sps"
      SOURCES "${SPEC_SELF}"
      TIMEOUT 10)
  elseif(c STREQUAL "lane-rejects-missing-source")
    httparse_add_scheme_lane(
      NAME httparse.harness.example.chez.source
      BACKEND chez
      PROGRAM "${SPEC_SELF}"
      SOURCES "${SPEC_SELF}" "/nonexistent/body.scm"
      TIMEOUT 10)
  elseif(c STREQUAL "lane-rejects-duplicate-source-basename")
    httparse_add_scheme_lane(
      NAME httparse.harness.example.chez.source
      BACKEND chez
      PROGRAM "${SPEC_SELF}"
      SOURCES "${SPEC_SELF}" "${SPEC_SELF}"
      TIMEOUT 10)
  elseif(c STREQUAL "lane-rejects-unknown-backend")
    httparse_add_scheme_lane(
      NAME httparse.harness.example.chez.source
      BACKEND guile
      PROGRAM "${SPEC_SELF}"
      SOURCES "${SPEC_SELF}"
      TIMEOUT 10)
  elseif(c STREQUAL "lane-rejects-unknown-mode")
    # The registrar never compares BACKEND against the NAME's own backend
    # segment: httparse_test_name_parse supplies only lane_mode, and
    # BACKEND routes httparse_scheme_lane_command directly (see that call
    # in HttparseSchemeLane.cmake). A name whose backend segment is cmake
    # -- so httparse_test_name_parse validates "direct" against cmake's
    # own mode vocabulary and accepts it -- paired with BACKEND chez reaches
    # the chez branch carrying a mode (direct) it does not build a command
    # for: unknown-mode, not unknown-backend, and reachable only through the
    # full registrar this way -- httparse_scheme_lane_command's own
    # unknown-mode case is already covered directly, without a registrar.
    set(HTTPARSE_CHEZ_EXECUTABLE "/opt/chez")
    httparse_add_scheme_lane(
      NAME httparse.harness.example.cmake.direct
      BACKEND chez
      PROGRAM "${SPEC_SELF}"
      SOURCES "${SPEC_SELF}"
      TIMEOUT 10)
  else()
    message(FATAL_ERROR "httparse-spec: unknown case '${c}'")
  endif()

  message(FATAL_ERROR "httparse-spec: case '${c}' was accepted but must be rejected")
endif()

set(HTTPARSE_HARNESS_CHEZ_LAUNCHER "/h/launchers/chez-source.ss")
set(HTTPARSE_CHEZ_OBJECT_ROOT "/objects")
set(HTTPARSE_HARNESS_CHEZ_AOT_LAUNCHER "/launchers/chez-aot.ss")
set(HTTPARSE_HARNESS_CHEZ_COMPILE_LAUNCHER "/launchers/chez-compile.ss")
set(HTTPARSE_HARNESS_CHEZ_LIBRARY_ROOT "/h/chez")
set(HTTPARSE_HARNESS_OBJECT_GUARD_DIR "/b/guard")
set(HTTPARSE_SRC_CHEZ_LIBRARY_ROOT "/s/chez")
# The generator's library root. A lane names one root per
# library family it imports, so the source command line grows by one flag
# pair for the generator -- which is what the expectation below asserts.
set(HTTPARSE_GENERATOR_CHEZ_LIBRARY_ROOT "/g/chez")

# --- Chez ------------------------------------------------------------------

set(HTTPARSE_CHEZ_EXECUTABLE "/opt/chez")
httparse_scheme_lane_command(httparse.harness.example.chez.source
  chez source "/h/self/p.sps" command measured status message)
spec_check_equal("${status}" "ok" "chez lane classifies")
spec_check_equal("${command}"
  "/opt/chez;--script;/h/launchers/chez-source.ss;--library-root;/h/chez;--library-root;/s/chez;--library-root;/g/chez;--object-guard;/b/guard;--program;/h/self/p.sps"
  "chez lane command line")

# The guard directory is the entire mechanism that stops a stale .so from being
# loaded in a lane that calls itself source. Asserted through its flag rather
# than by position: with a repeatable-flag protocol a position is no longer
# stable, and a lane that dropped the guard would still run.
list(FIND command "--object-guard" guard_index)
math(EXPR guard_value_index "${guard_index} + 1")
list(GET command "${guard_value_index}" guard)
spec_check_equal("${guard}" "/b/guard" "chez lane passes the object guard directory")

# Within one lane, measured copies are keyed by basename in a flat
# fingerprint/ directory, so a manifest carrying two entries with one
# basename would let one silently overwrite the other. The pure detector is
# asserted directly; the registrar's refusal is a rejection case below.
httparse_lane_duplicate_basenames(dups "/a/x.sls" "/b/y.sls")
spec_check_equal("${dups}" "" "distinct basenames report no duplicates")
httparse_lane_duplicate_basenames(dups "/a/x.sls" "/b/x.sls" "/c/x.sls" "/d/y.sls")
spec_check_equal("${dups}" "x.sls" "a repeated basename is reported once, however often it repeats")

# CMake resolves an unset local through the calling scope, so if the
# detector ever loses its own accumulator initialization, it inherits
# whatever `duplicates` the caller has lying around. Seeded here so that
# hazard has a witness.
set(duplicates "stale-from-caller")
httparse_lane_duplicate_basenames(dups "/a/x.sls" "/b/y.sls")
spec_check_equal("${dups}" "" "the detector does not inherit the caller's ambient duplicates")
unset(duplicates)

# --- Rejections ------------------------------------------------------------

# Diagnostics carry a stable prefix precisely so a specification can assert the
# exact wording, not merely a nonzero status. Asserted here for both messages
# the functional core can produce: a typo or a garbled string would otherwise
# pass every existing assertion undetected.
httparse_scheme_lane_command(httparse.harness.example.guile.source
  guile source "/h/self/p.scm" command measured status message)
spec_check_equal("${status}" "unknown-backend" "an unknown backend is rejected")
spec_check_equal("${message}"
  "'guile' is not a Scheme lane backend. Known backends: chez."
  "unknown backend message")

set(HTTPARSE_CHEZ_EXECUTABLE "")
httparse_scheme_lane_command(httparse.harness.example.chez.source
  chez source "/h/self/p.sps" command measured status message)
spec_check_equal("${status}" "no-runtime" "a chez lane without a chez is not registered")
spec_check_equal("${command}" "" "a rejected lane returns no command")
spec_check_equal("${message}"
  "no Chez was discovered, so the chez source lane for '/h/self/p.sps' is not registered."
  "chez lane no-runtime message")

# Both no-runtime REPLACEs in MutationSuite.cmake hardcode the literal
# "source" (see that file's own comment on this exact hazard), so a mutation
# that reverted ${mode} back to a hardcoded "source" would pass every
# assertion above -- every one of them calls with mode source. Asserted here
# with mode aot instead, the one mode value able to tell the fixed code from
# the reverted one.
httparse_scheme_lane_command(httparse.harness.example.chez.aot
  chez aot "/h/self/p.sps" command measured status message)
spec_check_equal("${status}" "no-runtime" "a chez aot lane without a chez is not registered")
spec_check_equal("${command}" "" "a rejected lane returns no command")
spec_check_equal("${message}"
  "no Chez was discovered, so the chez aot lane for '/h/self/p.sps' is not registered."
  "chez lane no-runtime message names the aot mode, not a hardcoded source")

# --- Declared sources versus measured sources ------------------------------
#
# A source lane reads the repository sources, so the two lists coincide and
# the distinction is invisible. It is not invisible for a compiled lane, where
# the expectation is computed from the originals and the run must read what
# the artifact was actually built from -- and this is the one place a
# specification can see the rule with no runtime present.
set(HTTPARSE_CHEZ_EXECUTABLE "/opt/chez")
httparse_scheme_lane_command(httparse.harness.example.chez.source
  chez source "/h/self/p.sps"
  command measured status message "/h/shared/a.scm" "/h/shared/b.scm")
spec_check_equal("${status}" "ok" "a chez source lane is accepted")
spec_check_equal("${measured}" "/h/shared/a.scm;/h/shared/b.scm"
  "a source lane measures the sources it declares, in the declared order")

# The aot half of the same rule, over two sources, because a one-source
# manifest cannot witness order: the measured list must be the fingerprint/
# copies, in the declared order. This is the assertion MutationSuite.cmake's
# "a compiled lane measures the repository originals" and "the measured list
# is built in reverse" mutations break.
set(HTTPARSE_CHEZ_EXECUTABLE "/opt/chez")
httparse_scheme_lane_command(httparse.harness.example-two.chez.aot
  chez aot "/h/self/p.sps"
  command measured status message "/h/shared/a.scm" "/h/shared/b.scm")
spec_check_equal("${status}" "ok" "a two-source chez aot lane is accepted")
spec_check_equal("${measured}"
  "/objects/httparse_harness_example-two_chez_aot/fingerprint/a.scm;/objects/httparse_harness_example-two_chez_aot/fingerprint/b.scm"
  "an aot lane measures the fingerprint copies, in the declared order")
spec_check_equal("${command}"
  "/opt/chez;--script;/launchers/chez-aot.ss;--object-dir;/objects/httparse_harness_example-two_chez_aot/harness;--object-dir;/objects/httparse_harness_example-two_chez_aot/src;--object-dir;/objects/httparse_harness_example-two_chez_aot/generator;--source-guard;/b/guard;--program;/objects/httparse_harness_example-two_chez_aot/p.so"
  "chez aot lane command line -- THREE object dirs, one per library root the
   source lane names. The generator's was missing until the first aot lane that
   imported a generator library, which failed with an unbound library rather
   than a missing directory; this assertion is what stops it being dropped
   again.")

httparse_scheme_lane_command(httparse.harness.example.chez.unknown-mode-name
  chez unknown-mode-name "/h/self/p.sps"
  command measured status message "/h/shared/a.scm")
spec_check_equal("${status}" "unknown-mode" "an unregistered mode is rejected")
spec_check_equal("${command}" "" "a rejected lane returns no command")
spec_check_equal("${measured}" "" "a rejected lane measures nothing")
spec_check_equal("${message}"
  "'unknown-mode-name' is not an execution mode this lane module can build a command for. Known modes: source aot."
  "unknown mode message")

# --- Registration (httparse_add_scheme_lane) ----------------------------
#
# add_test is not scriptable under cmake -P, so the two registrars are stubbed
# here too, this time to record which one httparse_add_scheme_lane reached
# and with what arguments rather than to stand aside for a rejection. Routing
# and the environment prefix live directly in this function with no pure
# helper underneath, so stubbing its two dependencies is the only way to
# observe them at all.
# Both stubs below record WORKING_DIRECTORY two ways: the value cmake_parse_arguments
# extracted, and whether the literal "WORKING_DIRECTORY" keyword appears anywhere
# in the raw argument list at all. The second is not redundant with the first. A
# lane that omitted WORKING_DIRECTORY and a lane that forwarded it with an empty
# value can both leave the parsed variable unset at this project's declared 3.26
# floor (CMP0174, which would tell them apart, is 3.31+) -- so only a scan of the
# raw arguments can tell "the keyword never appeared" from "it appeared with
# nothing after it", and the whole point of HttparseSchemeLane.cmake building
# working_directory_args conditionally is to never produce the second shape.
function(httparse_add_test)
  cmake_parse_arguments(PARSE_ARGV 0 s "" "NAME;TIMEOUT;WORKING_DIRECTORY" "COMMAND;LABELS;ENVIRONMENT")
  set_property(GLOBAL PROPERTY HTTPARSE_SPEC_REGISTRAR "plain")
  set_property(GLOBAL PROPERTY HTTPARSE_SPEC_ENVIRONMENT "${s_ENVIRONMENT}")
  set_property(GLOBAL PROPERTY HTTPARSE_SPEC_WORKING_DIRECTORY "${s_WORKING_DIRECTORY}")
  list(FIND ARGN "WORKING_DIRECTORY" wd_at)
  if(wd_at EQUAL -1)
    set_property(GLOBAL PROPERTY HTTPARSE_SPEC_WORKING_DIRECTORY_KEYWORD "absent")
  else()
    set_property(GLOBAL PROPERTY HTTPARSE_SPEC_WORKING_DIRECTORY_KEYWORD "present")
  endif()
endfunction()

function(httparse_add_exit_code_test)
  cmake_parse_arguments(PARSE_ARGV 0 s "" "NAME;EXPECT_EXIT;TIMEOUT;WORKING_DIRECTORY" "COMMAND;LABELS;ENVIRONMENT")
  set_property(GLOBAL PROPERTY HTTPARSE_SPEC_REGISTRAR "exit-code")
  set_property(GLOBAL PROPERTY HTTPARSE_SPEC_EXPECT_EXIT "${s_EXPECT_EXIT}")
  set_property(GLOBAL PROPERTY HTTPARSE_SPEC_ENVIRONMENT "${s_ENVIRONMENT}")
  set_property(GLOBAL PROPERTY HTTPARSE_SPEC_WORKING_DIRECTORY "${s_WORKING_DIRECTORY}")
  list(FIND ARGN "WORKING_DIRECTORY" wd_at)
  if(wd_at EQUAL -1)
    set_property(GLOBAL PROPERTY HTTPARSE_SPEC_WORKING_DIRECTORY_KEYWORD "absent")
  else()
    set_property(GLOBAL PROPERTY HTTPARSE_SPEC_WORKING_DIRECTORY_KEYWORD "present")
  endif()
endfunction()

# The aot artifacts builder is imperative shell (add_custom_command is not
# scriptable under cmake -P), so it is stubbed the same way the two
# registrars are: recorded, not run. What the spec can see is the routing
# decision -- an aot registration must reach it, a source registration must
# not -- and the arguments it was reached with, which is where the
# stale-root forwarding becomes assertable with no Scheme present.
function(httparse_lane_chez_aot_artifacts name program stale_library_root)
  set_property(GLOBAL PROPERTY HTTPARSE_SPEC_AOT_BUILDER_NAME "${name}")
  set_property(GLOBAL PROPERTY HTTPARSE_SPEC_AOT_BUILDER_STALE "${stale_library_root}")
endfunction()

# httparse_expected_fingerprint and httparse_wrong_fingerprint are
# defined in test/CMakeLists.txt, which this standalone
# script does not include, so they are stubbed for the same reason the two
# registrars above are: every direct registration below sets
# HTTPARSE_CHEZ_EXECUTABLE, which is exactly what makes
# httparse_add_scheme_lane's manifest block call one of these two. The
# environment assertions below account for what the stub adds. Each stub also
# records which one ran, in HTTPARSE_SPEC_FINGERPRINT_FUNCTION, so the
# WRONG_FINGERPRINT routing further down can be asserted directly.
function(httparse_expected_fingerprint name out_var)
  set_property(GLOBAL PROPERTY HTTPARSE_SPEC_FINGERPRINT_FUNCTION "expected")
  set(${out_var} "/fingerprints/${name}.fingerprint" PARENT_SCOPE)
endfunction()

function(httparse_wrong_fingerprint name out_var)
  set_property(GLOBAL PROPERTY HTTPARSE_SPEC_FINGERPRINT_FUNCTION "wrong")
  set(${out_var} "/fingerprints/${name}.wrong" PARENT_SCOPE)
endfunction()

# An EXPECT_EXIT lane must route to the exit-code registrar and forward the
# code. Both this registration and the plain one below must carry the source
# execution mode, the fingerprint sample path, and the fingerprint manifest
# ahead of whatever the caller supplied -- facts the launcher itself cannot
# assert about its own invocation.
set(HTTPARSE_CHEZ_EXECUTABLE "/opt/chez")
set_property(GLOBAL PROPERTY HTTPARSE_SPEC_REGISTRAR "none")
httparse_add_scheme_lane(
  NAME httparse.harness.example.chez.source
  BACKEND chez
  PROGRAM "${SPEC_SELF}"
  SOURCES "${SPEC_SELF}"
  TIMEOUT 10
  EXPECT_EXIT 1
  ENVIRONMENT "FOO=bar")
get_property(registrar GLOBAL PROPERTY HTTPARSE_SPEC_REGISTRAR)
spec_check_equal("${registrar}" "exit-code" "EXPECT_EXIT routes to the exit-code registrar")
get_property(expect_exit GLOBAL PROPERTY HTTPARSE_SPEC_EXPECT_EXIT)
spec_check_equal("${expect_exit}" "1" "EXPECT_EXIT is forwarded to the exit-code registrar")
get_property(environment GLOBAL PROPERTY HTTPARSE_SPEC_ENVIRONMENT)
spec_check_equal("${environment}"
  "HTTPARSE_EXECUTION_MODE=source;HTTPARSE_FINGERPRINT_SAMPLE=${CMAKE_SOURCE_DIR}/test/fixtures/fingerprint-sample.bin;HTTPARSE_FINGERPRINT_FILES=${SPEC_SELF};HTTPARSE_EXPECT_FINGERPRINT_FILE=/fingerprints/httparse.harness.example.chez.source.fingerprint;FOO=bar"
  "exit-code registration carries every default ahead of caller-supplied entries, which are appended last so they can override a default")

set_property(GLOBAL PROPERTY HTTPARSE_SPEC_REGISTRAR "none")
httparse_add_scheme_lane(
  NAME httparse.harness.example.chez.source
  BACKEND chez
  PROGRAM "${SPEC_SELF}"
  SOURCES "${SPEC_SELF}"
  TIMEOUT 10
  ENVIRONMENT "FOO=bar")
get_property(registrar GLOBAL PROPERTY HTTPARSE_SPEC_REGISTRAR)
spec_check_equal("${registrar}" "plain" "a lane without EXPECT_EXIT routes to the plain registrar")
get_property(environment GLOBAL PROPERTY HTTPARSE_SPEC_ENVIRONMENT)
spec_check_equal("${environment}"
  "HTTPARSE_EXECUTION_MODE=source;HTTPARSE_FINGERPRINT_SAMPLE=${CMAKE_SOURCE_DIR}/test/fixtures/fingerprint-sample.bin;HTTPARSE_FINGERPRINT_FILES=${SPEC_SELF};HTTPARSE_EXPECT_FINGERPRINT_FILE=/fingerprints/httparse.harness.example.chez.source.fingerprint;FOO=bar"
  "plain registration carries every default ahead of caller-supplied entries, which are appended last so they can override a default")

# --- The mode is the name's, not a literal ---------------------------------
#
# A lane that declares a mode it is not running is the defect this section
# exists to prevent, and the declaration is what every other lane's evidence
# is labelled with. Asserted over a name that is not `source`, because the
# literal it replaced was `source`: a mutation restoring the literal passes
# every assertion written over a source lane.
set(HTTPARSE_CHEZ_EXECUTABLE "/opt/chez")
set_property(GLOBAL PROPERTY HTTPARSE_SPEC_REGISTRAR "none")
set_property(GLOBAL PROPERTY HTTPARSE_SPEC_AOT_BUILDER_NAME "none")
httparse_add_scheme_lane(
  NAME httparse.harness.example.chez.aot
  BACKEND chez
  PROGRAM "${SPEC_SELF}"
  SOURCES "${SPEC_SELF}"
  TIMEOUT 10)
get_property(environment GLOBAL PROPERTY HTTPARSE_SPEC_ENVIRONMENT)
list(GET environment 0 mode_entry)
spec_check_equal("${mode_entry}" "HTTPARSE_EXECUTION_MODE=aot"
  "an aot lane declares the aot mode, read from its own name")

# The full list, not just the mode entry above: HTTPARSE_FINGERPRINT_FILES
# here is the measured copy's path under the per-lane object directory, while
# HTTPARSE_EXPECT_FINGERPRINT_FILE is still keyed by the lane's own name --
# the expectation comes from the declared source, the run's environment from
# the measured one. This assertion is the declared/measured asymmetry itself,
# the whole mechanism this task adds, visible here with no Scheme runtime
# present.
spec_check_equal("${environment}"
  "HTTPARSE_EXECUTION_MODE=aot;HTTPARSE_FINGERPRINT_SAMPLE=${CMAKE_SOURCE_DIR}/test/fixtures/fingerprint-sample.bin;HTTPARSE_FINGERPRINT_FILES=/objects/httparse_harness_example_chez_aot/fingerprint/HttparseSchemeLaneSpec.cmake;HTTPARSE_EXPECT_FINGERPRINT_FILE=/fingerprints/httparse.harness.example.chez.aot.fingerprint"
  "an aot lane's environment carries the measured copy's path in HTTPARSE_FINGERPRINT_FILES, not the declared source's own path")
get_property(builder_name GLOBAL PROPERTY HTTPARSE_SPEC_AOT_BUILDER_NAME)
spec_check_equal("${builder_name}" "httparse.harness.example.chez.aot"
  "an aot registration reaches the artifacts builder with its own lane name")
get_property(builder_stale GLOBAL PROPERTY HTTPARSE_SPEC_AOT_BUILDER_STALE)
spec_check_equal("${builder_stale}" ""
  "a lane without STALE_LIBRARY_ROOT hands the builder an empty stale root")

set_property(GLOBAL PROPERTY HTTPARSE_SPEC_AOT_BUILDER_NAME "none")
httparse_add_scheme_lane(
  NAME httparse.harness.example.chez.source
  BACKEND chez
  PROGRAM "${SPEC_SELF}"
  SOURCES "${SPEC_SELF}"
  TIMEOUT 10)
get_property(environment GLOBAL PROPERTY HTTPARSE_SPEC_ENVIRONMENT)
list(GET environment 0 mode_entry)
spec_check_equal("${mode_entry}" "HTTPARSE_EXECUTION_MODE=source"
  "a source lane still declares source")
get_property(builder_name GLOBAL PROPERTY HTTPARSE_SPEC_AOT_BUILDER_NAME)
spec_check_equal("${builder_name}" "none"
  "a source registration never reaches the artifacts builder")

# WRONG_FINGERPRINT chooses which function computes expect_file for the
# manifest block: present, httparse_wrong_fingerprint; absent,
# httparse_expected_fingerprint. Two assertions, since a branch has two
# sides -- a spec that checked only one would still pass if the branch were
# replaced by a constant that always called the same function.
set_property(GLOBAL PROPERTY HTTPARSE_SPEC_FINGERPRINT_FUNCTION "none")
httparse_add_scheme_lane(
  NAME httparse.harness.example.chez.source
  BACKEND chez
  PROGRAM "${SPEC_SELF}"
  SOURCES "${SPEC_SELF}"
  TIMEOUT 10
  WRONG_FINGERPRINT)
get_property(fingerprint_function GLOBAL PROPERTY HTTPARSE_SPEC_FINGERPRINT_FUNCTION)
spec_check_equal("${fingerprint_function}" "wrong"
  "a registration WITH WRONG_FINGERPRINT routes to httparse_wrong_fingerprint")

set_property(GLOBAL PROPERTY HTTPARSE_SPEC_FINGERPRINT_FUNCTION "none")
httparse_add_scheme_lane(
  NAME httparse.harness.example.chez.source
  BACKEND chez
  PROGRAM "${SPEC_SELF}"
  SOURCES "${SPEC_SELF}"
  TIMEOUT 10)
get_property(fingerprint_function GLOBAL PROPERTY HTTPARSE_SPEC_FINGERPRINT_FUNCTION)
spec_check_equal("${fingerprint_function}" "expected"
  "a registration WITHOUT WRONG_FINGERPRINT routes to httparse_expected_fingerprint")

# STALE_LIBRARY_ROOT changes what is compiled, never what is declared or
# run. If it reached the declared list the expectation would move with the
# artifact, the two would agree, and the lane that exists to fail would
# pass; if it changed the run command the lane would stop being the same
# lane it is the stale twin of. Three assertions, one per invariant.
set(HTTPARSE_CHEZ_EXECUTABLE "/opt/chez")
set_property(GLOBAL PROPERTY HTTPARSE_SPEC_REGISTRAR "none")
set_property(GLOBAL PROPERTY HTTPARSE_SPEC_FINGERPRINT_FUNCTION "none")
set_property(GLOBAL PROPERTY HTTPARSE_SPEC_AOT_BUILDER_STALE "unset")
httparse_add_scheme_lane(
  NAME httparse.harness.example-stale.chez.aot
  BACKEND chez
  PROGRAM "${SPEC_SELF}"
  SOURCES "${SPEC_SELF}"
  STALE_LIBRARY_ROOT "/fixtures/stale-root"
  EXPECT_EXIT 3
  TIMEOUT 10)
get_property(builder_stale GLOBAL PROPERTY HTTPARSE_SPEC_AOT_BUILDER_STALE)
spec_check_equal("${builder_stale}" "/fixtures/stale-root"
  "STALE_LIBRARY_ROOT reaches the artifacts builder")
get_property(fingerprint_function GLOBAL PROPERTY HTTPARSE_SPEC_FINGERPRINT_FUNCTION)
spec_check_equal("${fingerprint_function}" "expected"
  "a stale lane still computes the real expectation from its declared sources")
get_property(environment GLOBAL PROPERTY HTTPARSE_SPEC_ENVIRONMENT)
list(GET environment 0 mode_entry)
spec_check_equal("${mode_entry}" "HTTPARSE_EXECUTION_MODE=aot"
  "a stale lane is an ordinary aot lane to everything downstream of the builder")

# WORKING_DIRECTORY must be forwarded to whichever registrar the lane routed
# to, with its value, when the lane was given one -- and the keyword must not
# reach the registrar at all when it was not. Both directions, through both
# registrars: HttparseSchemeLane.cmake builds one working_directory_args
# list and splices it into both registration calls, so either could stop
# forwarding it independently of the other.
set_property(GLOBAL PROPERTY HTTPARSE_SPEC_REGISTRAR "none")
set_property(GLOBAL PROPERTY HTTPARSE_SPEC_WORKING_DIRECTORY "sentinel")
set_property(GLOBAL PROPERTY HTTPARSE_SPEC_WORKING_DIRECTORY_KEYWORD "sentinel")
httparse_add_scheme_lane(
  NAME httparse.harness.example.chez.source
  BACKEND chez
  PROGRAM "${SPEC_SELF}"
  SOURCES "${SPEC_SELF}"
  TIMEOUT 10
  WORKING_DIRECTORY "/h/run")
get_property(wd GLOBAL PROPERTY HTTPARSE_SPEC_WORKING_DIRECTORY)
spec_check_equal("${wd}" "/h/run"
  "a WORKING_DIRECTORY given to the plain registration path is forwarded with its value")
get_property(wd_keyword GLOBAL PROPERTY HTTPARSE_SPEC_WORKING_DIRECTORY_KEYWORD)
spec_check_equal("${wd_keyword}" "present"
  "the WORKING_DIRECTORY keyword reaches the plain registrar when the lane gave one")

set_property(GLOBAL PROPERTY HTTPARSE_SPEC_REGISTRAR "none")
set_property(GLOBAL PROPERTY HTTPARSE_SPEC_WORKING_DIRECTORY "sentinel")
set_property(GLOBAL PROPERTY HTTPARSE_SPEC_WORKING_DIRECTORY_KEYWORD "sentinel")
httparse_add_scheme_lane(
  NAME httparse.harness.example.chez.source
  BACKEND chez
  PROGRAM "${SPEC_SELF}"
  SOURCES "${SPEC_SELF}"
  TIMEOUT 10)
get_property(wd_keyword GLOBAL PROPERTY HTTPARSE_SPEC_WORKING_DIRECTORY_KEYWORD)
spec_check_equal("${wd_keyword}" "absent"
  "no WORKING_DIRECTORY keyword reaches the plain registrar when the lane did not give one")

set_property(GLOBAL PROPERTY HTTPARSE_SPEC_REGISTRAR "none")
set_property(GLOBAL PROPERTY HTTPARSE_SPEC_WORKING_DIRECTORY "sentinel")
set_property(GLOBAL PROPERTY HTTPARSE_SPEC_WORKING_DIRECTORY_KEYWORD "sentinel")
httparse_add_scheme_lane(
  NAME httparse.harness.example.chez.source
  BACKEND chez
  PROGRAM "${SPEC_SELF}"
  SOURCES "${SPEC_SELF}"
  TIMEOUT 10
  EXPECT_EXIT 1
  WORKING_DIRECTORY "/h/run")
get_property(wd GLOBAL PROPERTY HTTPARSE_SPEC_WORKING_DIRECTORY)
spec_check_equal("${wd}" "/h/run"
  "a WORKING_DIRECTORY given to the exit-code registration path is forwarded with its value")
get_property(wd_keyword GLOBAL PROPERTY HTTPARSE_SPEC_WORKING_DIRECTORY_KEYWORD)
spec_check_equal("${wd_keyword}" "present"
  "the WORKING_DIRECTORY keyword reaches the exit-code registrar when the lane gave one")

set_property(GLOBAL PROPERTY HTTPARSE_SPEC_REGISTRAR "none")
set_property(GLOBAL PROPERTY HTTPARSE_SPEC_WORKING_DIRECTORY "sentinel")
set_property(GLOBAL PROPERTY HTTPARSE_SPEC_WORKING_DIRECTORY_KEYWORD "sentinel")
httparse_add_scheme_lane(
  NAME httparse.harness.example.chez.source
  BACKEND chez
  PROGRAM "${SPEC_SELF}"
  SOURCES "${SPEC_SELF}"
  TIMEOUT 10
  EXPECT_EXIT 1)
get_property(wd_keyword GLOBAL PROPERTY HTTPARSE_SPEC_WORKING_DIRECTORY_KEYWORD)
spec_check_equal("${wd_keyword}" "absent"
  "no WORKING_DIRECTORY keyword reaches the exit-code registrar when the lane did not give one")

# A no-runtime backend must skip registration silently: neither registrar may
# be reached. This runs in-process rather than through spec_expect_rejected, so
# simply reaching the assertion below is itself proof that nothing raised.
set(HTTPARSE_CHEZ_EXECUTABLE "")
set_property(GLOBAL PROPERTY HTTPARSE_SPEC_REGISTRAR "none")
httparse_add_scheme_lane(
  NAME httparse.harness.example.chez.source
  BACKEND chez
  PROGRAM "${SPEC_SELF}"
  SOURCES "${SPEC_SELF}"
  TIMEOUT 10)
get_property(registrar GLOBAL PROPERTY HTTPARSE_SPEC_REGISTRAR)
spec_check_equal("${registrar}" "none" "a no-runtime backend registers nothing and does not raise")

spec_expect_all_rejected("${SPEC_SELF}"
  "lane-rejects-unparsed-arguments|unexpected arguments to httparse_add_scheme_lane"
  "lane-requires-name|NAME is required for httparse_add_scheme_lane"
  "lane-requires-backend|BACKEND is required for httparse_add_scheme_lane"
  "lane-requires-program|PROGRAM is required for httparse_add_scheme_lane"
  "lane-requires-timeout|TIMEOUT is required for httparse_add_scheme_lane"
  "lane-requires-sources|SOURCES is required for httparse_add_scheme_lane"
  "lane-requires-existing-program|names a program that does not exist"
  "lane-rejects-missing-source|names a source that does not exist"
  "lane-rejects-duplicate-source-basename|declares two sources sharing a basename"
  "lane-rejects-unknown-backend|is not a Scheme lane backend"
  "lane-rejects-unknown-mode|is not an execution mode this lane module can build a command for")

spec_finish("HttparseSchemeLane")

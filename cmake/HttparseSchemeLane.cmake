# Register one execution lane: a program, run by one runtime, in one mode.
#
# WHY THE COMMAND LINE IS BUILT IN ONE PLACE
#
# Registrations that each spell out their own invocation drift. The detail
# most worth not drifting is invisible when it is wrong: Chez's object-guard
# pair, without which a stale compiled object is silently preferred over the
# source a "source" lane claims to run.
#
# Slice 2 registers only source lanes. The compiled lanes arrive in slice 5 and
# extend this module rather than replacing it.

include_guard(GLOBAL)

include("${CMAKE_CURRENT_LIST_DIR}/HttparseExpectExit.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/HttparseTesting.cmake")

# --- Functional core -------------------------------------------------------

# httparse_lane_measured_copies(<dir> <out_var> <declared-source>...)
#
# Map each declared source to the copy a compiled lane's build step wrote into
# <dir>. Flat and keyed by basename, which is unambiguous because
# httparse_add_scheme_lane refuses a manifest carrying two entries with
# one basename. One rule for every compiled lane: protium needs per-lane
# path logic here precisely because it has no equivalent guard.
function(httparse_lane_measured_copies dir out_var)
  set(copies "")
  foreach(body IN LISTS ARGN)
    get_filename_component(name "${body}" NAME)
    list(APPEND copies "${dir}/${name}")
  endforeach()
  set(${out_var} "${copies}" PARENT_SCOPE)
endfunction()

# httparse_lane_duplicate_basenames(<out_duplicates> <path>...)
#
# Basenames appearing more than once, each reported once however often they
# repeat. Narrowed from the retired repository-wide guard (upstream decision 0006) to
# the one invariant that survives it: httparse_lane_measured_copies keys
# a compiled lane's fingerprint/ copies by basename, so within one lane's
# manifest a repeated basename would make one copy silently overwrite the
# other. Compared with the extension, because the extension is part of the
# copied filename.
function(httparse_lane_duplicate_basenames out_duplicates)
  set(seen "")
  set(duplicates "")
  foreach(path IN LISTS ARGN)
    get_filename_component(base "${path}" NAME)
    if(base IN_LIST seen)
      list(APPEND duplicates "${base}")
    endif()
    list(APPEND seen "${base}")
  endforeach()
  if(duplicates)
    list(REMOVE_DUPLICATES duplicates)
  endif()
  set(${out_duplicates} "${duplicates}" PARENT_SCOPE)
endfunction()

# httparse_chez_aot_paths(<name> <program> <out_object_dir> <out_compiled>)
#
# Where one AOT lane's artifacts live. Keyed by Chez version and machine type
# (HTTPARSE_CHEZ_OBJECT_ROOT) so a parallel build cannot race and no
# object outlives the runtime that produced it, and by LANE NAME -- not
# program -- so two lanes that build the same program from different text
# share nothing. That is not hypothetical: two registered lanes share this
# PROGRAM -- ...self.chez.aot and ...stale-artifact.chez.aot, and the second
# compiles it from deliberately divergent text. Keyed by program stem
# instead, both would resolve to one object directory, one compiled .so, and
# one flat fingerprint/ directory, so the stale lane's copies would silently
# overwrite the real lane's.
function(httparse_chez_aot_paths name program out_object_dir out_compiled)
  string(REPLACE "." "_" name_key "${name}")
  set(dir "${HTTPARSE_CHEZ_OBJECT_ROOT}/${name_key}")
  set(${out_object_dir} "${dir}" PARENT_SCOPE)
  # NAME_WLE strips one extension: harness-self-tests.sps yields
  # harness-self-tests. (The .chez filename infix this comment once preserved
  # retired with the merged wrappers -- upstream decision 0006.)
  get_filename_component(stem "${program}" NAME_WLE)
  set(${out_compiled} "${dir}/${stem}.so" PARENT_SCOPE)
endfunction()

# httparse_scheme_lane_command(<name> <backend> <mode> <program>
#                                  <out_command> <out_measured>
#                                  <out_status> <out_message>
#                                  <declared-source>...)
#
# Status is `ok`, `no-runtime`, `unknown-backend`, or `unknown-mode`. A
# missing runtime is not fatal: the CMake-layer specifications must stay
# runnable on a host with no Scheme installed, so a lane whose runtime was
# never discovered is skipped with a message rather than failing
# configuration. The runtime check runs first, ahead of the mode check that
# can produce `unknown-mode`, for the same reason: a lane naming a mode this
# module cannot build a command for must still fail loudly on a host that has
# the runtime to attempt it, but must not turn `cmake --preset no-scheme` into
# a configure failure over a backend/mode combination the host was never
# going to exercise.
#
# <out_measured> is the list of paths the run will fingerprint, in the order
# the declared sources were given. For a source lane it is the declared list:
# the repository sources are the only text there is. For a compiled lane it is
# the copies the build wrote beside the artifact, so a fingerprint describes
# what the artifact was built from rather than what is on disk now.
#
# Order is load-bearing. harness-fingerprint-combine is order-sensitive by
# design, so measured[i] must correspond to declared[i]; the mapping below
# walks the declared list rather than partitioning and rejoining it.
function(httparse_scheme_lane_command name backend mode program
         out_command out_measured out_status out_message)
  set(${out_command} "" PARENT_SCOPE)
  set(${out_measured} "" PARENT_SCOPE)
  set(${out_message} "" PARENT_SCOPE)

  if(backend STREQUAL "chez")
    if(NOT HTTPARSE_CHEZ_EXECUTABLE)
      set(${out_status} "no-runtime" PARENT_SCOPE)
      set(${out_message}
        "no Chez was discovered, so the chez ${mode} lane for '${program}' is not registered."
        PARENT_SCOPE)
      return()
    endif()

    if(mode STREQUAL "source")
      # Flags, not positions: a lane names one library root per library
      # family it imports, and the count grows with each slice.
      set(${out_command}
        "${HTTPARSE_CHEZ_EXECUTABLE}"
        "--script" "${HTTPARSE_HARNESS_CHEZ_LAUNCHER}"
        "--library-root" "${HTTPARSE_HARNESS_CHEZ_LIBRARY_ROOT}"
        "--library-root" "${HTTPARSE_SRC_CHEZ_LIBRARY_ROOT}"
        "--library-root" "${HTTPARSE_GENERATOR_CHEZ_LIBRARY_ROOT}"
        "--object-guard" "${HTTPARSE_HARNESS_OBJECT_GUARD_DIR}"
        "--program" "${program}"
        PARENT_SCOPE)
      set(${out_measured} ${ARGN} PARENT_SCOPE)
      set(${out_status} "ok" PARENT_SCOPE)
      return()
    endif()

    if(mode STREQUAL "aot")
      httparse_chez_aot_paths("${name}" "${program}" object_dir compiled)
      # --source-guard pairs every --object-dir's SOURCE half with the same
      # always-empty directory the chez.source lane uses as its OBJECT guard
      # (HTTPARSE_HARNESS_OBJECT_GUARD_DIR, set once in
      # test/CMakeLists.txt). A bare directory string handed to
      # library-directories becomes both halves of the pair, so without this
      # an object directory is also a source directory Chez can expand;
      # chez-aot.ss's own header records the measurement.
      set(${out_command}
        "${HTTPARSE_CHEZ_EXECUTABLE}"
        "--script" "${HTTPARSE_HARNESS_CHEZ_AOT_LAUNCHER}"
        "--object-dir" "${object_dir}/harness"
        "--object-dir" "${object_dir}/src"
        "--source-guard" "${HTTPARSE_HARNESS_OBJECT_GUARD_DIR}"
        "--program" "${compiled}"
        PARENT_SCOPE)
      httparse_lane_measured_copies("${object_dir}/fingerprint" measured ${ARGN})
      set(${out_measured} ${measured} PARENT_SCOPE)
      set(${out_status} "ok" PARENT_SCOPE)
      return()
    endif()

    set(${out_status} "unknown-mode" PARENT_SCOPE)
    set(${out_message}
      "'${mode}' is not an execution mode this lane module can build a command for. Known modes: source aot."
      PARENT_SCOPE)
    return()
  endif()

  set(${out_status} "unknown-backend" PARENT_SCOPE)
  set(${out_message}
    "'${backend}' is not a Scheme lane backend. Known backends: chez."
    PARENT_SCOPE)
endfunction()

# --- Imperative shell ------------------------------------------------------

# httparse_lane_chez_aot_artifacts(<name> <program> <stale_library_root>
#                                      <declared-source>...)
#
# Build one aot lane's compiled program and, in the SAME custom command, the
# fingerprint/ copies of the sources it was built from. One command is the
# whole of decision W6: the object and the copies then have one producer and
# cannot be separately stale, which is what makes the copies evidence about
# the artifact rather than a second reading of the source tree.
#
# The DEPENDS list is the other half. Every .sls under both library roots is
# a compile input (compile-imported-libraries), so every one of them must be
# able to re-trigger this command; a library missing from this list would
# leave the artifact -- and its copies -- describing the previous text, which
# is the exact defect class upstream decision 0004 demonstrated.
#
# <stale_library_root> is empty for every lane that is meant to pass. When it
# is set (the staleness lane, Task 3 of the remainder plan), it is prefixed
# as one extra (source root -> object dir) pair sharing the harness object
# directory, so a library present there at its library-relative path is the
# one compiled in -- and the copy step below takes each declared source from
# wherever the compile found it, so the measured copies stay evidence about
# the artifact under staleness too. The declared list, and therefore the
# expectation, is never touched by this parameter.
function(httparse_lane_chez_aot_artifacts name program stale_library_root)
  httparse_chez_aot_paths("${name}" "${program}" object_dir compiled)

  # Prefixed, not appended: Chez consults library-directories entries in
  # order and takes the first source it can resolve (measured for this exact
  # shape -- design section 5.3's remainder addendum), so a library present
  # in the stale root shadows the real one for the compile while every
  # library absent there still resolves from the real roots.
  set(stale_pair_args "")
  if(stale_library_root)
    list(APPEND stale_pair_args
      --library-root "${stale_library_root}"
      --object-dir "${object_dir}/harness")
  endif()

  # The copy step takes each declared source from wherever the compile step
  # will have found it. A declared source is shadowed exactly when the stale
  # root holds a file at the same path relative to the harness library root;
  # sources outside that root (the program, src/ libraries) are never
  # shadowed, because the stale pair above is the harness pair's shadow and
  # nothing else's.
  set(sources_of_record "")
  foreach(body IN LISTS ARGN)
    set(source_of_record "${body}")
    if(stale_library_root)
      string(FIND "${body}" "${HTTPARSE_HARNESS_CHEZ_LIBRARY_ROOT}/" at)
      if(at EQUAL 0)
        string(REPLACE "${HTTPARSE_HARNESS_CHEZ_LIBRARY_ROOT}/" ""
               relative "${body}")
        if(EXISTS "${stale_library_root}/${relative}")
          set(source_of_record "${stale_library_root}/${relative}")
        endif()
      endif()
    endif()
    list(APPEND sources_of_record "${source_of_record}")
  endforeach()

  httparse_lane_measured_copies("${object_dir}/fingerprint" copies ${ARGN})
  set(copy_commands "")
  list(LENGTH ARGN source_count)
  math(EXPR last "${source_count} - 1")
  foreach(i RANGE 0 ${last})
    list(GET sources_of_record ${i} source_of_record)
    list(GET copies ${i} copy)
    list(APPEND copy_commands
      COMMAND "${CMAKE_COMMAND}" -E copy_if_different
              "${source_of_record}" "${copy}")
  endforeach()

  # The generator arrives as a submodule (decision 0005). An unpopulated
  # submodule is a directory that exists and is empty, which would otherwise
  # surface as a confusing missing-library error inside Chez rather than here.
  if(NOT EXISTS "${HTTPARSE_GENERATOR_CHEZ_LIBRARY_ROOT}")
    message(FATAL_ERROR
      "httparse: the generator library root "
      "${HTTPARSE_GENERATOR_CHEZ_LIBRARY_ROOT} does not exist. The submodule "
      "is not checked out: run 'git submodule update --init --recursive'.")
  endif()

  # Configure-time glob, deliberately without CONFIGURE_DEPENDS: a new
  # library arrives with a SOURCES edit in test/CMakeLists.txt, which forces
  # the reconfigure this glob needs anyway. Empty is a fatal error, not a
  # lane with no dependencies: a lane that depends on nothing goes on
  # passing against the previous text.
  file(GLOB_RECURSE chez_library_sources
    "${HTTPARSE_HARNESS_CHEZ_LIBRARY_ROOT}/*.sls"
    "${HTTPARSE_SRC_CHEZ_LIBRARY_ROOT}/*.sls"
    "${HTTPARSE_GENERATOR_CHEZ_LIBRARY_ROOT}/*.sls")
  if(NOT chez_library_sources)
    message(FATAL_ERROR
      "httparse: no Chez library sources were found under "
      "${HTTPARSE_HARNESS_CHEZ_LIBRARY_ROOT} or "
      "${HTTPARSE_SRC_CHEZ_LIBRARY_ROOT}. That means this glob is wrong, "
      "not that the aot lane has nothing to depend on.")
  endif()

  add_custom_command(
    OUTPUT "${compiled}"
    COMMAND "${CMAKE_COMMAND}" -E make_directory "${object_dir}/harness"
    COMMAND "${CMAKE_COMMAND}" -E make_directory "${object_dir}/src"
    COMMAND "${CMAKE_COMMAND}" -E make_directory "${object_dir}/fingerprint"
    COMMAND "${HTTPARSE_CHEZ_EXECUTABLE}" --script
            "${HTTPARSE_HARNESS_CHEZ_COMPILE_LAUNCHER}"
            ${stale_pair_args}
            --library-root "${HTTPARSE_HARNESS_CHEZ_LIBRARY_ROOT}"
            --object-dir "${object_dir}/harness"
            --library-root "${HTTPARSE_SRC_CHEZ_LIBRARY_ROOT}"
            --object-dir "${object_dir}/src"
            --library-root "${HTTPARSE_GENERATOR_CHEZ_LIBRARY_ROOT}"
            --object-dir "${object_dir}/generator"
            --program "${program}"
            --output "${compiled}"
    ${copy_commands}
    DEPENDS "${program}"
            "${HTTPARSE_HARNESS_CHEZ_COMPILE_LAUNCHER}"
            "${HTTPARSE_HARNESS_CHEZ_AOT_LAUNCHER}"
            ${chez_library_sources}
            ${sources_of_record}
    COMMENT "httparse: Chez aot compile for ${name}"
    VERBATIM)

  string(REPLACE "." "_" stem "${name}")
  add_custom_target("httparse_chez_aot_${stem}" DEPENDS "${compiled}")
  if(NOT TARGET httparse_chez_aot)
    add_custom_target(httparse_chez_aot ALL)
  endif()
  add_dependencies(httparse_chez_aot "httparse_chez_aot_${stem}")
endfunction()

# httparse_add_scheme_lane(NAME <name> BACKEND <chez> PROGRAM <path>
#                              TIMEOUT <seconds> SOURCES <path>...
#                              [EXPECT_EXIT <code>] [WRONG_FINGERPRINT]
#                              [STALE_LIBRARY_ROOT <dir>]
#                              [WORKING_DIRECTORY <dir>]
#                              [LABELS ...] [ENVIRONMENT ...])
#
# NAME, BACKEND, PROGRAM, TIMEOUT and SOURCES are required. The name's
# fifth field is the execution mode; the registrar derives it, so a
# registration here cannot claim one lane while running another.
#
# WRONG_FINGERPRINT hands the lane an expectation the run cannot match, and
# STALE_LIBRARY_ROOT compiles the artifact from any library the given root
# holds at its library-relative path while the declared SOURCES keep naming
# the real one. Both exist to make a passing provenance check falsifiable;
# neither belongs on a lane that is meant to pass.
#
# With EXPECT_EXIT the lane is registered through the exact-status helper;
# without it, a nonzero exit fails the test in the ordinary way.
function(httparse_add_scheme_lane)
  cmake_parse_arguments(PARSE_ARGV 0 arg "WRONG_FINGERPRINT"
    "NAME;BACKEND;PROGRAM;TIMEOUT;EXPECT_EXIT;WORKING_DIRECTORY;STALE_LIBRARY_ROOT"
    "LABELS;ENVIRONMENT;SOURCES")

  if(arg_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR
      "httparse: unexpected arguments to httparse_add_scheme_lane: ${arg_UNPARSED_ARGUMENTS}")
  endif()
  # SOURCES is required, not optional. The property worth having is not "the
  # lanes have provenance" but "a lane cannot be added without its manifest"
  # -- and this configure-time check is the whole of that guarantee, because
  # the harness skips provenance rather than refusing when no manifest reaches
  # it. It matters little here, where every lane is a source lane, and a great
  # deal in slices 5b and 5c, where a lane registered without provenance is
  # exactly the lane that can silently fall back to source.
  foreach(required NAME BACKEND PROGRAM TIMEOUT SOURCES)
    if(NOT arg_${required})
      message(FATAL_ERROR
        "httparse: ${required} is required for httparse_add_scheme_lane ('${arg_NAME}').")
    endif()
  endforeach()
  if(NOT EXISTS "${arg_PROGRAM}")
    message(FATAL_ERROR
      "httparse: '${arg_NAME}' names a program that does not exist: "
      "${arg_PROGRAM}. A lane registered against a missing file would fail at "
      "run time with a runtime error rather than at configure time with this one.")
  endif()
  # A manifest entry that does not exist would be a provenance failure at run
  # time, reported by the harness as though the build tree were incomplete. It
  # is a registration mistake, and it is cheaper to say so here.
  foreach(body IN LISTS arg_SOURCES)
    if(NOT EXISTS "${body}")
      message(FATAL_ERROR
        "httparse: '${arg_NAME}' names a source that does not exist: "
        "${body}.")
    endif()
  endforeach()

  # Within one lane's manifest, basenames must be unique: the flat
  # fingerprint/ copy directory of the aot branch keys measured copies by
  # basename. This replaced the repository-wide basename guard when the
  # include namespace it policed retired (upstream decision 0006).
  httparse_lane_duplicate_basenames(duplicate_basenames ${arg_SOURCES})
  if(duplicate_basenames)
    message(FATAL_ERROR
      "httparse: '${arg_NAME}' declares two sources sharing a basename: "
      "${duplicate_basenames}. httparse_lane_measured_copies keys a "
      "compiled lane's fingerprint/ copies by basename, so one would "
      "silently overwrite the other.")
  endif()

  # Within this registrar the name is the single source of the mode, so a
  # registration here cannot claim one lane while running another. It is not the
  # only place the repository sets HTTPARSE_EXECUTION_MODE: nine
  # registrations in test/CMakeLists.txt (search that name) bypass this function
  # and hand-set it directly instead, and nothing enforces those the way this
  # parse does. Eight name a .chez.source lane and hand-set "source", so they
  # agree literally. The ninth, httparse.harness.scheme-mutation.cmake.direct,
  # does not describe itself at all: its name's mode field is "direct", a
  # cmake-backend value disjoint from the source/aot/o1 vocabulary, and the
  # "source" it sets is for the lanes it stages and runs. There is nothing there
  # for agreement to mean, which is why this comment does not claim it.
  # httparse_add_test parses the same name again for its labels; the
  # function is pure, so parsing it twice is cheaper than passing a parsed field
  # through a registrar that does not need it.
  httparse_test_name_parse("${arg_NAME}" lane_layer lane_feature
                               lane_backend lane_mode)

  httparse_scheme_lane_command(
    "${arg_NAME}" "${arg_BACKEND}" "${lane_mode}" "${arg_PROGRAM}"
    command measured status message ${arg_SOURCES})

  if(status STREQUAL "unknown-backend"
     OR status STREQUAL "unknown-mode")
    message(FATAL_ERROR "httparse: ${message}")
  endif()
  if(status STREQUAL "no-runtime")
    message(STATUS "httparse: skipping ${arg_NAME} -- ${message}")
    return()
  endif()

  # The shell half of the aot lane. Guarded on the mode rather than on the
  # backend, so adding a backend does not silently acquire this rule; by this
  # point status is `ok`, so a chez executable is known to exist.
  if(lane_mode STREQUAL "aot")
    httparse_lane_chez_aot_artifacts(
      "${arg_NAME}" "${arg_PROGRAM}" "${arg_STALE_LIBRARY_ROOT}" ${arg_SOURCES})
  endif()

  # The lane registration declares the execution mode; the launcher never
  # touches this variable. For the Chez lane, the launcher's object guard is
  # what makes the declaration unfalsifiable: it makes a compiled object
  # impossible to load.
  #
  # The fixture is immutable and lives in the source tree; a lane only ever
  # reads it. Set for every lane rather than only the self-tests, so a program
  # that starts needing it does not also need a registration change.
  #
  # arg_ENVIRONMENT is deliberately not spliced in here: CTest applies
  # ENVIRONMENT entries in list order, so for a repeated key the last one wins.
  # It is appended once, after every default this function computes for itself
  # (including the manifest block below), so a caller-supplied entry can always
  # override a default -- which is exactly how the provenance lanes in
  # test/CMakeLists.txt force a specific, named failure: by overriding
  # HTTPARSE_FINGERPRINT_FILES or HTTPARSE_EXPECT_FINGERPRINT_FILE after
  # this function has already computed the real ones.
  set(environment
    "HTTPARSE_EXECUTION_MODE=${lane_mode}"
    "HTTPARSE_FINGERPRINT_SAMPLE=${CMAKE_SOURCE_DIR}/test/fixtures/fingerprint-sample.bin")

  # The manifest, and the expectation it must agree with. The separator is `|`
  # rather than a path separator: `:` and `;` differ between platforms, and `|`
  # is illegal in a Windows path, so it cannot occur inside a member.
  #
  # Gated on a discovered Chez, because httparse_expected_fingerprint runs
  # the expectation launcher under Chez. With chez the only backend this
  # function routes to `ok`, the guard cannot be false by the time this line
  # runs -- a chez lane with no discovered Chez already took the no-runtime
  # return above. It stays explicit rather than assumed: the manifest block
  # should not depend on control flow elsewhere in this function to know when
  # a fingerprint can be computed.
  if(HTTPARSE_CHEZ_EXECUTABLE)
    string(JOIN "|" fingerprint_files ${measured})
    if(arg_WRONG_FINGERPRINT)
      httparse_wrong_fingerprint("${arg_NAME}" expect_file)
    else()
      httparse_expected_fingerprint("${arg_NAME}" expect_file
                                        ${arg_SOURCES})
    endif()
    list(APPEND environment
      "HTTPARSE_FINGERPRINT_FILES=${fingerprint_files}"
      "HTTPARSE_EXPECT_FINGERPRINT_FILE=${expect_file}")
  endif()

  # See the comment above the initial set(environment ...): appended last so a
  # caller-supplied entry always wins over a default, including the two above.
  list(APPEND environment ${arg_ENVIRONMENT})

  # Same CMP0174 reasoning as httparse_add_exit_code_test in
  # HttparseExpectExit.cmake: forward WORKING_DIRECTORY only when there is
  # a value, rather than forwarding an empty one unconditionally.
  set(working_directory_args "")
  if(arg_WORKING_DIRECTORY)
    set(working_directory_args WORKING_DIRECTORY "${arg_WORKING_DIRECTORY}")
  endif()

  if(DEFINED arg_EXPECT_EXIT)
    httparse_add_exit_code_test(
      NAME "${arg_NAME}"
      COMMAND ${command}
      EXPECT_EXIT "${arg_EXPECT_EXIT}"
      TIMEOUT "${arg_TIMEOUT}"
      LABELS ${arg_LABELS}
      ${working_directory_args}
      ENVIRONMENT ${environment})
  else()
    httparse_add_test(
      NAME "${arg_NAME}"
      COMMAND ${command}
      TIMEOUT "${arg_TIMEOUT}"
      LABELS ${arg_LABELS}
      ${working_directory_args}
      ENVIRONMENT ${environment})
  endif()
endfunction()

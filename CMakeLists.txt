# chez-httparse: an HTTP/1 parser for Chez Scheme.
#
# CMake is the canonical build frontend on every platform, with a thin Makefile
# over it for the usual Unix entry points.
#
# The 3.26 floor is set by the preset schema this project uses -- version 6,
# which requires 3.25 -- plus a margin. It is not what enables JUnit output or
# refusing an empty test selection; both of those arrive earlier, in 3.21. Only
# 4.3.3 has actually been exercised, so 3.26 is a declared floor rather than a
# tested one.
#
# LANGUAGES NONE is deliberate: chez-httparse has no C of its own, so asking
# CMake for a C compiler would impose a requirement the project does not have.
cmake_minimum_required(VERSION 3.26)

project(chez-httparse
  VERSION 0.1.0
  DESCRIPTION "HTTP/1 parser for Chez Scheme"
  HOMEPAGE_URL "https://github.com/Kiyomi-Computation-Systems/chez-httparse"
  LANGUAGES NONE)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_LIST_DIR}/cmake")

option(HTTPARSE_BUILD_TESTS "Build the test suite" ${PROJECT_IS_TOP_LEVEL})

# Discovery is opt-out so the CMake-layer specifications can be configured and
# run on a host with no Scheme installed. Every lane that needs a runtime is
# registered only when its runtime was found.
option(HTTPARSE_REQUIRE_CHEZ "Require a usable Chez Scheme at configure time" ON)

include(HttparseChez)

if(HTTPARSE_REQUIRE_CHEZ)
  httparse_chez_discover()
endif()

# src/generated/ is DERIVED from src/httparse/grammar.sls and committed, so that
# what this project ships is reviewable as a diff and loadable without a
# generator. This target and the determinism lane run the SAME script, so a
# refresh cannot drift from the check that guards it -- the same rule the
# vendored corpus follows.
if(HTTPARSE_CHEZ_EXECUTABLE)
  add_custom_target(httparse_parser_refresh
    COMMAND "${HTTPARSE_CHEZ_EXECUTABLE}"
            --libdirs "${CMAKE_SOURCE_DIR}/src:${CMAKE_SOURCE_DIR}/vendor/byte-machine/src"
            --script "${CMAKE_SOURCE_DIR}/tools/emit-machine.ss"
            --machine message
            --output "${CMAKE_SOURCE_DIR}/src/generated/httparse-message.sls"
    COMMAND "${HTTPARSE_CHEZ_EXECUTABLE}"
            --libdirs "${CMAKE_SOURCE_DIR}/src:${CMAKE_SOURCE_DIR}/vendor/byte-machine/src"
            --script "${CMAKE_SOURCE_DIR}/tools/emit-machine.ss"
            --machine url
            --output "${CMAKE_SOURCE_DIR}/src/generated/httparse-url.sls"
    COMMENT "httparse: re-emitting the generated parsers"
    VERBATIM)
endif()

if(HTTPARSE_BUILD_TESTS)
  enable_testing()
  # CTest will not create the directory for --output-junit itself.
  file(MAKE_DIRECTORY "${CMAKE_BINARY_DIR}/test-results")
  include(HttparseTesting)
  include(HttparseExpectExit)
  include(HttparseSchemeLane)
  add_subdirectory(test)
endif()

message(STATUS
  "chez-httparse ${PROJECT_VERSION}: tests=${HTTPARSE_BUILD_TESTS} "
  "chez=${HTTPARSE_REQUIRE_CHEZ}")

# Specification for the functional core of cmake/HttparseTesting.cmake.
#
# The registration helper decides which tests exist at all, so a defect here is
# invisible in the worst way: a malformed or duplicated registration produces a
# suite that runs fewer tests than it appears to and still reports success. Each
# rule is therefore enforced at configure time and specified before anything
# relies on it.

cmake_minimum_required(VERSION 3.26)

include("${CMAKE_CURRENT_LIST_DIR}/../../../cmake/HttparseTesting.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/SpecSupport.cmake")

set(SPEC_SELF "${CMAKE_CURRENT_LIST_FILE}")

if(DEFINED HTTPARSE_SPEC_CASE)
  set(c "${HTTPARSE_SPEC_CASE}")

  # add_test and set_tests_properties belong to a project context this script
  # does not have. Stubbing both lets the registrar's own validation be
  # exercised: without it a case would die on that unrelated error instead of
  # falling through to the "must be rejected" check.
  function(add_test)
  endfunction()
  function(set_tests_properties)
  endfunction()

  if(c STREQUAL "too-few-segments")
    httparse_test_name_parse("httparse.unit.graph.chez" l f b m)
  elseif(c STREQUAL "uppercase")
    httparse_test_name_parse("httparse.unit.Graph.chez.source" l f b m)
  elseif(c STREQUAL "wrong-prefix")
    httparse_test_name_parse("httpparse.unit.graph.chez.source" l f b m)
  elseif(c STREQUAL "unknown-layer")
    httparse_test_name_parse("httparse.smoke.graph.chez.source" l f b m)
  elseif(c STREQUAL "unknown-backend")
    httparse_test_name_parse("httparse.unit.graph.guile.source" l f b m)
  elseif(c STREQUAL "incompatible-mode")
    # Chez has no .o1 lane; the mode exists but not for this backend.
    httparse_test_name_parse("httparse.unit.graph.chez.o1" l f b m)
  elseif(c STREQUAL "feature-leading-hyphen")
    httparse_test_name_parse("httparse.unit.-graph.chez.source" l f b m)
  elseif(c STREQUAL "feature-trailing-hyphen")
    httparse_test_name_parse("httparse.unit.graph-.chez.source" l f b m)
  elseif(c STREQUAL "unknown-label")
    httparse_test_validate_labels(unit bogus)
  elseif(c STREQUAL "duplicate-name")
    httparse_test_reserve_name("httparse.unit.graph.chez.source")
    httparse_test_reserve_name("httparse.unit.graph.chez.source")
  elseif(c STREQUAL "missing-timeout")
    httparse_test_require_timeout("" "httparse.unit.graph.chez.source")
  elseif(c STREQUAL "zero-timeout")
    httparse_test_require_timeout("0" "httparse.unit.graph.chez.source")
  elseif(c STREQUAL "noninteger-timeout")
    httparse_test_require_timeout("30s" "httparse.unit.graph.chez.source")
  elseif(c STREQUAL "registration-rejects-absent-working-directory")
    httparse_add_test(
      NAME httparse.harness.example.cmake.direct
      COMMAND "/bin/true"
      TIMEOUT 10
      WORKING_DIRECTORY "/there/is/no/such/directory")
  else()
    message(FATAL_ERROR "httparse-spec: unknown case '${c}'")
  endif()

  message(FATAL_ERROR "httparse-spec: case '${c}' was accepted but must be rejected")
endif()

# --- Positive --------------------------------------------------------------

httparse_test_name_parse("httparse.unit.graph.chez.source" l f b m)
spec_check_equal("${l}" "unit" "layer")
spec_check_equal("${f}" "graph" "feature")
spec_check_equal("${b}" "chez" "backend")
spec_check_equal("${m}" "source" "mode")

# Every backend/mode pair the project actually has a lane for must parse. These
# are the three lanes of the execution model, and a helper that rejected one
# would silently delete that lane's coverage.
foreach(pair "chez.source" "chez.aot" "cmake.direct")
  httparse_test_name_parse("httparse.unit.graph.${pair}" l f b m)
endforeach()

# A multi-word feature with interior hyphens is fine; only the edges are barred.
httparse_test_name_parse("httparse.differential.span-boundary.chez.aot" l f b m)
spec_check_equal("${f}" "span-boundary" "hyphenated feature")

httparse_test_validate_labels(unit chez source)
httparse_test_reserve_name("httparse.unit.unique-one.chez.source")
httparse_test_reserve_name("httparse.unit.unique-two.chez.source")
httparse_test_require_timeout("120" "httparse.unit.graph.chez.source")

# --- The run directory ------------------------------------------------------
#
# Which directory a lane launches from is a decision, and a registration may
# override it. Specified against the pure function
# rather than through httparse_add_test: the registrar calls add_test, which
# script mode does not have, and creates directories, which a specification must
# not do to whatever tree it happens to be run from.
httparse_test_run_directory("httparse.harness.example.cmake.direct" "" derived)
spec_check_equal("${derived}" "${CMAKE_BINARY_DIR}/test-run/httparse.harness.example.cmake.direct"
  "with no override, the run directory is derived from the test name")

httparse_test_run_directory("httparse.harness.example.cmake.direct" "/some/where" chosen)
spec_check_equal("${chosen}" "/some/where" "an override is used verbatim")

# The empty string is the shape a caller that omitted WORKING_DIRECTORY produces,
# and it must mean "derive", not "launch from the filesystem root".
httparse_test_run_directory("httparse.harness.other.cmake.direct" "" empty_override)
spec_check_equal("${empty_override}" "${CMAKE_BINARY_DIR}/test-run/httparse.harness.other.cmake.direct"
  "an empty override still derives, and derives from this name")

# --- Negative --------------------------------------------------------------

set(negative_cases
  "too-few-segments|httparse: malformed test name"
  "uppercase|httparse: malformed test name"
  "wrong-prefix|httparse: malformed test name"
  "unknown-layer|httparse: unknown test layer 'smoke'"
  "unknown-backend|httparse: unknown test backend 'guile'"
  "incompatible-mode|httparse: incompatible backend/mode"
  "feature-leading-hyphen|Feature segment '-graph' must not begin or end with a hyphen"
  "feature-trailing-hyphen|Feature segment 'graph-' must not begin or end with a hyphen"
  "unknown-label|httparse: unknown test label 'bogus'"
  "duplicate-name|httparse: duplicate test name"
  "missing-timeout|httparse: TIMEOUT is required"
  "zero-timeout|httparse: TIMEOUT for .* must be a positive whole number"
  "noninteger-timeout|httparse: TIMEOUT for .* must be a positive whole number"
  "registration-rejects-absent-working-directory|is not an existing directory")

spec_expect_all_rejected("${SPEC_SELF}" ${negative_cases})

spec_finish("HttparseTesting")

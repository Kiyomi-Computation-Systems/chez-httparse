# Specification for cmake/HttparseProbe.cmake.
#
# Runtime discovery works by running a small script and reading `key=value`
# lines back. The reading is where it fails quietly. `string(REGEX MATCH)` sets
# no result variable of its own: on a miss it leaves the *previous* regex's
# captures in CMAKE_MATCH_1, so a reader that does not first check the match
# gets a plausible wrong answer -- a machine type belonging to another question
# -- rather than an error. That is why this helper exists, and why it is
# specified before either runtime module relies on it.
#
# Two modes. Positive assertions run inline. Each rejection is proved by a child
# `cmake -P` of this same file, which must exit nonzero *and* print its declared
# diagnostic; a case that fails for the wrong reason is not a passing case.

cmake_minimum_required(VERSION 3.26)

include("${CMAKE_CURRENT_LIST_DIR}/../../../cmake/HttparseProbe.cmake")

include("${CMAKE_CURRENT_LIST_DIR}/SpecSupport.cmake")

set(SPEC_SELF "${CMAKE_CURRENT_LIST_FILE}")

set(good_output "full-version=Chez Scheme Version 10.4.1
machine-type=tarm64osx
threaded=yes")

if(DEFINED HTTPARSE_SPEC_CASE)
  set(c "${HTTPARSE_SPEC_CASE}")

  if(c STREQUAL "missing-field")
    httparse_probe_field("${good_output}" "architecture" value "the chez probe")
  elseif(c STREQUAL "empty-value")
    httparse_probe_field("machine-type=" "machine-type" value "the chez probe")
  elseif(c STREQUAL "empty-output")
    httparse_probe_field("" "machine-type" value "the chez probe")
  elseif(c STREQUAL "ghostscript-banner")
    # What Ghostscript actually prints on this development host: real,
    # well-formed output from a program that is not the runtime being probed
    # for. It exits 0 while doing it, so only the content of the output can
    # tell them apart.
    httparse_probe_field("GPL Ghostscript 10.07.1 (2026-05-19)
Copyright (C) 2026 Artifex Software, Inc.  All rights reserved."
      "version" value "a probe")
  elseif(c STREQUAL "key-only-a-suffix")
    # 'version' must not be satisfied by the 'full-version' line. A helper that
    # matched anywhere in a line would report Chez's whole banner as the version
    # and look very nearly right.
    httparse_probe_field("${good_output}" "version" value "the chez probe")
  else()
    message(FATAL_ERROR "httparse-spec: unknown case '${c}'")
  endif()

  message(FATAL_ERROR "httparse-spec: case '${c}' was accepted but must be rejected")
endif()

# --- Driver ----------------------------------------------------------------

# Positive: every field is readable, including one whose value contains spaces.
httparse_probe_field("${good_output}" "full-version" v "the chez probe")
spec_check_equal("${v}" "Chez Scheme Version 10.4.1" "full-version with spaces")

httparse_probe_field("${good_output}" "machine-type" v "the chez probe")
spec_check_equal("${v}" "tarm64osx" "machine-type")

# The first line is reachable without a preceding newline.
httparse_probe_field("only=first" "only" v "a probe")
spec_check_equal("${v}" "first" "field on the first line")

# Carriage returns are stripped, so a Windows child cannot yield 'yes\r' and
# compare unequal to everything.
httparse_probe_field("threaded=yes\r\nmachine-type=ta6nt\r\n" "threaded" v "a probe")
spec_check_equal("${v}" "yes" "value with a stripped carriage return")
httparse_probe_field("threaded=yes\r\nmachine-type=ta6nt\r\n" "machine-type" v "a probe")
spec_check_equal("${v}" "ta6nt" "second field after a carriage return")

# A value may itself contain '='. Only the first one separates. A compiler
# invocation is a natural example: config=CC=gcc-16 embeds one in the value.
httparse_probe_field("config=CC=gcc-16" "config" v "a probe")
spec_check_equal("${v}" "CC=gcc-16" "value containing an equals sign")

# The defect this helper exists to prevent: a failed lookup must not return the
# previous lookup's value. CMAKE_MATCH_1 is deliberately dirtied first.
# The dirtying regex must populate the *same* capture index the accessor reads
# (CMAKE_MATCH_2), or this assertion proves nothing: a stale-returning accessor
# would hand back an unset variable and look correct. Mutation testing caught
# exactly that when the precondition only dirtied CMAKE_MATCH_1.
#
# MEASURED LIMIT OF THIS ASSERTION
#
# CMake 4.3.3 clears CMAKE_MATCH_<n> when a match fails, so on this version an
# accessor that returned CMAKE_MATCH_2 instead of "" is indistinguishable from
# one that returns "": that specific mutation survives, and is declared as
# EXPECT_SURVIVES in the mutation suite. The clear stays because the project's
# declared floor is CMake 3.26, where older behaviour is in range; it is
# defensive code for versions this host cannot exercise, not dead code.
#
# The exemption is narrow, and it is worth being precise about why. It covers
# only *what value* the branch writes. It does not cover whether the branch runs
# at all: deleting it leaves the output variable untouched, which is a
# version-independent defect and is caught here by the seeding above. Widening
# the recorded limitation to "the clear cannot be tested" would have hidden
# that.
string(REGEX MATCH "(machine-type)=(tarm64osx)" _ "${good_output}")
spec_check_equal("${CMAKE_MATCH_2}" "tarm64osx" "precondition: CMAKE_MATCH_2 is dirty")
# Seeded first. Asserting that an output is empty proves nothing when an unset
# variable is also empty: without this, an accessor that simply never writes the
# output satisfies the assertion exactly as well as one that clears it, and
# deleting the clearing branch outright leaves this spec green.
set(absent "<<unwritten>>")
httparse_probe_field_optional("${good_output}" "architecture" absent)
spec_check_equal("${absent}" "" "an absent optional field yields empty, not the stale match")

# Anchoring belongs to the optional accessor too. Without this, a 'version'
# lookup satisfied by the 'full-version' line would be caught in one accessor
# and silently wrong in the other.
httparse_probe_field_optional("${good_output}" "version" suffix_only)
spec_check_equal("${suffix_only}" "" "an optional lookup is not satisfied by a longer key")

httparse_probe_field_optional("${good_output}" "threaded" present)
spec_check_equal("${present}" "yes" "a present optional field still yields its value")

# --- Negative cases --------------------------------------------------------

set(negative_cases
  "missing-field|httparse: the chez probe produced no 'architecture' field"
  "empty-value|httparse: the chez probe reported an empty 'machine-type' field"
  "empty-output|httparse: the chez probe produced no 'machine-type' field"
  "ghostscript-banner|httparse: a probe produced no 'version' field"
  "key-only-a-suffix|httparse: the chez probe produced no 'version' field")

spec_expect_all_rejected("${SPEC_SELF}" ${negative_cases})

spec_finish("HttparseProbe")

# Specification: the vendored llhttp corpus is upstream's bytes, unmodified.
#
# The corpus is vendored as data and is never edited: a fixture we come to
# believe is wrong becomes a ratchet entry and a decision record, never a
# change to these bytes, because a golden we may edit when it disagrees with us
# is not a golden. A rule like that is worthless as prose -- the whole
# failure mode is someone "just fixing" a fixture to make a lane green, which
# reads as a reasonable diff -- so it is a registered check instead (AGENTS.md:
# prefer a check to a comment).
#
# WHAT IS ASSERTED, AND WHY IT IS TWO-WAY. Three independent things:
#
#   1. every path PROVENANCE lists exists and hashes to the recorded SHA-256;
#   2. every file present on disk is listed in PROVENANCE;
#   3. the declared file-count matches the number of sha256 lines.
#
# (1) alone catches a corrupted or edited fixture. It does NOT catch a file
# added to the directory without being recorded -- which is how a local
# "temporary" fixture becomes permanent, indistinguishable from vendored data,
# and eventually cited as upstream behaviour. (2) is what makes the directory
# mean what it claims. (3) catches the regeneration that silently dropped
# entries: a PROVENANCE rewritten with fewer files than it copied would satisfy
# both (1) and (2) on the smaller set.
#
# PROVENANCE itself is excluded from (2) -- it cannot record its own hash.

cmake_minimum_required(VERSION 3.26)

include_guard(GLOBAL)
include("${CMAKE_CURRENT_LIST_DIR}/SpecSupport.cmake")

get_filename_component(_corpus_root "${CMAKE_CURRENT_LIST_DIR}/../../.." ABSOLUTE)
set(_corpus_dir "${_corpus_root}/test/vendor/llhttp")
set(_corpus_provenance "${_corpus_dir}/PROVENANCE")

if(NOT EXISTS "${_corpus_provenance}")
  spec_record_failure()
  message(SEND_ERROR
    "httparse-spec: no PROVENANCE at '${_corpus_provenance}'. "
    "Vendor the corpus with: cmake -DLLHTTP_ROOT=<checkout> -P cmake/HttparseCorpusRefresh.cmake")
  spec_finish("corpus provenance")
  return()
endif()

file(READ "${_corpus_provenance}" _corpus_text)
string(REPLACE ";" "\;" _corpus_text "${_corpus_text}")
string(REPLACE "\n" ";" _corpus_lines "${_corpus_text}")

set(_corpus_declared_count "")
set(_corpus_listed "")
set(_corpus_checked 0)

foreach(_line IN LISTS _corpus_lines)
  if(_line MATCHES "^file-count: ([0-9]+)$")
    set(_corpus_declared_count "${CMAKE_MATCH_1}")
  elseif(_line MATCHES "^sha256 ([0-9a-f]+) (.+)$")
    set(_expected "${CMAKE_MATCH_1}")
    set(_rel "${CMAKE_MATCH_2}")
    list(APPEND _corpus_listed "${_rel}")
    math(EXPR _corpus_checked "${_corpus_checked} + 1")

    if(NOT EXISTS "${_corpus_dir}/${_rel}")
      spec_record_failure()
      message(SEND_ERROR "httparse-spec: PROVENANCE lists '${_rel}' but it is missing from the corpus")
      continue()
    endif()

    file(SHA256 "${_corpus_dir}/${_rel}" _actual)
    if(NOT _actual STREQUAL _expected)
      spec_record_failure()
      message(SEND_ERROR
        "httparse-spec: '${_rel}' does not match PROVENANCE. "
        "Vendored corpus files are never edited: "
        "restore them with cmake -DLLHTTP_ROOT=<checkout> -P cmake/HttparseCorpusRefresh.cmake. "
        "expected ${_expected}, got ${_actual}")
    endif()
  endif()
endforeach()

# (3) the declared count
if(_corpus_declared_count STREQUAL "")
  spec_record_failure()
  message(SEND_ERROR "httparse-spec: PROVENANCE declares no file-count")
else()
  spec_check_equal("${_corpus_checked}" "${_corpus_declared_count}"
                   "PROVENANCE sha256 lines against its declared file-count")
endif()

# An empty corpus must be a failure, never a silent pass -- the same rule the
# test presets, the mutation engine and the Scheme harness all keep.
if(_corpus_checked EQUAL 0)
  spec_record_failure()
  message(SEND_ERROR "httparse-spec: PROVENANCE records no files; an empty corpus is a failure")
endif()

# (2) nothing on disk is unrecorded
file(GLOB_RECURSE _corpus_present RELATIVE "${_corpus_dir}" "${_corpus_dir}/*")
foreach(_rel IN LISTS _corpus_present)
  if(_rel STREQUAL "PROVENANCE")
    continue()
  endif()
  if(NOT "${_rel}" IN_LIST _corpus_listed)
    spec_record_failure()
    message(SEND_ERROR
      "httparse-spec: '${_rel}' is in the corpus but not recorded in PROVENANCE. "
      "Nothing enters test/vendor/ except through the refresh script.")
  endif()
endforeach()

message(STATUS "httparse-spec: corpus provenance checked ${_corpus_checked} file(s)")
spec_finish("corpus provenance")

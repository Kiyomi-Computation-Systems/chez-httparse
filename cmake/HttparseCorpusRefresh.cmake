# Re-vendor the llhttp conformance corpus from a local checkout.
#
#   cmake -DLLHTTP_ROOT=/path/to/llhttp -P cmake/HttparseCorpusRefresh.cmake
#
# Decision 0007 vendors the corpus as DATA: upstream's bytes, verbatim, with a
# PROVENANCE file recording where they came from and a SHA-256 per file that a
# registered spec checks. This script is the only way those bytes are written,
# so the initial vendor and every later refresh run identical code -- a refresh
# cannot drift from however the first copy happened to be made.
#
# WHY THE SOURCE IS A VARIABLE, NEVER A PATH IN THIS FILE. Decision 0002 ruled
# out in-tree references to a sibling developer checkout for the generator
# dependency, and 0007 item 3 extends that rule to the corpus. The checkout is
# named at invocation or the script refuses.
#
# (The dependency is deliberately not named here in prose: the rename audit
# forbids that token anywhere in the build/test tree, and it caught this file
# on its first run for exactly that.)
#
# WHY THE DESTINATION IS EMPTIED FIRST. A refresh that only copies would leave
# a fixture upstream deleted sitting in the tree, still checksummed, still
# claimed by the ratchet -- passing, and testing nothing anyone maintains.

cmake_minimum_required(VERSION 3.26)

if(NOT DEFINED LLHTTP_ROOT OR LLHTTP_ROOT STREQUAL "")
  message(FATAL_ERROR
    "httparse: LLHTTP_ROOT is required.\n"
    "  cmake -DLLHTTP_ROOT=/path/to/llhttp -P cmake/HttparseCorpusRefresh.cmake")
endif()

get_filename_component(_src "${LLHTTP_ROOT}" ABSOLUTE)
if(NOT IS_DIRECTORY "${_src}/test/request" OR NOT EXISTS "${_src}/LICENSE")
  message(FATAL_ERROR
    "httparse: '${_src}' does not look like an llhttp checkout "
    "(expected test/request/ and LICENSE).")
endif()

get_filename_component(_repo "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)
set(_dest "${_repo}/test/vendor/llhttp")

# --- what upstream commit is this? -----------------------------------------
#
# Recorded when git can answer and marked unknown when it cannot, rather than
# omitted: a PROVENANCE whose commit line is absent reads like an oversight,
# where one that says "unknown" says the copy was taken from a tree that could
# not identify itself, which is a different and worse thing to know later.
set(_ref "unknown")
set(_commit "unknown")
find_package(Git QUIET)
if(GIT_FOUND AND IS_DIRECTORY "${_src}/.git")
  execute_process(COMMAND "${GIT_EXECUTABLE}" -C "${_src}" rev-parse HEAD
                  OUTPUT_VARIABLE _commit OUTPUT_STRIP_TRAILING_WHITESPACE
                  ERROR_QUIET RESULT_VARIABLE _rc)
  if(NOT _rc EQUAL 0)
    set(_commit "unknown")
  endif()
  execute_process(COMMAND "${GIT_EXECUTABLE}" -C "${_src}" describe --tags
                  OUTPUT_VARIABLE _ref OUTPUT_STRIP_TRAILING_WHITESPACE
                  ERROR_QUIET RESULT_VARIABLE _rc)
  if(NOT _rc EQUAL 0)
    set(_ref "unknown")
  endif()
endif()

# --- collect, empty, copy ---------------------------------------------------
file(GLOB _req "${_src}/test/request/*.md")
file(GLOB _res "${_src}/test/response/*.md")
list(SORT _req)
list(SORT _res)

if(_req STREQUAL "" OR _res STREQUAL "")
  message(FATAL_ERROR "httparse: found no fixture files under '${_src}/test'.")
endif()

file(REMOVE_RECURSE "${_dest}")
file(MAKE_DIRECTORY "${_dest}/request" "${_dest}/response")

set(_relatives "")
foreach(_f IN LISTS _req)
  get_filename_component(_n "${_f}" NAME)
  configure_file("${_f}" "${_dest}/request/${_n}" COPYONLY)
  list(APPEND _relatives "request/${_n}")
endforeach()
foreach(_f IN LISTS _res)
  get_filename_component(_n "${_f}" NAME)
  configure_file("${_f}" "${_dest}/response/${_n}" COPYONLY)
  list(APPEND _relatives "response/${_n}")
endforeach()
configure_file("${_src}/test/url.md" "${_dest}/url.md" COPYONLY)
list(APPEND _relatives "url.md")
configure_file("${_src}/LICENSE" "${_dest}/LICENSE" COPYONLY)
list(APPEND _relatives "LICENSE")

list(SORT _relatives)
list(LENGTH _relatives _count)

# --- PROVENANCE -------------------------------------------------------------
string(TIMESTAMP _today "%Y-%m-%d" UTC)
set(_body
"# PROVENANCE -- the vendored llhttp conformance corpus
#
# Upstream's bytes, verbatim. Decision 0007 governs this directory:
#   * these files are NEVER edited -- a fixture we believe is wrong becomes a
#     ratchet entry and a decision record, never a change to these bytes;
#   * every file is checksummed below and verified by a registered spec, so
#     upstream drift and local corruption are build failures, not discoveries;
#   * refresh only through:
#       cmake -DLLHTTP_ROOT=<checkout> -P cmake/HttparseCorpusRefresh.cmake
#
# llhttp is MIT licensed (LICENSE beside this file, retained per 0007 item 7).
# This is test data; it is not part of the distributed library.

upstream-url: https://github.com/nodejs/llhttp
upstream-ref: ${_ref}
upstream-commit: ${_commit}
retrieved: ${_today}
file-count: ${_count}

")
foreach(_rel IN LISTS _relatives)
  file(SHA256 "${_dest}/${_rel}" _hash)
  string(APPEND _body "sha256 ${_hash} ${_rel}\n")
endforeach()

file(WRITE "${_dest}/PROVENANCE" "${_body}")

message(STATUS "httparse: vendored ${_count} file(s) from ${_ref} (${_commit})")
message(STATUS "httparse: wrote ${_dest}/PROVENANCE")

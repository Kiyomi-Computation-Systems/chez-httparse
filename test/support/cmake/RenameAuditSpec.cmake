# Specification: no upstream project token survives in the build/test tree.
#
# This harness was ported from another repository under a mechanical rename
# (decision 0001 in .plans/decisions/), and Slice 1's exit criteria (decision
# 0003) require zero upstream-name references outside the documentation and
# attribution surfaces. A rule like that decays the moment it lives only in a
# review checklist -- the next file copied from upstream reintroduces the name
# and nothing fails -- so it is a registered check instead (AGENTS.md: prefer
# a check to a comment).
#
# WHAT IS SCANNED. The build/test tree: the top-level build files, cmake/,
# test/, and .github/. The documentation and attribution surfaces (.plans/,
# README.org, CHANGELOG.md, AGENTS.md, LICENSE, .superpowers/) are exempt by
# decision 0003 and are not walked. A scan root that does not exist is
# skipped, not an error: under the mutation engine's staged tree only cmake/
# and test/support/cmake/ are present, and the audit must still judge those.
#
# WHY THE PATTERNS ARE ASSEMBLED AT RUN TIME. This file must never contain
# the forbidden text it hunts, or it would convict itself; string(CONCAT)
# builds each pattern from halves. Matching is done on a lowercased copy of
# each file, so every case mixture of the upstream name -- function prefix,
# cache variable, module CamelCase, hyphenated prose -- reduces to the two
# stems below.

include_guard(GLOBAL)
include("${CMAKE_CURRENT_LIST_DIR}/SpecSupport.cmake")

get_filename_component(_audit_root "${CMAKE_CURRENT_LIST_DIR}/../../.." ABSOLUTE)

# The two lowercase stems every observed shape of the upstream name reduces
# to: the separated form (underscore or hyphen) and the fused CamelCase form.
string(CONCAT _audit_separated "byte" "[_-]" "machine")
string(CONCAT _audit_fused "byte" "machine")

# THE TWO LEGITIMATE FORMS (decision 0011). The audit no longer asks whether
# the token occurs; it asks whether every occurrence is one of these. They are
# stripped from a lowercased copy before the scan, so anything the stems still
# match afterwards is a leak.
#
#   vendor/<dep>            the submodule path (decision 0005), which the build
#                           must name to put the generator on Chez's library path
#   (<dep> <name>)          an R6RS library reference, imported by its real name
#                           because decision 0001 item 4 never renames it
#
# Every other shape still fails: a function prefix, a cache variable, a
# CamelCase filename, or a bare hyphenated token in a test name, diagnostic
# prefix or collection directory. Assembled from halves for the same reason
# the stems are -- this file must not convict itself.
string(CONCAT _audit_allow_constructor
       "byte" "-machine-make-compiled-machine" "(/v[0-9]+)?")
string(CONCAT _audit_allow_collection
       "vendor/" "byte" "-machine" "/src/" "byte" "-machine")
string(CONCAT _audit_allow_path "vendor/" "byte" "-machine")
string(CONCAT _audit_allow_library "\\(" "byte" "-machine [a-z][a-z0-9-]*\\)")

set(_audit_files
  "${_audit_root}/Makefile"
  "${_audit_root}/CMakeLists.txt"
  "${_audit_root}/CMakePresets.json"
  "${_audit_root}/.gitignore"
  "${_audit_root}/.gitattributes")

foreach(_audit_dir cmake test .github)
  if(IS_DIRECTORY "${_audit_root}/${_audit_dir}")
    file(GLOB_RECURSE _audit_found "${_audit_root}/${_audit_dir}/*")
    list(APPEND _audit_files ${_audit_found})
  endif()
endforeach()

set(_audit_scanned 0)
foreach(_audit_file IN LISTS _audit_files)
  if(NOT EXISTS "${_audit_file}" OR IS_DIRECTORY "${_audit_file}")
    continue()
  endif()
  math(EXPR _audit_scanned "${_audit_scanned} + 1")
  file(READ "${_audit_file}" _audit_content)
  string(TOLOWER "${_audit_content}" _audit_lower)
  # Strip the declared legitimate forms; what the stems match after this is a
  # leak. Library references go first: the path form is a prefix of nothing
  # here, but stripping the longer, more specific shape first keeps the two
  # independent of each other.
  string(REGEX REPLACE "${_audit_allow_constructor}" "" _audit_lower "${_audit_lower}")
  string(REGEX REPLACE "${_audit_allow_library}" "" _audit_lower "${_audit_lower}")
  # Longest first: the collection path contains the submodule path, so
  # stripping the shorter one first would leave "/src/<dep>" behind and
  # convict a legitimate reference.
  string(REPLACE "${_audit_allow_collection}" "" _audit_lower "${_audit_lower}")
  string(REPLACE "${_audit_allow_path}" "" _audit_lower "${_audit_lower}")
  if(_audit_lower MATCHES "${_audit_separated}" OR
     _audit_lower MATCHES "${_audit_fused}")
    spec_record_failure()
    file(RELATIVE_PATH _audit_rel "${_audit_root}" "${_audit_file}")
    message(SEND_ERROR
      "httparse-spec: upstream project token leaked into '${_audit_rel}'. "
      "The build/test tree must carry no reference to the repository this "
      "harness was ported from (decision 0003); rename it per the decision "
      "0001 map, or, if this file is genuinely attribution, move the mention "
      "to an exempt surface. Only the submodule path and an R6RS library "
      "reference are legitimate here (decision 0011); a new form is added by "
      "amending that record, not by widening this one quietly.")
  endif()
endforeach()

# An audit that scanned nothing proves nothing -- the same reason an empty
# test selection and an empty mutation suite are failures elsewhere in this
# tree. Even the staged mutation tree carries this spec's own directory, so
# zero files means the roots were mislocated, not that the tree is clean.
if(_audit_scanned EQUAL 0)
  spec_record_failure()
  message(SEND_ERROR
    "httparse-spec: the rename audit scanned zero files, so it verified "
    "nothing. The scan roots no longer describe the tree.")
endif()

spec_finish("rename audit (${_audit_scanned} files clean)")

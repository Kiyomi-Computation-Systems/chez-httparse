# Specification: a milestone plan's header does not contradict its own ladder.
#
# A plan's header restates two things the rest of the tree already knows: which
# decisions govern it, and which milestones are still ahead of it. Both went
# stale, twice. M8 shipped while the header still called the document a design
# and stopped its decision range at 0010; that was corrected by hand, and M9
# landed one pull request later and staled the same paragraph again -- M9 marked
# its own heading DONE and left the Goal section calling it deferred.
#
# Correcting it a third time buys one pull request of accuracy. A review rule
# decays exactly the way the rename audit's would, so the invariant is a
# registered check instead (AGENTS.md: prefer a check to a comment).
#
# WHAT IS CHECKED, and why only this much:
#
#   1. Every decision link resolves to a record that exists. Unambiguous: a
#      link to a missing record is a defect whatever renamed it.
#
#   2. No milestone whose own heading says DONE is named in a deferral sentence
#      in the header. This is precisely the contradiction that shipped.
#
# WHAT IS DELIBERATELY NOT CHECKED: that the header's decision range ends at
# the highest-numbered record. That reads like an invariant and is not one --
# the records are project-wide, so a later decision need not concern this plan,
# and a lane asserting otherwise would demand a false edit. The header no
# longer names a range at all, which is the honest fix, because then there is
# nothing to drift. The absence is a decision, not an oversight, which is why
# it is written down here.

cmake_minimum_required(VERSION 3.26)

include("${CMAKE_CURRENT_LIST_DIR}/SpecSupport.cmake")

set(SPEC_SELF "${CMAKE_CURRENT_LIST_FILE}")

get_filename_component(_plan_root "${CMAKE_CURRENT_LIST_DIR}/../../.." ABSOLUTE)
set(_plan_decisions "${_plan_root}/.plans/decisions")

# --- The audit, as a function of text --------------------------------------
#
# Findings are computed from a document's text and the decision directory's
# contents alone. That is what lets the witness cases below drive this same
# code with synthetic documents rather than by editing the real plan, and it
# keeps the file reading at the edges.
#
# plan_audit_document(<text> <decisions-dir> <label> <out-findings> <out-laddered>)
#
# <out-laddered> reports whether a milestone ladder was actually found and
# judged. A document this audit cannot read proves nothing about itself, and
# the driver refuses to pass on a run that judged no ladder at all.
function(plan_audit_document text decisions_dir label out_findings out_laddered)
  set(findings "")
  set(laddered 0)

  # (1) Every decision link resolves.
  string(REGEX MATCHALL "decisions/[0-9][0-9][0-9][0-9]-[a-z0-9-]+\\.md"
         links "${text}")
  if(links)
    list(REMOVE_DUPLICATES links)
  endif()
  foreach(link IN LISTS links)
    string(REGEX REPLACE "^decisions/" "" record "${link}")
    if(NOT EXISTS "${decisions_dir}/${record}")
      list(APPEND findings
           "${label}: links to decisions/${record}, which does not exist")
    endif()
  endforeach()

  # (2) No milestone marked DONE is called deferred in the header.
  #
  # The header is everything above the ladder, because that is the summarising
  # prose which drifts; a milestone section describing its own deferral is
  # correct and must not be flagged.
  string(FIND "${text}" "\n## Milestones" ladder_at)
  if(NOT ladder_at EQUAL -1)
    string(SUBSTRING "${text}" 0 ${ladder_at} header)

    set(done_numbers "")
    string(REGEX MATCHALL "\n### M[0-9]+[^\n]*DONE" done_headings "${text}")
    foreach(heading IN LISTS done_headings)
      string(REGEX REPLACE "^\n### M([0-9]+).*$" "\\1" n "${heading}")
      list(APPEND done_numbers "${n}")
    endforeach()

    if(done_numbers)
      set(laddered 1)

      # Sentence-scope the deferral claim. A header may legitimately say in one
      # sentence that M9 delivered pausing and in the next that M10 and M11
      # remain deferred; scoping to the whole header would convict that. The
      # split is on a period followed by whitespace, so a version like v0.1.0
      # survives intact. Semicolons are neutralised first because they would
      # otherwise split the text as a list.
      string(TOLOWER "${header}" sentences)
      string(REPLACE ";" "," sentences "${sentences}")
      string(REGEX REPLACE "\\.[ \t\r\n]+" ".@@" sentences "${sentences}")
      string(REPLACE "@@" ";" sentences "${sentences}")

      foreach(sentence IN LISTS sentences)
        if(NOT sentence MATCHES "defer")
          continue()
        endif()
        foreach(n IN LISTS done_numbers)
          # No word boundary in CMake's regex vocabulary, so the digit run is
          # closed explicitly: M1 must not match M10.
          if(sentence MATCHES "m${n}([^0-9]|$)")
            list(APPEND findings
                 "${label}: the header calls M${n} deferred, but its own heading says DONE")
          endif()
        endforeach()
      endforeach()
    endif()
  endif()

  set(${out_findings} "${findings}" PARENT_SCOPE)
  set(${out_laddered} "${laddered}" PARENT_SCOPE)
endfunction()

# --- Witness cases ---------------------------------------------------------
#
# Driven as child processes by the driver below. Each feeds the audit a
# synthetic document that must be rejected; without these, deleting either
# check would leave this lane green.
if(DEFINED HTTPARSE_SPEC_CASE)
  set(c "${HTTPARSE_SPEC_CASE}")

  if(c STREQUAL "rejects-missing-decision-record")
    set(doc "Status: delivered, per [9999](decisions/9999-a-record-that-does-not-exist.md).\n\n## Milestones\n\n### M9 - pausing - DONE\n")
  elseif(c STREQUAL "rejects-done-milestone-called-deferred")
    set(doc "Status: delivered. M9, M10 and M11 are deferred rather than delivered.\n\n## Milestones\n\n### M9 - pausing - DONE\n")
  elseif(c STREQUAL "rejects-a-document-with-no-ladder")
    set(doc "Status: delivered. Nothing here declares a milestone ladder at all.\n")
  else()
    message(FATAL_ERROR "httparse-spec: unknown case '${c}'")
  endif()

  plan_audit_document("${doc}" "${_plan_decisions}" "synthetic document"
                      findings laddered)
  if(laddered EQUAL 0)
    list(APPEND findings
         "synthetic document: no milestone ladder was judged, so nothing was verified")
  endif()

  if(findings)
    list(JOIN findings "\n  " joined)
    message(FATAL_ERROR "httparse-spec: plan header audit rejected this case:\n  ${joined}")
  endif()

  message(FATAL_ERROR "httparse-spec: case '${c}' was accepted but must be rejected")
endif()

# --- Driver ----------------------------------------------------------------

# Globbed rather than named, so renaming the plan keeps it audited; an empty
# glob is a failure, for the same reason the rename audit refuses a run that
# scanned nothing.
file(GLOB _plan_documents "${_plan_root}/.plans/*milestone-plan.md")
if(NOT _plan_documents)
  spec_record_failure()
  message(SEND_ERROR
    "httparse-spec: no milestone plan was found under .plans/, so this lane "
    "verified nothing. The glob no longer describes the tree.")
endif()

set(_plan_findings "")
set(_plan_laddered 0)
foreach(_plan_document IN LISTS _plan_documents)
  file(READ "${_plan_document}" _plan_text)
  file(RELATIVE_PATH _plan_label "${_plan_root}" "${_plan_document}")
  plan_audit_document("${_plan_text}" "${_plan_decisions}" "${_plan_label}"
                      _document_findings _document_laddered)
  list(APPEND _plan_findings ${_document_findings})
  if(_document_laddered)
    math(EXPR _plan_laddered "${_plan_laddered} + 1")
  endif()
endforeach()

foreach(_plan_finding IN LISTS _plan_findings)
  spec_record_failure()
  message(SEND_ERROR "httparse-spec: ${_plan_finding}")
endforeach()

# A run that judged no ladder has checked the interesting half of nothing.
if(_plan_documents AND _plan_laddered EQUAL 0)
  spec_record_failure()
  message(SEND_ERROR
    "httparse-spec: no milestone ladder was judged in any plan, so the "
    "deferral check verified nothing. The heading shapes have changed.")
endif()

spec_expect_all_rejected("${SPEC_SELF}"
  "rejects-missing-decision-record|which does not exist"
  "rejects-done-milestone-called-deferred|but its own heading says DONE"
  "rejects-a-document-with-no-ladder|so nothing was verified")

spec_finish("plan header audit (${_plan_laddered} ladder(s) judged)")

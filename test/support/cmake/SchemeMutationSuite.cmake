# Proof that the Scheme harness's self-tests are not vacuous.
#
# The harness is the instrument every other test in this tree is measured
# with. If `check-equal` silently always returned true, the whole project
# would go green and stay green, and no test written with `check-equal` could
# notice. So each decision in the runner is broken in turn on a staged copy,
# and the self-tests must fail.
#
# PASSES NUMBERED 1 TO 31, BECAUSE EACH DECISION NEEDS ITS OWN WITNESS
#
# The numbers are stable labels the comments below cross-reference, so they
# keep their gaps (8, 18 and 19 are unused) and the highest number is 31 while
# the pass count is lower. EXPECTED_PASSES and EXPECTED_MUTATIONS are declared
# below and checked against httparse_mutation_totals' accumulated count once
# every pass has run, because nothing else can see a deleted pass: deleting
# whole passes leaves every individual specification green, with the mutation
# count silently dropping.
#
# Pass 1 runs the Chez self-tests lane against the runner.
#
# Pass 2 runs the Chez empty-selection lane through the exact-status helper, for
# the one decision in the runner that no in-process assertion can reach --
# harness-begin reading HTTPARSE_TEST_FILTER out of the environment. A suite
# cannot set its own environment from inside the portable subset, and the
# harness exports no reader for the filter that read produces, so the only
# witness is a whole process that was supposed to select nothing and exit 2.
#
# Pass 3 runs the Chez bootstrap lane, for the defect that disarms the
# self-tests as it commits them: a failure counter that stops counting. Every
# assertion in every suite reports through the counter, so with it broken a
# failing suite prints its FAIL lines and still exits 0. The bootstrap counts
# its own failures with raw conditionals and exits by hand, which is exactly why
# it exists and why it is the only lane whose verdict survives.
#
# Passes 4 to 5 run the Chez launcher's two guard-directory refusals, one per
# pass, each through the exact-status helper. A refusal cannot be witnessed by a
# lane that is set up correctly, because a correctly set-up lane never reaches
# one: each needs its own deliberately wrong command line, and a verify command
# is fixed for the whole pass.
#
# Pass 6 is the launcher's `compile-imported-libraries` call, and it is the one
# mutation in this file that no single process can catch. See its recorded
# reason.
#
# Pass 7 is the library-directories pairing, the mechanism that makes
# `mode=source` an honest claim. No library root in this tree has a compiled
# object in it, so unpairing the root from the guard changes nothing anywhere
# else; the pass therefore builds a root that does have one, and runs the
# self-tests lane against it.
#
# Passes 9 to 17 are the launcher's parse decisions: an unknown flag, a flag
# with no value, a single-valued flag repeated, a required flag unchecked in
# general, one entry dropped from each of required-flags' three members, and
# one entry dropped from each of single-valued-flags' two members. Each gets
# its own pass because each needs its own deliberately wrong invocation and a
# verify command fixed for the whole pass, the same constraint passes 4 to 5
# already established -- generalised here from two decisions to nine.
#
# No pass varies the launch directory: with library roots absolute and
# source-directories empty, there is no resolution step for a launch directory
# to change, so a lane's outcome cannot depend on where it starts.
#
# Pass 20 is the fingerprint algorithm's own decisions -- the +1 that keeps a
# leading zero byte significant, the seed, the multiplier, the modulus, and
# combine's order sensitivity.
#
# Pass 21 is the hex digit table. It sets no manifest, so provenance is
# skipped here exactly as it is for every other pass but 22 through 25: what
# actually catches the mutation is the self-tests' own "hex digits render
# lowercase" case, which check-equals fixed literals ("ff", "deadbeef", "0")
# rather than deriving its expectation from fingerprint.sls.
#
# Passes 22 through 25 are the provenance check and the reachability guard
# that closes over it: 22 is the comparison, 23 the
# missing-expectation branch, 24 the call site that reaches
# harness-verify-provenance! at all, and 25 harness-provenance-reachability-
# diagnosis itself, each witnessed through the exact-status helper so that
# exit 3 -- the refusal -- is the green baseline, exactly as passes 4 and 5 do
# for the launcher's guard-directory refusals. A third refusal -- a manifest
# naming an unreadable source -- has no mutation; see the stated blind spot
# recorded beside pass 23 below. Pass 24 needs a baseline of its own: see the
# detail beside its declaration for why the reachability guard makes
# WRONG_FP_FILE's exit-3 baseline ambiguous for that one mutation and not for
# pass 22's own.
#
# Pass 26 is the aot launcher's own library-path pairing and its
# source-directories narrowing -- the mechanism that makes `mode=aot`
# an honest claim, the same argument pass 7 already makes for `mode=source`.
# The objects it exercises are compiled once, from the staged tree, into this
# pass's own work directory, and reused by passes 27 to 29 below. The pairing
# is witnessed against a divergent library source planted where only an
# unpaired object directory would read it; the narrowing is EXPECT_SURVIVES,
# for the reason recorded beside it.
#
# Passes 27 to 29 are the aot-side launchers' three genuinely new refusals --
# chez-aot.ss's missing-program check, chez-aot.ss's dirty-source-guard
# check, and chez-compile.ss's unpaired-roots check -- each witnessed the
# same way passes 9 to 17 witness chez-source.ss's parse decisions: a
# deliberately wrong invocation through the exact-status helper, since a
# correctly set-up lane never reaches a refusal on its own. The flag-block
# copies both files carry from chez-source.ss are deliberately not re-proven
# here; each launcher's own header records what that leaves unwitnessed.
#
# Pass 30 covers the two decisions inside harness-verify-provenance! that no
# one-source manifest can witness -- the split character and the combining
# order. Passes 22 to 25 pack their verify command through
# HTTPARSE_EXPECT_COMMAND, whose | packing forbids a multi-source manifest, so
# this pass runs the lane command bare instead: its baseline is a passing
# provenance run (exit 0), and each catchable mutation turns that into the
# mismatch refusal (exit 3), with no wrapper needed. Its manifest deliberately
# excludes harness.sls, the file both mutations edit: with it included, an
# inert one-byte edit nowhere near either decision trips the identical
# refusal, so the catch would discriminate nothing.
#
# Pass 31 needs the opposite manifest.
# harness-provenance-failure!'s single shared exit line is reachable only
# from a run whose own provenance has already failed, so witnessing it means
# deliberately naming harness.sls -- the file this mutation edits -- in the
# very manifest that checks it. Self-reference is the mechanism here rather
# than the mistake pass 30 avoids, and it is what makes this constant
# witnessable instead of a structural survivor; AGENTS.md is explicit that a
# decision which can be witnessed does not get an EXPECT_SURVIVES.
#
# WHAT THIS SUITE NEEDS FROM ITS ENVIRONMENT
#
# The self-tests assert that the lane declared its execution mode, that the
# registration's test name is visible, and read the fingerprint fixture
# through adapter-file-bytes, so HTTPARSE_EXECUTION_MODE=source,
# HTTPARSE_TEST_NAME, and HTTPARSE_FINGERPRINT_SAMPLE (naming
# test/fixtures/fingerprint-sample.bin) must all be set in this process;
# CTest supplies all three -- see this suite's registration in
# test/CMakeLists.txt. Run by hand without them, the baseline fails before any
# mutation is tried -- which is the designed behaviour, not a bug: an
# unverifiable baseline makes every mutation look caught.

cmake_minimum_required(VERSION 3.26)

# Declared here, rather than only in prose, so the count enforced at the
# bottom of this file is the same text a reader checks by eye at the top --
# one number to keep in sync, not two that can quietly disagree.
#
# Counted from this file: the sixteen top-level passes below, plus one pass
# per httparse_launcher_pass call (nine: the source launcher's parse
# decisions) and one per httparse_launcher_file_pass call (three: the
# aot-side launchers' new refusals), is 28 passes. The mutation count is the
# declarations inside those passes: 47 written out below plus the 12 the two
# helpers declare, 59. The totals check at the bottom is what notices if this
# paragraph ever stops being true.
set(EXPECTED_PASSES 28)
set(EXPECTED_MUTATIONS 59)

include("${CMAKE_CURRENT_LIST_DIR}/MutationRunner.cmake")

get_filename_component(SOURCE_ROOT "${CMAKE_CURRENT_LIST_DIR}/../../.." ABSOLUTE)

if(DEFINED ENV{HTTPARSE_TEST_TMPDIR})
  set(WORK_DIR "$ENV{HTTPARSE_TEST_TMPDIR}")
else()
  set(WORK_DIR "${SOURCE_ROOT}/build/scheme-mutation")
endif()
set(STAGE_DIR "${WORK_DIR}/stage")

# The object guard the Chez launcher requires. It lives outside the stage
# because the stage is removed and rebuilt on every run, and the launcher
# refuses to start if the guard is missing.
set(GUARD_DIR "${WORK_DIR}/guard")
file(REMOVE_RECURSE "${GUARD_DIR}")
file(MAKE_DIRECTORY "${GUARD_DIR}")

# Two more guards, for the two refusals that need a guard directory in a state
# the build never otherwise produces. The absent one is named and deliberately
# not created.
set(DIRTY_GUARD_DIR "${WORK_DIR}/guard-dirty")
file(REMOVE_RECURSE "${DIRTY_GUARD_DIR}")
file(MAKE_DIRECTORY "${DIRTY_GUARD_DIR}")
file(WRITE "${DIRTY_GUARD_DIR}/stray-object.so"
  "Not a compiled library. Its only job is to stop this directory being empty.\n")

set(ABSENT_GUARD_DIR "${WORK_DIR}/guard-absent")
file(REMOVE_RECURSE "${ABSENT_GUARD_DIR}")

if(NOT HTTPARSE_CHEZ_EXECUTABLE)
  message(FATAL_ERROR
    "httparse-mutation: HTTPARSE_CHEZ_EXECUTABLE was not passed in. "
    "This suite runs a real execution lane, so it cannot be verified under the "
    "no-scheme preset; the registration must forward the discovered path.")
endif()

# Every directory a pass mutates or a verify command resolves libraries
# through. The engine refuses a listed directory that stages nothing, so a
# directory belongs here only when a pass needs something staged from it.
set(HTTPARSE_MUTATION_STAGE_DIRS
  "cmake" "test/support/cmake" "test/support/harness" "test/support/launchers")

set(HTTPARSE_MUTATION_VERIFY_COMMAND
  "${HTTPARSE_CHEZ_EXECUTABLE}"
  "--script" "${STAGE_DIR}/test/support/launchers/chez-source.ss"
  "--library-root" "${STAGE_DIR}/test/support/harness"
  "--object-guard" "${GUARD_DIR}"
  "--program" "${STAGE_DIR}/test/support/harness/self/harness-self-tests.sps")

set(RUNNER test/support/harness/httparse/test/harness.sls)
set(CHEZ_ADAPTER test/support/harness/httparse/test/harness.sls)
set(LAUNCHER test/support/launchers/chez-source.ss)

# --- Assertions ------------------------------------------------------------

httparse_mutation(
  FILE ${RUNNER} SPEC harness-self-tests.sps
  LABEL "runner: check passes whatever it is given"
  FIND [[(define (check what value)
  (harness-count-check!)
  (if value]]
  REPLACE [[(define (check what value)
  (harness-count-check!)
  (if #t]])

# Narrower than the mutation above, and not covered by it: `check` still returns
# #f and still counts the check, but the failure is never recorded. A suite
# built on this would print no FAIL line, count no failure, and exit 0 while
# every assertion in it "failed".
httparse_mutation(
  FILE ${RUNNER} SPEC harness-self-tests.sps
  LABEL "runner: a false check counts but records no failure"
  FIND [[      (begin (harness-record-failure! what "expected a true value") #f)))]]
  REPLACE [[      #f))]])

httparse_mutation(
  FILE ${RUNNER} SPEC harness-self-tests.sps
  LABEL "runner: check-equal compares identity instead of structure"
  FIND [[  (if (equal? actual expected)]]
  REPLACE [[  (if (eq? actual expected)]])

httparse_mutation(
  FILE ${RUNNER} SPEC harness-self-tests.sps
  LABEL "runner: check-not-equal is no longer the inverse"
  FIND [[  (if (equal? actual unexpected)]]
  REPLACE [[  (if (not (equal? actual unexpected))]])

httparse_mutation(
  FILE ${RUNNER} SPEC harness-self-tests.sps
  LABEL "runner: check-fail records nothing"
  FIND [[  (harness-record-failure! what detail)
  #f)]]
  REPLACE [[  #f)]])

httparse_mutation(
  FILE ${RUNNER} SPEC harness-self-tests.sps
  LABEL "runner: check-raises accepts a thunk that returned normally"
  FIND [[      ((eq? (car outcome) 'returned)]]
  REPLACE [[      ((eq? (car outcome) 'never-happens)]])

httparse_mutation(
  FILE ${RUNNER} SPEC harness-self-tests.sps
  LABEL "runner: a failure never marks its case as failed"
  FIND [[  (set! harness-current-case-failed #t)]]
  REPLACE [[  (set! harness-current-case-failed #f)]])

httparse_mutation(
  FILE ${RUNNER} SPEC harness-self-tests.sps
  LABEL "runner: a duplicate case id is silently accepted, making one registration unreachable"
  FIND [[      ((harness-member? id harness-case-ids)]]
  REPLACE [[      (#f]])

# harness-record-error! takes one argument where harness-record-failure! takes
# two, so the "case raised" label goes with the call it belongs to: keeping it
# would mutate the arity rather than the classification, and the arity violation
# is caught by a different assertion than the one this line claims to exercise.
httparse_mutation(
  FILE ${RUNNER} SPEC harness-self-tests.sps
  LABEL "runner: a raise inside a case is recorded as an error rather than that case's failure"
  FIND [[                   (harness-record-failure!
                    "case raised"
                    (adapter-describe-condition (car (cdr outcome))))]]
  REPLACE [[                   (harness-record-error!
                    (adapter-describe-condition (car (cdr outcome))))]])

# harness-group and with-cleanup re-raise through identical text, so each of the
# two mutations below anchors on the line above the `if` -- the group-stack pop
# for one, the tail of the cleanup report for the other. They are two mutations
# rather than one SITES 2 mutation because a multi-site mutation is "caught" as
# soon as any one site is caught. harness-group pops its name off the stack
# *before* it re-raises, so deleting the re-raise still leaves every prefix
# correct; the group merely returns the condition instead of throwing it, and
# only the self-test "a group re-raises its body's condition" can tell.
httparse_mutation(
  FILE ${RUNNER} SPEC harness-self-tests.sps
  LABEL "runner: a group swallows its body's condition instead of re-raising it"
  FIND [[    (set! harness-group-stack (cdr harness-group-stack))
    (if (eq? (car outcome) 'raised)
        (raise (car (cdr outcome)))]]
  REPLACE [[    (set! harness-group-stack (cdr harness-group-stack))
    (if #f
        (raise (car (cdr outcome)))]])

httparse_mutation(
  FILE ${RUNNER} SPEC harness-self-tests.sps
  LABEL "runner: with-cleanup swallows its body's condition instead of re-raising it"
  FIND [[             (adapter-describe-condition (car (cdr cleanup-outcome)))))))
    (if (eq? (car outcome) 'raised)
        (raise (car (cdr outcome)))]]
  REPLACE [[             (adapter-describe-condition (car (cdr cleanup-outcome)))))))
    (if #f
        (raise (car (cdr outcome)))]])

httparse_mutation(
  FILE ${RUNNER} SPEC harness-self-tests.sps
  LABEL "runner: cleanup never runs"
  FIND [[    (let ((cleanup-outcome (guard (e (#t (list 'raised e)))
                             (list 'value (cleanup)))))]]
  REPLACE [[    (let ((cleanup-outcome (list 'value #f)))]])

# FIND anchors on the error and failure clauses alone, not on the `(cond` that
# opens harness-exit-status: provenance is the cond's first clause and
# outranks both, and anchoring on the pair is what survives a further clause
# being added ahead of them.
httparse_mutation(
  FILE ${RUNNER} SPEC harness-self-tests.sps
  LABEL "runner: a failure outranks a harness error in the exit status"
  FIND [[        ((> harness-error-count 0) harness-status-harness-error)
        ((> harness-failure-count 0) harness-status-failed)]]
  REPLACE [[        ((> harness-failure-count 0) harness-status-failed)
        ((> harness-error-count 0) harness-status-harness-error)]])

# --- Probes ----------------------------------------------------------------

# The FIND consumes the whole line, its trailing newline included, so the
# replacement carries a newline of its own; without one it would swallow the
# following line as well and delete more than it names. An inert comment rather
# than an empty replacement, because an explicitly empty single-value argument
# is left undefined by cmake_parse_arguments at the 3.26 floor this project
# declares (CMP0174 is 3.31+), and REPLACE is required.
httparse_mutation(
  FILE ${RUNNER} SPEC harness-self-tests.sps
  LABEL "runner: a probe does not restore the state it displaced"
  FIND [[        (harness-restore-state! saved)
]]
  REPLACE [[        ;; deleted
]])

# Anchored on the preceding line so the pattern is pinned to the tail of
# harness-clear-state! rather than to any future assignment of the same
# variable: harness-set-filter! and harness-begin both assign harness-filter,
# and a bare pattern would start matching one of them after an innocuous edit.
httparse_mutation(
  FILE ${RUNNER} SPEC harness-self-tests.sps
  LABEL "runner: a probe inherits the ambient filter and skips its own cases"
  FIND [[  (set! harness-failures '())
  (set! harness-filter #f))]]
  REPLACE [[  (set! harness-failures '()))]])

# --- Empty selection -------------------------------------------------------

httparse_mutation(
  FILE ${RUNNER} SPEC harness-self-tests.sps
  LABEL "runner: an empty selection is not diagnosed"
  FIND [[    ((> case-count 0) #f)]]
  REPLACE [[    ((> case-count -1) #f)]])

httparse_mutation(
  FILE ${RUNNER} SPEC harness-self-tests.sps
  LABEL "runner: a filtered-out run is diagnosed as having registered nothing"
  FIND [[    ((> skipped-count 0)]]
  REPLACE [[    (#f]])

# --- Output ----------------------------------------------------------------

httparse_mutation(
  FILE ${RUNNER} SPEC harness-self-tests.sps
  LABEL "runner: probe output suppression is removed"
  FIND [[(define (harness-quiet?) (> harness-probe-depth 0))]]
  REPLACE [[(define (harness-quiet?) #f)]]
  EXPECT_SURVIVES
    "suppression changes only what is printed, never a counter or a status, so no assertion can observe it from inside the process; it is covered only by a manual reading of the log, and its real cost -- a log that teaches readers to ignore FAIL lines -- is not machine-checkable")

# The other two print-only decisions, and the same argument. The adapter
# protocol exposes no output-capture service, and the runner may not reach
# past its protocol for one -- so the harness has no way to read
# back what it printed -- and this suite judges a mutation by the verify
# command's exit status, so an output difference is invisible to it whatever
# lane it runs.
# httparse.harness.verbose.chez.source closes the half that can be closed:
# it runs a real program with the variable set, so the path is executed and a
# break that raises is caught. What no layer checks is that the line was
# printed: that is a manual check, and the reason strings below say what it
# looks for.
httparse_mutation(
  FILE ${RUNNER} SPEC harness-self-tests.sps
  LABEL "runner: the value read for HTTPARSE_TEST_VERBOSE is discarded"
  FIND [[    (set! harness-verbose (if (and v (not (string=? v ""))) #t #f)))]]
  REPLACE [[    (set! harness-verbose #f))]]
  EXPECT_SURVIVES
    "the verify command that judges this mutation does not set the variable, so both runs take the same branch -- harness-verbose ends up #f either way -- and the two are byte-identical, not merely indistinguishable by exit status. In a process that does set it the whole difference is one printed line per passing case: no counter, no case count, no status moves, and this suite judges by exit status. httparse.harness.verbose.chez.source proves the read happens and does not raise; that the value read is honoured is covered by a manual check -- either self-tests lane with HTTPARSE_TEST_VERBOSE=1 prints one pass line per case and none without it")

httparse_mutation(
  FILE ${RUNNER} SPEC harness-self-tests.sps
  LABEL "runner: a passing case is never announced under verbose"
  FIND [[                 (if harness-verbose
                     (harness-say (string-append "httparse-harness: pass " id))))]]
  REPLACE [[                 #f)]]
  EXPECT_SURVIVES
    "the pass line is the only thing this branch produces, and a line that is not printed changes no counter and no status; httparse.harness.verbose.chez.source still proves the branch is reached and does not raise, but only a reader of the log can see the line itself, which is a manual check")

# --- The Chez adapter's export list ----------------------------------------

httparse_mutation(
  FILE ${CHEZ_ADAPTER} SPEC harness-self-tests.sps
  LABEL "chez adapter: an exported adapter name is dropped"
  FIND [[    adapter-os adapter-architecture adapter-execution-mode]]
  REPLACE [[    adapter-architecture adapter-execution-mode]])

# Not every export is load-bearing, and pretending otherwise would be the more
# comfortable lie. harness-summary, harness-empty-selection-error, and
# harness-failure-context are used only from the runner section of harness.sls
# itself; an internal reference resolves against the definition, never through
# the export list. Dropping any of the three therefore changes nothing any
# lane can observe -- and with one adapter there is no second export list to
# keep in step with, so the export is a tripwire, not a contract. Recorded
# here so the blind spot is asserted rather than remembered, and so the day
# one of them acquires a caller outside the library, this line fails.
httparse_mutation(
  FILE ${CHEZ_ADAPTER} SPEC harness-self-tests.sps
  LABEL "chez adapter: an export used only inside the runner section is dropped"
  FIND [[    harness-begin harness-finish harness-summary harness-exit-status]]
  REPLACE [[    harness-begin harness-finish harness-exit-status]]
  EXPECT_SURVIVES
    "harness-summary, harness-empty-selection-error, and harness-failure-context are referenced only from the runner section of harness.sls itself; an internal reference resolves inside the library whatever the export list says, so no lane imports the three and none can notice one going missing")

# Load-bearing, unlike the three names in the survivor above: the fingerprint
# library reads files itself (httparse test fingerprint), so
# harness-fingerprint-file does not reach adapter-file-bytes at all. The
# self-tests' own direct call -- reading the fingerprint sample fixture
# through it -- is the only thing that makes dropping this export visible.
httparse_mutation(
  FILE ${CHEZ_ADAPTER} SPEC harness-self-tests.sps
  LABEL "chez adapter: adapter-file-bytes is dropped from the export list"
  FIND [[    adapter-value->string adapter-describe-condition adapter-file-bytes]]
  REPLACE [[    adapter-value->string adapter-describe-condition]])

# Emptying source-directories is deliberate narrowing, measured inert.
httparse_mutation(
  FILE ${LAUNCHER} SPEC harness-self-tests.sps
  LABEL "launcher: source-directories is left at Chez's default instead of emptied"
  FIND [[(source-directories '())]]
  REPLACE [[;; deleted]]
  EXPECT_SURVIVES
    "measured inert, like the aot launcher's matching line: no include form exists anywhere, library resolution runs through library-directories, and no lane's outcome differs between an empty source path and Chez's default; the line is kept as narrowing, not as behavior")

# --- The adapter's os-table -------------------------------------------------

httparse_mutation(
  FILE ${RUNNER} SPEC harness-self-tests.sps
  LABEL "adapter: an os-table row maps to the wrong name"
  FIND [[("osx" . "darwin")]]
  REPLACE [[("osx" . "linux")]]
  EXPECT_STATUS 1
  EXPECT_OUTPUT_MATCHES "tarm64osx os")

httparse_mutation_run("${SOURCE_ROOT}" "${STAGE_DIR}")

# --- Second pass: harness-begin's read of the environment filter -----------
#
# The self-tests cannot witness this one. They check the normalisation rule
# directly, on the pure function, but the read itself only matters to a process
# whose ambient filter came from outside it -- and a suite cannot set its own
# environment from inside the portable subset, nor read back the filter the
# runner stored. The empty-selection lane is that process: it registers one case
# its filter cannot select and must exit 2. Break the read and the case runs, the
# suite exits 0, and the exact-status helper says so.
#
# The helper is what makes exit 2 the passing outcome here, which the mutation
# runner requires: it judges "caught" as a nonzero result from the verify
# command, so the verify command must be one that exits 0 when the lane is
# healthy.

httparse_mutation_reset()

string(JOIN "|" EMPTY_SELECTION_COMMAND
  "${HTTPARSE_CHEZ_EXECUTABLE}"
  "--script" "${STAGE_DIR}/test/support/launchers/chez-source.ss"
  "--library-root" "${STAGE_DIR}/test/support/harness"
  "--object-guard" "${GUARD_DIR}"
  "--program" "${STAGE_DIR}/test/support/harness/self/harness-empty-selection.sps")

set(HTTPARSE_MUTATION_VERIFY_COMMAND
  "${CMAKE_COMMAND}" -E env
  "HTTPARSE_TEST_FILTER=no-case-has-this-in-its-name"
  "${CMAKE_COMMAND}"
  "-DHTTPARSE_EXPECT_EXIT=2"
  "-DHTTPARSE_EXPECT_COMMAND=${EMPTY_SELECTION_COMMAND}"
  -P "${STAGE_DIR}/cmake/HttparseExpectExit.cmake")

httparse_mutation(
  FILE ${RUNNER} SPEC harness-empty-selection.sps
  LABEL "runner: harness-begin ignores HTTPARSE_TEST_FILTER"
  FIND [[  (set! harness-filter
        (harness-normalize-filter
         (adapter-environment-variable "HTTPARSE_TEST_FILTER")))]]
  REPLACE [[  (set! harness-filter #f)]])

httparse_mutation_run("${SOURCE_ROOT}" "${STAGE_DIR}")

# --- Third pass: the failure counter itself ---------------------------------
#
# Under the self-tests lane this mutation goes UNCAUGHT: with
# harness-record-failure! no longer counting, a self-test that fails prints its
# FAIL line, marks its case failed, and leaves the exit status at 0. The
# mutation disarms the mechanism every assertion reports through as it commits
# the defect, so no suite written with `check` can witness it -- which is
# precisely the argument the bootstrap lane exists to answer. It judges the
# primitives with raw conditionals, counts its own failures, and exits by hand.

httparse_mutation_reset()

set(HTTPARSE_MUTATION_VERIFY_COMMAND
  "${HTTPARSE_CHEZ_EXECUTABLE}"
  "--script" "${STAGE_DIR}/test/support/launchers/chez-source.ss"
  "--library-root" "${STAGE_DIR}/test/support/harness"
  "--object-guard" "${GUARD_DIR}"
  "--program" "${STAGE_DIR}/test/support/harness/self/harness-bootstrap.sps")

httparse_mutation(
  FILE ${RUNNER} SPEC harness-bootstrap.sps
  LABEL "runner: a recorded failure is never counted, so a failing suite exits 0"
  FIND [[  (set! harness-failure-count (+ harness-failure-count 1))]]
  REPLACE [[  (set! harness-failure-count harness-failure-count)]])

httparse_mutation_run("${SOURCE_ROOT}" "${STAGE_DIR}")

# --- Passes 4 to 5: the launcher's two guard-directory refusals -------------
#
# The launcher decides whether a lane runs at all, and its object guard is the
# sole mechanism that makes `mode=source` an honest claim. Neither refusal can
# be reached by a lane that was set up correctly, so each gets a deliberately
# wrong command line of its own, run through the exact-status helper so that
# exit 2 -- the refusal -- is what a healthy launcher scores.
#
# A missing required flag is not witnessed here. Passes 9 to 17 below give each
# required-flag entry its own mutation, each a strictly more precise witness of
# that decision than a zero-argument invocation would be; witnessing it here
# too would mean two mutations proving the same line, one of them permanently
# coarser.
#
# SPEC names the registered lane rather than a program basename, because the
# witness is a whole invocation and not a program: "passing" means the named
# program never ran.

httparse_mutation_reset()

string(JOIN "|" LAUNCHER_ABSENT_GUARD_COMMAND
  "${HTTPARSE_CHEZ_EXECUTABLE}"
  "--script" "${STAGE_DIR}/test/support/launchers/chez-source.ss"
  "--library-root" "${STAGE_DIR}/test/support/harness"
  "--object-guard" "${ABSENT_GUARD_DIR}"
  "--program" "${STAGE_DIR}/test/support/harness/self/harness-bootstrap.sps")

set(HTTPARSE_MUTATION_VERIFY_COMMAND
  "${CMAKE_COMMAND}"
  "-DHTTPARSE_EXPECT_EXIT=2"
  "-DHTTPARSE_EXPECT_COMMAND=${LAUNCHER_ABSENT_GUARD_COMMAND}"
  -P "${STAGE_DIR}/cmake/HttparseExpectExit.cmake")

# EXPECT_OUTPUT_MATCHES captures what this mutation actually, verifiably
# produces: with the existence check gone, the very next line calls
# directory-list on a path that does not exist, which Chez itself refuses --
# a real, deterministic consequence of deleting exactly this check, not the
# launcher's own die(). Verified against a real staged run, not guessed; see
# httparse_launcher_pass's header comment below for why the wrapper's
# own exit code (0 or 1) cannot make this distinction by itself.
httparse_mutation(
  FILE ${LAUNCHER} SPEC httparse.harness.launcher-absent-guard.chez.source
  LABEL "launcher: a guard directory that does not exist is assumed rather than checked"
  FIND [[(if (not (file-directory? object-guard-dir))]]
  REPLACE [[(if #f]]
  EXPECT_OUTPUT_MATCHES "Exception in directory-list")

httparse_mutation_run("${SOURCE_ROOT}" "${STAGE_DIR}")

httparse_mutation_reset()

string(JOIN "|" LAUNCHER_DIRTY_GUARD_COMMAND
  "${HTTPARSE_CHEZ_EXECUTABLE}"
  "--script" "${STAGE_DIR}/test/support/launchers/chez-source.ss"
  "--library-root" "${STAGE_DIR}/test/support/harness"
  "--object-guard" "${DIRTY_GUARD_DIR}"
  "--program" "${STAGE_DIR}/test/support/harness/self/harness-bootstrap.sps")

set(HTTPARSE_MUTATION_VERIFY_COMMAND
  "${CMAKE_COMMAND}"
  "-DHTTPARSE_EXPECT_EXIT=2"
  "-DHTTPARSE_EXPECT_COMMAND=${LAUNCHER_DIRTY_GUARD_COMMAND}"
  -P "${STAGE_DIR}/cmake/HttparseExpectExit.cmake")

# The one that matters most: a guard directory that has acquired a file is no
# longer a guard, and the lane would go on reporting mode=source while loading
# whatever was put there.
#
# EXPECT_OUTPUT_MATCHES here is "bootstrap: failures=0", not anything about the
# stray file: with this check gone the launcher does not notice the dirty
# guard at all, so the whole staged bootstrap program runs and passes, ending
# with its own success banner. That is the correct, deterministic consequence
# of deleting exactly this line, verified against a real staged run.
httparse_mutation(
  FILE ${LAUNCHER} SPEC httparse.harness.launcher-dirty-guard.chez.source
  LABEL "launcher: a guard directory with a file in it is accepted as a guard"
  FIND [[(if (not (null? (directory-list object-guard-dir)))]]
  REPLACE [[(if #f]]
  EXPECT_OUTPUT_MATCHES "bootstrap: failures=0")

httparse_mutation_run("${SOURCE_ROOT}" "${STAGE_DIR}")

# --- Sixth pass: a source lane that compiles what it imports ---------------
#
# Its own guard directory, because this is the one mutation here whose effect is
# to write into one.

httparse_mutation_reset()

set(COMPILE_GUARD_DIR "${WORK_DIR}/guard-compile")
file(REMOVE_RECURSE "${COMPILE_GUARD_DIR}")
file(MAKE_DIRECTORY "${COMPILE_GUARD_DIR}")

set(HTTPARSE_MUTATION_VERIFY_COMMAND
  "${HTTPARSE_CHEZ_EXECUTABLE}"
  "--script" "${STAGE_DIR}/test/support/launchers/chez-source.ss"
  "--library-root" "${STAGE_DIR}/test/support/harness"
  "--object-guard" "${COMPILE_GUARD_DIR}"
  "--program" "${STAGE_DIR}/test/support/harness/self/harness-bootstrap.sps")

httparse_mutation(
  FILE ${LAUNCHER} SPEC httparse.harness.bootstrap.chez.source
  LABEL "launcher: a source lane is allowed to compile what it imports"
  FIND [[(compile-imported-libraries #f)]]
  REPLACE [[(compile-imported-libraries #t)]]
  EXPECT_SURVIVES
    "deleting the call is provably unobservable -- Chez's own default for compile-imported-libraries is already #f -- so the only mutation with an effect is turning it on, and its entire effect is a file: Chez writes httparse/test/harness.so into the object half of the library-directories pair, which is the guard, and it does so after the launcher has already asserted the guard was empty. No single process can see it. The registered lanes can, and do: with compilation on, the first Chez lane to run pollutes the shared object guard and three of the harness preset's tests fail. This suite runs one process per mutation, so what it can prove about this line is only that the line is still there")

httparse_mutation_run("${SOURCE_ROOT}" "${STAGE_DIR}")

# --- Seventh pass: the library-directories pairing ---------------------------
#
# The pairing is the launcher's central mechanism. Chez looks for a library's
# compiled object only in the *object* half of a library-directories pair, so
# pairing the library root with a directory the build keeps empty is the whole
# reason this lane may call itself "source". The launcher's own header and
# test/CMakeLists.txt both say so, and without this pass nothing checks it:
# `(library-directories (list library-root))` leaves every test green, because
# no library root in this tree has an object beside its source for Chez to
# prefer.
#
# So this pass builds one, in a library root of its own. A garbage `.so` is not
# enough: Chez silently ignores a file it cannot read as a library, and both the
# pristine and the unpaired run then exit 0 -- an inconclusive experiment, not
# evidence that the pairing does nothing. The object here is genuinely compiled,
# from a copy of the adapter whose `adapter-runtime-name` returns a sentinel,
# and the pristine `.sls` stays beside it so the baseline has real source to
# load. The sentinel is what makes the catch legible: the mutated run fails
# *because the object was loaded*, and says so in its banner, its FAIL-CONTEXT
# line, and its summary, rather than failing for some unrelated reason.
#
# Everything lives under this suite's work directory. The source tree is only
# read, no other pass's guard is touched, and this pass gets an empty guard of
# its own so that a future change to the shared one cannot quietly decide the
# result.
#
# Reached only when a Chez was passed in, the same way every other Chez pass
# here is: this file refuses to start without one, and the registration in
# test/CMakeLists.txt is guarded on the same variable, so `ctest --preset
# no-scheme` never reaches the compile below.

httparse_mutation_reset()

set(POISON_DIR "${WORK_DIR}/poisoned-library-root")
set(POISON_ROOT "${POISON_DIR}/root")
set(POISON_SOURCE_DIR "${POISON_DIR}/poisoned-source")
set(POISON_OBJECT "${POISON_ROOT}/httparse/test/harness.so")
set(POISON_GUARD_DIR "${WORK_DIR}/guard-poisoned")

file(REMOVE_RECURSE "${POISON_DIR}" "${POISON_GUARD_DIR}")
file(MAKE_DIRECTORY "${POISON_ROOT}/httparse/test")
file(MAKE_DIRECTORY "${POISON_SOURCE_DIR}/httparse/test")
file(MAKE_DIRECTORY "${POISON_GUARD_DIR}")

# Asserted, not assumed, for the same reason SITES is: if the adapter is
# refactored past this pattern the "poisoned" copy would be a pristine one, the
# mutated run would pass, and the mutation would be reported UNCAUGHT with no
# hint that the poison was the thing that broke.
set(POISON_FIND [[  (define (adapter-runtime-name) "chez")]])
set(POISON_REPLACE [[  (define (adapter-runtime-name) "POISONED-FROM-OBJECT")]])

file(READ "${SOURCE_ROOT}/${CHEZ_ADAPTER}" POISON_PRISTINE)
string(FIND "${POISON_PRISTINE}" "${POISON_FIND}" POISON_AT)
if(POISON_AT EQUAL -1)
  message(FATAL_ERROR
    "httparse-mutation: the Chez adapter no longer contains "
    "'${POISON_FIND}', so the object this pass compiles would be an unpoisoned "
    "copy and the library-directories mutation would prove nothing. Update the "
    "pattern rather than dropping it.")
endif()
string(REPLACE "${POISON_FIND}" "${POISON_REPLACE}" POISON_MUTATED "${POISON_PRISTINE}")

# The pristine source goes down first, and the object is written by the
# compile below.
#
# The object is preferred only while it is not older than the .sls beside
# it -- and, transitively, while its imported fingerprint library also
# resolves to a non-stale object (the MEASURED note below). No STAGED file's
# mtime participates, because no file in the harness includes another, so
# nothing is re-resolved at load time.
file(WRITE "${POISON_ROOT}/httparse/test/harness.sls" "${POISON_PRISTINE}")
file(WRITE "${POISON_SOURCE_DIR}/httparse/test/harness.sls" "${POISON_MUTATED}")

# harness.sls imports (httparse test fingerprint), so the object compiled
# below has a real library dependency. MEASURED, not assumed: Chez's staleness
# check on a compiled library is transitive -- an object is trusted only if
# every library it imports also resolves to a non-stale compiled object, not
# bare source. A minimal two-library reproduction confirmed this directly: an
# importer's freshly compiled object was silently discarded in favour of its
# own pristine source whenever the imported library resolved to source only,
# even though the importer's own root was searched first and its object was
# not stale by itself. Giving fingerprint no compiled object anywhere in this
# pass's roots reproduces exactly that: the poisoned harness object is
# silently rejected and the baseline's pristine banner prints instead, so the
# mutation below goes UNCAUGHT. So POISON_ROOT is self-sufficient: a real,
# non-stale fingerprint object beside the poisoned harness object, compiled
# first so harness's object is never older than a library it depends on.
#
# One cross-copy invariant this relies on: the compile below resolves
# fingerprint's import from ${SOURCE_ROOT}/test/support/harness (the
# real source tree, via library-directories), while the verify run further
# down resolves the same import from POISON_ROOT's own copy. Compiling
# against one copy and running against another is safe here only because
# the file(READ)/file(WRITE) pair immediately below makes the two
# byte-identical by construction -- the same guarantee the pristine
# harness.sls copy above already depends on.
file(READ "${SOURCE_ROOT}/test/support/harness/httparse/test/fingerprint.sls"
     POISON_FINGERPRINT_PRISTINE)
file(WRITE "${POISON_ROOT}/httparse/test/fingerprint.sls" "${POISON_FINGERPRINT_PRISTINE}")

set(POISON_COMPILE_SCRIPT "${POISON_DIR}/compile-poisoned-object.ss")
file(WRITE "${POISON_COMPILE_SCRIPT}"
";; Written by SchemeMutationSuite.cmake, never committed. Compiles the
;; poisoned adapter copy into the library root that holds the pristine source,
;; so a launcher which stops pairing that root with an empty object directory
;; loads the object instead of the source. This is a per-runtime staging file,
;; not harness text, so naming Chez here is allowed.
;;
;; Both halves of the poison are read from the source tree, not from the stage:
;; the two are byte-identical by construction, and reading the stage would make
;; this pass depend on the previous pass having left it in place.
(library-directories (list (cons \"${SOURCE_ROOT}/test/support/harness\" \"${POISON_GUARD_DIR}\")))
;; Compiled first, and into POISON_ROOT itself (not the guard): harness's own
;; object is trusted only if this one is also a real, reachable object by the
;; time harness compiles, per the transitive staleness note above.
(compile-library \"${POISON_ROOT}/httparse/test/fingerprint.sls\"
                 \"${POISON_ROOT}/httparse/test/fingerprint.so\")
(compile-library \"${POISON_SOURCE_DIR}/httparse/test/harness.sls\"
                 \"${POISON_OBJECT}\")
")

execute_process(
  COMMAND "${HTTPARSE_CHEZ_EXECUTABLE}" "--script" "${POISON_COMPILE_SCRIPT}"
  RESULT_VARIABLE POISON_RC
  OUTPUT_VARIABLE POISON_OUT
  ERROR_VARIABLE POISON_ERR)
if(NOT POISON_RC EQUAL 0 OR NOT EXISTS "${POISON_OBJECT}"
   OR NOT EXISTS "${POISON_ROOT}/httparse/test/fingerprint.so")
  message(FATAL_ERROR
    "httparse-mutation: could not compile the poisoned library root "
    "(exit ${POISON_RC}). Without a real object for both harness and the "
    "fingerprint library it now imports, the library-directories mutation "
    "cannot discriminate, and a run against a file Chez cannot read as a "
    "library, or a harness object it distrusts for an unresolved import, "
    "passes either way.\n"
    "${POISON_OUT}${POISON_ERR}")
endif()

# Makes "not older than the source" true by construction rather than by the
# compile happening to take a second, which a filesystem with coarse timestamps
# would not record. The fingerprint object is touched first, preserving the
# dependency order the compile above already established: harness's object
# must never be older than a library it imports.
file(TOUCH "${POISON_ROOT}/httparse/test/fingerprint.so")
file(TOUCH "${POISON_OBJECT}")

set(HTTPARSE_MUTATION_VERIFY_COMMAND
  "${HTTPARSE_CHEZ_EXECUTABLE}"
  "--script" "${STAGE_DIR}/test/support/launchers/chez-source.ss"
  "--library-root" "${POISON_ROOT}"
  "--object-guard" "${POISON_GUARD_DIR}"
  "--program" "${STAGE_DIR}/test/support/harness/self/harness-self-tests.sps")

# EXPECT_OUTPUT_MATCHES turns the paragraph above's claim -- that the mutated
# run "says so in its banner, its FAIL-CONTEXT line, and its summary" -- into
# something this suite enforces rather than merely asserts in prose. The
# sentinel is the literal string written into POISON_REPLACE above, so a rc
# that happens to be nonzero for some other reason (a staging error, an
# unrelated crash) is reported caught-for-the-wrong-reason instead of caught.
httparse_mutation(
  FILE ${LAUNCHER}
  SPEC "harness-self-tests.sps against a library root holding a compiled object"
  LABEL "launcher: the library root is no longer paired with the object guard"
  FIND [[(library-directories
 (map (lambda (root) (cons root object-guard-dir)) library-roots))]]
  REPLACE [[(library-directories library-roots)]]
  EXPECT_OUTPUT_MATCHES "POISONED-FROM-OBJECT")

httparse_mutation_run("${SOURCE_ROOT}" "${STAGE_DIR}")

# --- Passes 9 to 17: the launcher's parse decisions -------------------------
#
# Deleting a refusal does not produce a wrong answer; it produces an invocation
# that is accepted and then fails somewhere else, or does not fail at all. Two
# of these mutations leave the launcher reaching malformed input and dying at
# 255 rather than 2, which the exact-status helper reports as out-of-vocabulary.
# That is still caught, and it is the honest outcome: the refusal exists exactly
# so that malformed input is named rather than stumbled over.

set(LAUNCHER_BASE_ARGS
  "--library-root" "${STAGE_DIR}/test/support/harness"
  "--object-guard" "${GUARD_DIR}"
  "--program" "${STAGE_DIR}/test/support/harness/self/harness-bootstrap.sps")

# httparse_launcher_pass(<lane> <label> <find> <replace>
#                                   <expect_output_matches> <arg>...)
#
# One pass: point the verify command at a deliberately wrong invocation, declare
# one mutation, run it. Defined here rather than inlined nine times because the
# only thing that varies is the lane, the command line, and the mutation.
#
# expect_output_matches exists because the wrapper's own exit code is only ever
# 0 or 1 -- HttparseExpectExit.cmake's message(FATAL_ERROR) exits 1
# regardless of what the real launcher's exit status was, so a nonzero result
# here means only "the real process did not exit 2", never which of the two
# very different ways that can happen: the invocation this pass built runs to
# completion once the deleted check stops blocking it (verified as
# "bootstrap: failures=0" -- the bootstrap program's own success banner,
# reachable only by loading and running the entire staged launcher and
# program), or it reaches a later, unrelated Chez error and dies with an
# out-of-vocabulary status (verified per pass -- see the call sites below).
# Both are legitimate evidence that the deleted check mattered. What neither
# looks like is a read error from a staged file that stopped being valid
# Scheme: a REPLACE that opens a line comment can swallow a list's closing
# parens (the hazard recorded next to the --library-root mutation below), and
# the pass is then caught at exit 255 on "Exception in read: ..." rather than
# on the refusal it names. Every value
# passed here was captured from a real staged run of the mutation it guards,
# not guessed.
#
# The reset, the declaration and the run all happen inside this function on
# purpose. httparse_mutation_reset and httparse_mutation both write the
# counter with PARENT_SCOPE, so they agree only while they share a caller;
# splitting them across this boundary would leave the run seeing a count from
# somewhere else.
function(httparse_launcher_pass lane label find replace expect_output_matches)
  httparse_mutation_reset()

  string(JOIN "|" packed
    "${HTTPARSE_CHEZ_EXECUTABLE}"
    "--script" "${STAGE_DIR}/test/support/launchers/chez-source.ss"
    ${ARGN})

  set(HTTPARSE_MUTATION_VERIFY_COMMAND
    "${CMAKE_COMMAND}"
    "-DHTTPARSE_EXPECT_EXIT=2"
    "-DHTTPARSE_EXPECT_COMMAND=${packed}"
    -P "${STAGE_DIR}/cmake/HttparseExpectExit.cmake")

  httparse_mutation(
    FILE ${LAUNCHER} SPEC "${lane}"
    LABEL "${label}"
    FIND "${find}"
    REPLACE "${replace}"
    EXPECT_OUTPUT_MATCHES "${expect_output_matches}")

  httparse_mutation_run("${SOURCE_ROOT}" "${STAGE_DIR}")
endfunction()

httparse_launcher_pass(
  httparse.harness.launcher-unknown-flag.chez.source
  "launcher: an unrecognised flag is accepted"
  [[        ((not (member (car rest) known-flags))]]
  [[        (#f]]
  "bootstrap: failures=0"
  "--librarie-root" "${STAGE_DIR}/test/support/harness" ${LAUNCHER_BASE_ARGS})

httparse_launcher_pass(
  httparse.harness.launcher-missing-value.chez.source
  "launcher: a flag with no value is accepted"
  [[        ((null? (cdr rest))]]
  [[        (#f]]
  "Exception in cddr"
  ${LAUNCHER_BASE_ARGS} "--library-root")

httparse_launcher_pass(
  httparse.harness.launcher-repeated-flag.chez.source
  "launcher: a single-valued flag may be given twice"
  [[   (if (> (length (flag-values flag)) 1)]]
  [[   (if #f]]
  "bootstrap: failures=0"
  ${LAUNCHER_BASE_ARGS}
  "--program" "${STAGE_DIR}/test/support/harness/self/harness-self-tests.sps")

# SPEC must name a lane `ctest -N` actually lists: it is the transcript name a
# real invocation is judged under, and once a verify command is set (as every
# pass in this file does), SPEC is otherwise ignored -- so a value that names
# no real lane is checked by nothing, and nothing notices. This pass and the
# entry-specific one below that drops --library-root from required-flags both
# run the identical missing-library-root invocation, so both are witnessed by
# the same registered lane, httparse.harness.launcher-no-library-root.chez.source.
# A unique SPEC would keep the two mutations apart in the transcript, but only
# by naming a lane that does not exist. The disambiguation belongs in LABEL
# instead, which is free text with no such constraint: this pass witnesses
# the launcher's Decision 2 check itself (the
# `if` that runs once per required flag, so it breaks identically no matter
# which flag the invocation happened to omit -- library-root was picked only
# because it made a convenient invocation to reuse), while the pass below
# witnesses required-flags' library-root *entry* specifically, i.e. whether
# the flag is still in the list Decision 2 walks at all. Two different lines,
# two different mutations, one shared witness.
httparse_launcher_pass(
  httparse.harness.launcher-no-library-root.chez.source
  "launcher: a missing required flag is not noticed (decision 2's own check, general across every entry; reuses the no-library-root invocation below only for convenience)"
  [[   (if (null? (flag-values flag))]]
  [[   (if #f]]
  [[library \(httparse test harness\) not found]]
  "--object-guard" "${GUARD_DIR}"
  "--program" "${STAGE_DIR}/test/support/harness/self/harness-bootstrap.sps")

# Three more: one per entry in required-flags. The check above is one decision,
# but the list it walks is three, and an entry dropped from it is invisible to
# every invocation except the one omitting that flag.

httparse_launcher_pass(
  httparse.harness.launcher-no-program.chez.source
  "launcher: --program is dropped from required-flags"
  [[  (list "--program"]]
  [[  (list ;; --program removed by mutation]]
  "Exception in car"
  "--library-root" "${STAGE_DIR}/test/support/harness"
  "--object-guard" "${GUARD_DIR}")

httparse_launcher_pass(
  httparse.harness.launcher-no-object-guard.chez.source
  "launcher: --object-guard is dropped from required-flags"
  [[        "--object-guard"]]
  [[        ;; --object-guard removed by mutation]]
  "Exception in car"
  "--library-root" "${STAGE_DIR}/test/support/harness"
  "--program" "${STAGE_DIR}/test/support/harness/self/harness-bootstrap.sps")

# --library-root is the last entry in required-flags, so its source line ends
# with two closing parens -- the list's and the define's -- rather than one.
# A FIND that matched only the flag's text left both dangling after a REPLACE
# that opened a line comment: the comment swallowed ")) " too, so the staged
# file was not readable Scheme and died with a read error at exit 255 rather
# than the launcher's own required-flag refusal -- caught, but for the wrong
# reason, and witnessing nothing about the decision this pass names. The FIND
# below includes the trailing "))" so the REPLACE can close the list itself.
# Whichever entry ends up last in required-flags after a reorder or a fourth
# addition inherits this hazard and needs the same treatment.
httparse_launcher_pass(
  httparse.harness.launcher-no-library-root.chez.source
  "launcher: --library-root is dropped from required-flags"
  [[        "--library-root"))]]
  [[        ;; --library-root removed by mutation
        ))]]
  [[library \(httparse test harness\) not found]]
  "--object-guard" "${GUARD_DIR}"
  "--program" "${STAGE_DIR}/test/support/harness/self/harness-bootstrap.sps")

# Two more, for single-valued-flags. --object-guard has never been exercised as
# a repeated flag: the general check just above is witnessed only through
# --program (LAUNCHER_BASE_ARGS already carries one --object-guard, so this
# pass repeats it rather than adding a second fixture guard directory --
# the launcher's Decision 3 counts occurrences, not distinct values).
# Dropping --object-guard from single-valued-flags specifically, leaving the
# check itself and --program's membership in the list untouched, is invisible
# to every invocation but this one.
httparse_launcher_pass(
  httparse.harness.launcher-repeated-object-guard.chez.source
  "launcher: --object-guard is dropped from single-valued-flags"
  [[(define single-valued-flags
  (list "--object-guard" "--program"))]]
  [[(define single-valued-flags
  (list "--program"))]]
  "bootstrap: failures=0"
  ${LAUNCHER_BASE_ARGS}
  "--object-guard" "${GUARD_DIR}")

# required-flags' own rationale -- "an entry dropped from it is invisible to
# every invocation except the one omitting that flag" -- applies just as much
# to single-valued-flags' other member, so --program gets the same treatment.
# It sits last on its line, hard against the list's and the define's closing
# parens -- the same position that made --library-root's required-flags
# mutation above catch a read error instead of the decision it names (the
# hazard recorded there). The FIND below matches the whole two-line form,
# both closing parens included, and the REPLACE is itself a complete,
# well-formed define, so there is no dangling ")" left for a comment to
# swallow.
#
# The invocation below repeats --program, so the real lane witnessing it is
# httparse.harness.launcher-repeated-flag.chez.source, not a name of this
# pass's own -- see the SPEC-must-name-a-real-lane comment above the
# required-flag-unchecked pass for why that match matters and what happens
# when it drifts.
httparse_launcher_pass(
  httparse.harness.launcher-repeated-flag.chez.source
  "launcher: --program is dropped from single-valued-flags (reuses the launcher-repeated-flag invocation, which already repeats --program)"
  [[(define single-valued-flags
  (list "--object-guard" "--program"))]]
  [[(define single-valued-flags
  (list "--object-guard"))]]
  "bootstrap: failures=0"
  ${LAUNCHER_BASE_ARGS}
  "--program" "${STAGE_DIR}/test/support/harness/self/harness-self-tests.sps")

# --- Pass 20: the fingerprint algorithm --------------------------------------
#
# The self-tests assert measured literals, so any change to seed, multiplier,
# modulus, the +1, or the digit table moves at least one of them.

set(FINGERPRINT test/support/harness/httparse/test/fingerprint.sls)

set(HTTPARSE_MUTATION_VERIFY_COMMAND
  "${HTTPARSE_CHEZ_EXECUTABLE}"
  "--script" "${STAGE_DIR}/test/support/launchers/chez-source.ss"
  "--library-root" "${STAGE_DIR}/test/support/harness"
  "--object-guard" "${GUARD_DIR}"
  "--program" "${STAGE_DIR}/test/support/harness/self/harness-self-tests.sps")

httparse_mutation_reset()

# Without the +1 a NUL contributes nothing, and the three leading-zero cases
# collapse into one value. This is the only mutation here that a fixed set of
# literals could survive if the literals happened not to include a NUL --
# which is why they do.
httparse_mutation(
  FILE ${FINGERPRINT} SPEC harness-self-tests.sps
  LABEL "fingerprint: leading zero bytes stop being significant"
  FIND [[                           (+ (bytevector-u8-ref bv i) 1))]]
  REPLACE [[                           (bytevector-u8-ref bv i))]])

httparse_mutation(
  FILE ${FINGERPRINT} SPEC harness-self-tests.sps
  LABEL "fingerprint: the seed changes"
  FIND [[(define harness-fingerprint-seed 14695981039346656)]]
  REPLACE [[(define harness-fingerprint-seed 14695981039346657)]])

httparse_mutation(
  FILE ${FINGERPRINT} SPEC harness-self-tests.sps
  LABEL "fingerprint: the multiplier changes"
  FIND [[(define harness-fingerprint-multiplier 1000003)]]
  REPLACE [[(define harness-fingerprint-multiplier 1000033)]])

httparse_mutation(
  FILE ${FINGERPRINT} SPEC harness-self-tests.sps
  LABEL "fingerprint: the modulus changes"
  FIND [[(define harness-fingerprint-modulus 2305843009213693951) ; 2^61 - 1]]
  REPLACE [[(define harness-fingerprint-modulus 2305843009213693907)]])

# Combining becomes a sum, so order stops mattering and the two combine cases
# collapse to one value.
httparse_mutation(
  FILE ${FINGERPRINT} SPEC harness-self-tests.sps
  LABEL "fingerprint: combining stops being order sensitive"
  FIND [[              (modulo (+ (* h harness-fingerprint-multiplier) (+ (car rest) 1))]]
  REPLACE [[              (modulo (+ h (+ (car rest) 1))]])

httparse_mutation_run("${SOURCE_ROOT}" "${STAGE_DIR}")

# --- Pass 21: the hex rendering table -----------------------------------------
#
# MEASURED. No manifest is set, so provenance is skipped here
# exactly as it is for every other pass but 22 through 25 below:
# HTTPARSE_FINGERPRINT_FILES is unset, harness-verify-provenance! returns
# #t immediately, and the self-tests suite runs its own cases undisturbed. It
# is the self-tests' own "hex digits render lowercase" case that actually
# witnesses this mutation -- it check-equals fixed literals ("ff", "deadbeef",
# "0") rather than deriving its expectation from fingerprint.sls, so mutating
# the digit table fails an ordinary comparison: the process exits 1 (the
# harness's own "an assertion failed" status) with a "httparse-harness:
# FAIL " line, which is exactly what EXPECT_STATUS and EXPECT_OUTPUT_MATCHES
# below assert and exactly what the real run reports caught.

set(HEX_MUTATION_FIND [[(define harness-hex-digits "0123456789abcdef")]])
set(HEX_MUTATION_REPLACE [[(define harness-hex-digits "0123456789ABCDEF")]])

httparse_mutation_reset()

set(HTTPARSE_MUTATION_VERIFY_COMMAND
  "${HTTPARSE_CHEZ_EXECUTABLE}"
  "--script" "${STAGE_DIR}/test/support/launchers/chez-source.ss"
  "--library-root" "${STAGE_DIR}/test/support/harness"
  "--object-guard" "${GUARD_DIR}"
  "--program" "${STAGE_DIR}/test/support/harness/self/harness-self-tests.sps")

httparse_mutation(
  FILE ${FINGERPRINT} SPEC harness-self-tests.sps
  LABEL "fingerprint: hex digits become uppercase"
  FIND "${HEX_MUTATION_FIND}"
  REPLACE "${HEX_MUTATION_REPLACE}"
  EXPECT_STATUS 1
  EXPECT_OUTPUT_MATCHES "httparse-harness: FAIL ")

httparse_mutation_run("${SOURCE_ROOT}" "${STAGE_DIR}")

# --- Passes 22 and 23: the provenance check itself ----------------------------
#
# Wrapped in the exact-status helper so exit 3 -- the refusal -- is the green
# baseline, exactly as passes 4 and 5 do for the launcher. A mutation that makes
# the check more permissive drops the inner status to 0, the wrapper reports
# nonzero, and the mutation is caught. Continued below by passes 24 and 25,
# which this pair's own comments point to at the place each split off.
#
# THE MANIFEST NAMES ONE SOURCE ON PURPOSE
#
# HTTPARSE_EXPECT_COMMAND packs its argument vector with `|`, which is also
# the manifest separator, so a two-element manifest would be unpacked as two
# arguments. One source is enough: these passes test whether the check runs and
# is consulted, not how values combine, which pass 20 covers. Passes 24 and 25
# keep the same one-source manifest for the same reason.

set(RUNNER_BODY test/support/harness/httparse/test/harness.sls)

set(WRONG_FP_FILE "${WORK_DIR}/wrong.fingerprint")
file(WRITE "${WRONG_FP_FILE}" "not-a-fingerprint")

httparse_mutation_reset()

string(JOIN "|" PROVENANCE_MISMATCH_COMMAND
  "${CMAKE_COMMAND}" "-E" "env"
  "HTTPARSE_FINGERPRINT_FILES=${STAGE_DIR}/test/support/harness/httparse/test/fingerprint.sls"
  "HTTPARSE_EXPECT_FINGERPRINT_FILE=${WRONG_FP_FILE}"
  "--"
  "${HTTPARSE_CHEZ_EXECUTABLE}"
  "--script" "${STAGE_DIR}/test/support/launchers/chez-source.ss"
  "--library-root" "${STAGE_DIR}/test/support/harness"
  "--object-guard" "${GUARD_DIR}"
  "--program" "${STAGE_DIR}/test/support/harness/self/harness-self-tests.sps")

set(HTTPARSE_MUTATION_VERIFY_COMMAND
  "${CMAKE_COMMAND}"
  "-DHTTPARSE_EXPECT_EXIT=3"
  "-DHTTPARSE_EXPECT_COMMAND=${PROVENANCE_MISMATCH_COMMAND}"
  -P "${STAGE_DIR}/cmake/HttparseExpectExit.cmake")

httparse_mutation(
  FILE ${RUNNER_BODY} SPEC httparse.harness.provenance.chez.source
  LABEL "provenance: the comparison always reports agreement"
  FIND [[    ((string=? expected computed) #f)]]
  REPLACE [[    (#t #f)]])

httparse_mutation_run("${SOURCE_ROOT}" "${STAGE_DIR}")

# "provenance: harness-begin stops checking at all" cannot share this pass's
# WRONG_FP_FILE verify command. The reachability guard
# (test/support/harness/httparse/test/harness.sls,
# harness-provenance-reachability-diagnosis) makes it ambiguous: with the call
# removed, harness-provenance-checked never becomes #t, and the guard refuses
# with status 3 of its own accord -- the same number WRONG_FP_FILE's mismatch
# produces, for an unrelated reason. HttparseExpectExit compares only the
# number, so both baseline and mutation would satisfy EXPECT_EXIT 3 and the
# wrapper would report "exited as expected" either way: not caught, not
# because nothing noticed, but because two different refusals agree on the
# one status this vocabulary gives refusals. It is pass 24 below, which gives
# it a baseline the guard cannot also produce.

# Pass 23: the same wrapper, but the expectation file does not exist, so the
# refusal under test is the missing-expectation branch rather than the
# comparison. Its mutation leaves the guard `(not expected)` matching -- so
# there is no fallthrough to the next clause -- and changes only what the
# matched branch returns: silently #f instead of the diagnosis string.
# harness-verify-provenance! reads that #f as nothing to report and lets the
# run proceed as though the missing expectation had been verified.
#
# Measured: caught, but not by exiting 0. The self-tests' own
# "a missing expectation is its own diagnosis" case calls
# harness-provenance-diagnosis(#f, ...) directly and checks that a diagnosis
# comes back; with the branch mutated that check fails outright -- an
# ordinary comparison -- and the whole run reports httparse-harness
# status 1, not 3. The exact-status wrapper below compares that 1 against the
# declared EXPECT_EXIT of 3 and reports the mismatch. Both routes are a
# failed comparison; neither is a raise.
#
# The branch is mutated rather than the guard. Turning `(not expected)` into
# `(and #f expected)`, which never matches, falls through to
# `(string=? expected computed)` with expected still #f. string=? on a
# non-string is a type violation, so that form is caught by Chez's top-level
# handler killing the process at exit 255 -- outside the harness's own status
# vocabulary, and before a single self-test case runs -- rather than by the
# assertion naming this decision. A failed comparison is the better witness.
httparse_mutation_reset()

string(JOIN "|" PROVENANCE_ABSENT_COMMAND
  "${CMAKE_COMMAND}" "-E" "env"
  "HTTPARSE_FINGERPRINT_FILES=${STAGE_DIR}/test/support/harness/httparse/test/fingerprint.sls"
  "HTTPARSE_EXPECT_FINGERPRINT_FILE=${WORK_DIR}/never-produced.fingerprint"
  "--"
  "${HTTPARSE_CHEZ_EXECUTABLE}"
  "--script" "${STAGE_DIR}/test/support/launchers/chez-source.ss"
  "--library-root" "${STAGE_DIR}/test/support/harness"
  "--object-guard" "${GUARD_DIR}"
  "--program" "${STAGE_DIR}/test/support/harness/self/harness-self-tests.sps")

set(HTTPARSE_MUTATION_VERIFY_COMMAND
  "${CMAKE_COMMAND}"
  "-DHTTPARSE_EXPECT_EXIT=3"
  "-DHTTPARSE_EXPECT_COMMAND=${PROVENANCE_ABSENT_COMMAND}"
  -P "${STAGE_DIR}/cmake/HttparseExpectExit.cmake")

httparse_mutation(
  FILE ${RUNNER_BODY} SPEC httparse.harness.provenance-absent-expectation.chez.source
  LABEL "provenance: a missing expectation stops being a diagnosis"
  FIND [[    ((not expected)
     (string-append
      "no expectation was supplied, so nothing can say whether this run "
      "executed the text it was supposed to. This run computed " computed "."))]]
  REPLACE [[    ((not expected) #f)]])

httparse_mutation_run("${SOURCE_ROOT}" "${STAGE_DIR}")

# A stated blind spot: the third refusal -- a manifest naming an unreadable
# source -- has no mutation here. Making it witnessable would need an
# expectation crafted to equal what the mutant computes after the read fails,
# which is a value with no meaning outside that mutation. It is covered by its
# registered lane, httparse.harness.provenance-missing-body.chez.source,
# and this is recorded rather than papered over with an EXPECT_SURVIVES, which
# AGENTS.md reserves for the genuinely unwitnessable.

# --- Pass 24: the call site, witnessed against a baseline the guard cannot
# also satisfy -----------------------------------------------------------
#
# Continues "provenance: harness-begin stops checking at all" from pass 22,
# with a different baseline. WRONG_FP_FILE cannot be reused: it makes the
# unmutated lane's correct behaviour exit 3, and this mutation's broken
# behaviour *also* exits 3 (the reachability guard's own refusal), so a
# wrapper that only compares the exit number cannot tell them apart -- both
# read as "exited 3 as expected." Giving the lane an expectation it actually
# matches makes the unmutated baseline exit 0 instead, which the guard cannot
# produce (harness-provenance-checked is #t by the time harness-summary reads
# it, so the guard stays quiet and the self-tests' own pass/fail is what
# decides). The mutation still removes the call, so harness-provenance-checked
# stays #f, the guard still refuses, and the lane still exits 3 -- cleanly
# distinct from the 0 baseline.
#
# THE MANIFEST NAMES ONE SOURCE, AS ABOVE, AND ITS EXPECTATION IS COMPUTED, NOT
# WRITTEN BY HAND
#
# httparse_expected_fingerprint in test/CMakeLists.txt is a CMake function,
# unreachable from this standalone script, so the value is produced the same
# way it is: running fingerprint-manifest.ss over the staged fingerprint.sls.
# THE ALGORITHM IS NOT REIMPLEMENTED HERE applies here just as it does there.
set(CORRECT_FP_FILE "${WORK_DIR}/correct.fingerprint")
execute_process(
  COMMAND "${HTTPARSE_CHEZ_EXECUTABLE}" "--script"
          "${STAGE_DIR}/test/support/launchers/fingerprint-manifest.ss"
          "${STAGE_DIR}/test/support/harness"
          "${GUARD_DIR}"
          "${CORRECT_FP_FILE}"
          "${STAGE_DIR}/test/support/harness/httparse/test/fingerprint.sls"
  RESULT_VARIABLE fp_rc
  OUTPUT_VARIABLE fp_out
  ERROR_VARIABLE fp_err)
if(NOT fp_rc EQUAL 0)
  message(FATAL_ERROR
    "httparse-mutation: could not compute pass 24's baseline fingerprint "
    "(exit ${fp_rc}): ${fp_out}${fp_err}")
endif()

httparse_mutation_reset()

string(JOIN "|" PROVENANCE_UNCALLED_COMMAND
  "${CMAKE_COMMAND}" "-E" "env"
  "HTTPARSE_FINGERPRINT_FILES=${STAGE_DIR}/test/support/harness/httparse/test/fingerprint.sls"
  "HTTPARSE_EXPECT_FINGERPRINT_FILE=${CORRECT_FP_FILE}"
  "--"
  "${HTTPARSE_CHEZ_EXECUTABLE}"
  "--script" "${STAGE_DIR}/test/support/launchers/chez-source.ss"
  "--library-root" "${STAGE_DIR}/test/support/harness"
  "--object-guard" "${GUARD_DIR}"
  "--program" "${STAGE_DIR}/test/support/harness/self/harness-self-tests.sps")

set(HTTPARSE_MUTATION_VERIFY_COMMAND
  "${CMAKE_COMMAND}"
  "-DHTTPARSE_EXPECT_EXIT=0"
  "-DHTTPARSE_EXPECT_COMMAND=${PROVENANCE_UNCALLED_COMMAND}"
  -P "${STAGE_DIR}/cmake/HttparseExpectExit.cmake")

httparse_mutation(
  FILE ${RUNNER_BODY} SPEC httparse.harness.provenance.chez.source
  LABEL "provenance: harness-begin stops checking at all"
  FIND [[  (harness-verify-provenance!)
  (harness-clear-state!)]]
  REPLACE [[  (harness-clear-state!)]])

httparse_mutation_run("${SOURCE_ROOT}" "${STAGE_DIR}")

# --- Pass 25: the reachability guard itself -------------------------------
#
# harness-unreached-provenance.sps (test/support/harness/self/) deliberately
# never calls harness-begin, so its lane's baseline already exits 3 through
# the guard alone -- no WRONG_FP_FILE trick needed, and no
# HTTPARSE_EXPECT_FINGERPRINT_FILE either, since nothing in this lane's
# reachable code ever compares a fingerprint. Two mutations, because
# harness-provenance-reachability-diagnosis's rule has two halves that fail
# independently ("manifest and not checked?"): the
# diagnosis can stop firing, or checked? can stop meaning what its name says.
# Either one drops the baseline's 3 to 0, which EXPECT_EXIT catches cleanly --
# unlike pass 24, nothing else in this lane's execution can also produce 3, so
# no separate baseline is needed here.
set(UNREACHED_PROVENANCE_SPEC httparse.harness.unreached-provenance.chez.source)

httparse_mutation_reset()

string(JOIN "|" PROVENANCE_REACHABILITY_COMMAND
  "${CMAKE_COMMAND}" "-E" "env"
  "HTTPARSE_FINGERPRINT_FILES=${STAGE_DIR}/test/support/harness/httparse/test/fingerprint.sls"
  "--"
  "${HTTPARSE_CHEZ_EXECUTABLE}"
  "--script" "${STAGE_DIR}/test/support/launchers/chez-source.ss"
  "--library-root" "${STAGE_DIR}/test/support/harness"
  "--object-guard" "${GUARD_DIR}"
  "--program" "${STAGE_DIR}/test/support/harness/self/harness-unreached-provenance.sps")

set(HTTPARSE_MUTATION_VERIFY_COMMAND
  "${CMAKE_COMMAND}"
  "-DHTTPARSE_EXPECT_EXIT=3"
  "-DHTTPARSE_EXPECT_COMMAND=${PROVENANCE_REACHABILITY_COMMAND}"
  -P "${STAGE_DIR}/cmake/HttparseExpectExit.cmake")

httparse_mutation(
  FILE ${RUNNER_BODY} SPEC ${UNREACHED_PROVENANCE_SPEC}
  LABEL "provenance: the reachability diagnosis stops guarding"
  FIND [[  (if (and manifest (not (string=? manifest "")) (not checked?))]]
  REPLACE [[  (if #f]])

httparse_mutation(
  FILE ${RUNNER_BODY} SPEC ${UNREACHED_PROVENANCE_SPEC}
  LABEL "provenance: harness-provenance-checked starts true, so unreached looks reached"
  FIND [[(define harness-provenance-checked #f)]]
  REPLACE [[(define harness-provenance-checked #t)]])

httparse_mutation_run("${SOURCE_ROOT}" "${STAGE_DIR}")

# --- Pass 26: the aot launcher's library-path pairing ------------------------
#
# Measured against the shipped lane. The objects are compiled once, here, from
# the staged tree; the plant is a byte-divergent copy of the harness library
# dropped at its library-relative path inside the object directory, touched
# newer than the objects. Under the shipped pairing the plant sits in a
# directory Chez consults only for objects and is never read; under an
# unpaired shape every object directory is also a source directory, Chez finds
# the newer source, re-expands it, and load-program refuses the different
# compilation instance at 255 -- outside the status vocabulary, reported as a
# process that died, which is the honest shape of this defect.
httparse_mutation_reset()

set(AOT_PASS_DIR "${WORK_DIR}/aot-pairing")
file(MAKE_DIRECTORY "${AOT_PASS_DIR}/harness" "${AOT_PASS_DIR}/src"
     "${AOT_PASS_DIR}/source-guard")
execute_process(
  COMMAND "${HTTPARSE_CHEZ_EXECUTABLE}" --script
          "${STAGE_DIR}/test/support/launchers/chez-compile.ss"
          --library-root "${STAGE_DIR}/test/support/harness"
          --object-dir "${AOT_PASS_DIR}/harness"
          --library-root "${STAGE_DIR}/src"
          --object-dir "${AOT_PASS_DIR}/src"
          --program "${STAGE_DIR}/test/support/harness/self/harness-bootstrap.sps"
          --output "${AOT_PASS_DIR}/harness-bootstrap.so"
  RESULT_VARIABLE aot_compile_rc)
if(NOT aot_compile_rc EQUAL 0)
  message(FATAL_ERROR
    "httparse-mutation: pass 26 could not compile its artifacts (rc "
    "${aot_compile_rc}); nothing this pass reports would mean anything.")
endif()
file(MAKE_DIRECTORY "${AOT_PASS_DIR}/harness/httparse/test")
file(COPY_FILE
  "${STAGE_DIR}/test/support/harness/httparse/test/harness.sls"
  "${AOT_PASS_DIR}/harness/httparse/test/harness.sls")
file(APPEND "${AOT_PASS_DIR}/harness/httparse/test/harness.sls"
  "\n;; planted: only an unpaired library path can read this file\n")
file(TOUCH "${AOT_PASS_DIR}/harness/httparse/test/harness.sls")

set(HTTPARSE_MUTATION_VERIFY_COMMAND
  "${CMAKE_COMMAND}" "-E" "env" "HTTPARSE_EXECUTION_MODE=aot" "--"
  "${HTTPARSE_CHEZ_EXECUTABLE}" "--script"
  "${STAGE_DIR}/test/support/launchers/chez-aot.ss"
  "--object-dir" "${AOT_PASS_DIR}/harness"
  "--object-dir" "${AOT_PASS_DIR}/src"
  "--source-guard" "${AOT_PASS_DIR}/source-guard"
  "--program" "${AOT_PASS_DIR}/harness-bootstrap.so")

# EXPECT_STATUS and EXPECT_OUTPUT_MATCHES are exactly what this pass's own
# verify command produced against the mutated launcher, run once and read
# before this narrowing was added: rc 255 and, on stdout,
# "Exception: loading .../harness.sls yielded a different compilation
# instance of (httparse test harness) from that required by compiled
# program" -- Chez's own load-program refusal, reached because the plant is
# now the newer file in a directory the mutated library-directories call
# also treats as a source directory. Matches the header's measured
# prediction; EXPECT_OUTPUT_MATCHES anchors on the stable substring rather
# than the full sentence, which embeds this machine's absolute build path.
httparse_mutation(
  FILE test/support/launchers/chez-aot.ss SPEC httparse.harness.self.chez.aot
  LABEL "chez-aot launcher: the source guard is unpaired from the object directories"
  FIND [[(library-directories
 (map (lambda (dir) (cons source-guard-dir dir)) object-dirs))]]
  REPLACE [[(library-directories object-dirs)]]
  EXPECT_STATUS 255
  EXPECT_OUTPUT_MATCHES "different compilation instance")

# FIND carries its own trailing newline: the bare pattern also opens the "WHY
# source-directories IS ALSO EMPTIED" paragraph's own worked example above
# ("run once with (source-directories '()) and once left at Chez's unset
# default"), so without the newline the pattern matches twice -- code once,
# prose once -- and the SITES-count guard in httparse_mutation refuses it
# (found 2, expected 1) rather than silently mutating the comment along with
# the code. Confirmed against the shipped file: the comment's occurrence is
# followed by " and", never by end-of-line, so anchoring on the trailing
# newline is precise, not merely convenient.
httparse_mutation(
  FILE test/support/launchers/chez-aot.ss SPEC httparse.harness.self.chez.aot
  LABEL "chez-aot launcher: source-directories is not emptied"
  FIND [[(source-directories '())
]]
  REPLACE [[(source-directories (list "."))
]]
  EXPECT_SURVIVES
    "measured inert through the shipped lane: library resolution runs through library-directories, no file in the inline tree includes another, so this line narrows nothing reachable today; kept in the launcher because it costs one line and guards a future load or include added to the launcher itself. Reopening condition: a Chez that re-resolves a compiled library's sources at load time.")

httparse_mutation_run("${SOURCE_ROOT}" "${STAGE_DIR}")

# --- Passes 27 to 29: the aot-side launchers' new refusals -------------------
#
# The same argument as passes 9-17: a correctly set-up lane never reaches a
# refusal, so only a deliberately wrong invocation can notice one being
# deleted. Three passes, matching the three registered refusal lanes -- the
# decisions genuinely new in these files. The verbatim flag-block copies
# are deliberately not re-proven here; the launchers' own headers record
# what is and is not witnessed per copy.
#
# Unlike httparse_launcher_pass above, EXPECT_STATUS and
# EXPECT_OUTPUT_MATCHES are optional here rather than a fixed positional
# parameter: passes 9-17 were each written with their narrowing already
# known, but these three are narrowed only after being run once and read (see
# the call sites below), so the helper has to accept an invocation carrying
# neither, either, or both. cmake_parse_arguments pulls them out of ARGN
# ahead of the launcher's own command-line arguments -- none of which is
# spelled "EXPECT_STATUS" or "EXPECT_OUTPUT_MATCHES" -- and each is forwarded
# to httparse_mutation only when given, the same CMP0174-motivated
# reasoning as httparse_add_exit_code_test's WORKING_DIRECTORY
# (HttparseExpectExit.cmake): a keyword forwarded with an empty value
# would parse as though it were never given at this project's 3.26 floor, but
# silently, since CMP0174 does not warn about it before 3.31.
#
# The reset, the declaration and the run all happen inside this function on
# purpose, the same reason httparse_launcher_pass's header gives.
function(httparse_launcher_file_pass launcher_file lane label find replace)
  cmake_parse_arguments(pass "" "EXPECT_STATUS;EXPECT_OUTPUT_MATCHES" "" ${ARGN})

  httparse_mutation_reset()

  string(JOIN "|" packed
    "${HTTPARSE_CHEZ_EXECUTABLE}"
    "--script" "${STAGE_DIR}/${launcher_file}"
    ${pass_UNPARSED_ARGUMENTS})

  set(HTTPARSE_MUTATION_VERIFY_COMMAND
    "${CMAKE_COMMAND}"
    "-DHTTPARSE_EXPECT_EXIT=2"
    "-DHTTPARSE_EXPECT_COMMAND=${packed}"
    -P "${STAGE_DIR}/cmake/HttparseExpectExit.cmake")

  set(narrow_args "")
  if(DEFINED pass_EXPECT_STATUS)
    list(APPEND narrow_args EXPECT_STATUS "${pass_EXPECT_STATUS}")
  endif()
  if(DEFINED pass_EXPECT_OUTPUT_MATCHES)
    list(APPEND narrow_args EXPECT_OUTPUT_MATCHES "${pass_EXPECT_OUTPUT_MATCHES}")
  endif()

  httparse_mutation(
    FILE ${launcher_file} SPEC "${lane}"
    LABEL "${label}"
    FIND "${find}"
    REPLACE "${replace}"
    ${narrow_args})

  httparse_mutation_run("${SOURCE_ROOT}" "${STAGE_DIR}")
endfunction()

# Run once and read before narrowing, the same discipline as pass 26 above.
# EXPECT_STATUS is not used: this pass runs through HttparseExpectExit.cmake,
# same as every httparse_launcher_pass call above, and that
# wrapper's own message(FATAL_ERROR) always exits 1 on a non-matching real
# status -- 255 included -- so EXPECT_STATUS could only ever see 0 or 1 here
# and would narrow nothing; passes 9-17's header makes the identical point.
# What is real evidence is the wrapper's echoed command output: with the
# existence check gone, load-program itself is handed a path that is not
# there and Chez's own file layer refuses it directly --
# "Exception in load-program: failed for .../no-such-program.so: no such
# file or directory", observed on the wrapper's echoed stdout.
httparse_launcher_file_pass(
  test/support/launchers/chez-aot.ss
  httparse.harness.chez-aot-launcher-missing-program.chez.aot
  "chez-aot launcher: a missing compiled program is accepted"
  [[(if (not (file-exists? program))]]
  [[(if #f]]
  "--object-dir" "${AOT_PASS_DIR}/harness"
  "--source-guard" "${AOT_PASS_DIR}/source-guard"
  "--program" "${AOT_PASS_DIR}/no-such-program.so"
  EXPECT_OUTPUT_MATCHES "Exception in load-program")

# Run once and read, as above; no EXPECT_STATUS, for the same wrapper reason
# given above the missing-program pass. Reusing the harness object directory
# as the guard (see the rationale where this pass is called) reproduces pass
# 26's scenario by a different route: the guard is the harness's object
# directory, so once the emptiness check stops blocking it, that same
# directory's library-directories pairing makes it a source directory too,
# and Chez's load-program hits the identical "different compilation
# instance" refusal pass 26's pairing mutation does -- two different deleted
# checks, coincident only in this fixture because both ultimately leave the
# harness object directory readable as a source directory.
httparse_launcher_file_pass(
  test/support/launchers/chez-aot.ss
  httparse.harness.chez-aot-launcher-dirty-source-guard.chez.aot
  "chez-aot launcher: a dirty source guard is accepted"
  [[(if (not (null? (directory-list source-guard-dir)))]]
  [[(if #f]]
  "--object-dir" "${AOT_PASS_DIR}/harness"
  "--object-dir" "${AOT_PASS_DIR}/src"
  "--source-guard" "${AOT_PASS_DIR}/harness"
  "--program" "${AOT_PASS_DIR}/harness-bootstrap.so"
  EXPECT_OUTPUT_MATCHES "different compilation instance")

# Run once and read, as above; no EXPECT_STATUS, for the same wrapper reason
# given above the missing-program pass. R6RS's map requires its argument
# lists to be the same length; with the pairing-count refusal gone, (map
# cons library-roots object-dirs) is handed a 2-element and a 1-element list
# and Chez's own map refuses them directly, observed on the wrapper's echoed
# stdout as "Exception in map: lists (...) and (...) differ in length".
httparse_launcher_file_pass(
  test/support/launchers/chez-compile.ss
  httparse.harness.chez-compile-launcher-unpaired-roots.chez.aot
  "chez-compile launcher: unpaired roots are accepted"
  [[(if (not (= (length library-roots) (length object-dirs)))]]
  [[(if #f]]
  "--library-root" "${STAGE_DIR}/test/support/harness"
  "--library-root" "${STAGE_DIR}/src"
  "--object-dir" "${AOT_PASS_DIR}/harness"
  "--program" "${STAGE_DIR}/test/support/harness/self/harness-bootstrap.sps"
  "--output" "${AOT_PASS_DIR}/unpaired.so"
  EXPECT_OUTPUT_MATCHES "Exception in map")

# --- Pass 30: the provenance decisions a one-source manifest cannot witness --
#
# Passes 22-25 pack their verify commands through HTTPARSE_EXPECT_COMMAND,
# whose | packing forbids a multi-source manifest -- their manifests name one
# source on purpose, so the split character and the combining order have
# no witness there. This pass runs the lane command bare: its baseline is
# a PASSING provenance run (exit 0), and each catchable mutation turns that
# into the mismatch refusal (exit 3), so no wrapper is needed and the
# two-source manifest rides in an ordinary env entry.
#
# NEITHER MANIFEST FILE IS ONE THIS PASS MUTATES
#
# harness.sls is the file both mutations below edit, since
# harness-verify-provenance! lives there. Measured against the shipped
# suite: with harness.sls one of the two fingerprinted sources, editing it
# at all fails the comparison before the mutated logic is even relevant, so
# EXPECT_STATUS 3 catches "harness.sls changed", not the decision each
# mutation names. A control proves it: an inert trailing space added to an
# unrelated comment at the top of the file, nowhere near provenance, split,
# or combine, trips the identical PROVENANCE-ERROR refusal. A catch that
# catches anything discriminates nothing (AGENTS.md). This pass fingerprints
# fingerprint.sls and harness-self-tests.sps instead -- two real files a real
# lane's manifest would name, neither touched by any mutation below -- so a
# mismatch can only come from the split or combine logic itself. Pass 31
# needs the opposite choice for the one decision this manifest shape cannot
# reach.
httparse_mutation_reset()

set(FINGERPRINT_MANIFEST
  "${STAGE_DIR}/test/support/harness/httparse/test/fingerprint.sls|${STAGE_DIR}/test/support/harness/self/harness-self-tests.sps")
set(FINGERPRINT_EXPECT_FILE "${WORK_DIR}/fingerprint-split-combine.fingerprint")
execute_process(
  COMMAND "${HTTPARSE_CHEZ_EXECUTABLE}" --script
          "${STAGE_DIR}/test/support/launchers/fingerprint-manifest.ss"
          "${STAGE_DIR}/test/support/harness"
          "${GUARD_DIR}"
          "${FINGERPRINT_EXPECT_FILE}"
          "${STAGE_DIR}/test/support/harness/httparse/test/fingerprint.sls"
          "${STAGE_DIR}/test/support/harness/self/harness-self-tests.sps"
  RESULT_VARIABLE fingerprint_expect_rc)
if(NOT fingerprint_expect_rc EQUAL 0)
  message(FATAL_ERROR
    "httparse-mutation: pass 30 could not compute its two-source "
    "expectation (rc ${fingerprint_expect_rc}). The expectation must come from the "
    "staged copies -- the stage is what the run reads -- so nothing this "
    "pass reports would mean anything without it.")
endif()

set(HTTPARSE_MUTATION_VERIFY_COMMAND
  "${CMAKE_COMMAND}" "-E" "env"
  "HTTPARSE_FINGERPRINT_FILES=${FINGERPRINT_MANIFEST}"
  "HTTPARSE_EXPECT_FINGERPRINT_FILE=${FINGERPRINT_EXPECT_FILE}"
  "--"
  "${HTTPARSE_CHEZ_EXECUTABLE}"
  "--script" "${STAGE_DIR}/test/support/launchers/chez-source.ss"
  "--library-root" "${STAGE_DIR}/test/support/harness"
  "--object-guard" "${GUARD_DIR}"
  "--program" "${STAGE_DIR}/test/support/harness/self/harness-self-tests.sps")

set(RUNNER_BODY test/support/harness/httparse/test/harness.sls)

# The manifest arrives |-joined. Split on anything else and the whole
# two-source string is one path naming no file, so the run refuses with the
# unreadable-source diagnosis -- still 3, still caught, and the label says
# which decision died. Measured: "PROVENANCE-ERROR cannot read
# <fingerprint.sls's path>|<harness-self-tests.sps's path>, which this run
# is supposed to have executed." -- the | that should have separated two
# paths is embedded in the one bogus path the comma-split produces.
httparse_mutation(
  FILE ${RUNNER_BODY} SPEC httparse.harness.provenance.chez.source
  LABEL "runner: the manifest is split on the wrong character"
  FIND [[        (let loop ((rest (harness-split raw #\|)) (acc '()))]]
  REPLACE [[        (let loop ((rest (harness-split raw #\,)) (acc '()))]]
  EXPECT_STATUS 3
  EXPECT_OUTPUT_MATCHES "PROVENANCE-ERROR cannot read")

# Combining is order-sensitive by design, so
# accumulating in reverse computes a different digest over the same two
# fingerprints -- both individually unchanged, since neither manifest file
# is edited by this mutation, so the mismatch below can only come from the
# order they were combined in, not from either file's own bytes. Measured:
# "PROVENANCE-ERROR fingerprint mismatch: the build expected <combined
# forward> but this run computed <combined reversed>."
httparse_mutation(
  FILE ${RUNNER_BODY} SPEC httparse.harness.provenance.chez.source
  LABEL "runner: the manifest digests combine in reverse order"
  FIND [[                               (harness-fingerprint-combine (reverse acc)))))]]
  REPLACE [[                               (harness-fingerprint-combine acc))))]]
  EXPECT_STATUS 3
  EXPECT_OUTPUT_MATCHES "PROVENANCE-ERROR fingerprint mismatch")

httparse_mutation_run("${SOURCE_ROOT}" "${STAGE_DIR}")

# --- Pass 31: the provenance exit constant, witnessed through a deliberately
# self-referential manifest --------------------------------------------------
#
# The one decision pass 30 cannot carry: harness-provenance-failure!'s single
# shared exit line, (adapter-exit harness-status-provenance). Wrong that
# constant and a provenance failure exits indistinguishably from an
# assertion failure -- the whole reason status 3 was reserved -- but under
# pass 30's own manifest (fingerprint.sls and harness-self-tests.sps,
# neither edited by this mutation) provenance keeps succeeding, so the line
# is never reached there: a passing baseline is httparse_mutation_run's
# own precondition, no pass may deliberately fail provenance, and a mutation
# whose only effect follows a failure that never happens would report as an
# unwitnessed EXPECT_SURVIVES.
#
# The way to reach the line is the manifest pass 30 deliberately avoids: name
# harness.sls itself -- the file this mutation, like both of pass 30's,
# edits. That self-reference is what pass 30 avoids (its header records the
# control that shows why); here it is the mechanism. Any edit to harness.sls
# staled against a manifest that fingerprints harness.sls fails provenance
# on its own -- exactly a run whose own text no longer matches what the
# build measured, which is what a real stale artifact looks like, not a
# contrived path to this line. That failure calls
# harness-provenance-failure!, which reaches the mutated line and exits
# harness-status-failed (1) instead of harness-status-provenance (3) -- the
# summary text printed just above the exit call still names status 3, built
# from the untouched constant, but the process's actual exit code is 1, so a
# caller reading only the exit status draws exactly the
# indistinguishable-from-an-assertion-failure conclusion this constant
# exists to prevent.
#
# AGENTS.md: a decision that can be witnessed does not get an
# EXPECT_SURVIVES.
httparse_mutation_reset()

set(FINGERPRINT_EXIT_MANIFEST
  "${STAGE_DIR}/test/support/harness/httparse/test/fingerprint.sls|${STAGE_DIR}/test/support/harness/httparse/test/harness.sls")
set(FINGERPRINT_EXIT_EXPECT_FILE "${WORK_DIR}/fingerprint-exit-constant.fingerprint")
execute_process(
  COMMAND "${HTTPARSE_CHEZ_EXECUTABLE}" --script
          "${STAGE_DIR}/test/support/launchers/fingerprint-manifest.ss"
          "${STAGE_DIR}/test/support/harness"
          "${GUARD_DIR}"
          "${FINGERPRINT_EXIT_EXPECT_FILE}"
          "${STAGE_DIR}/test/support/harness/httparse/test/fingerprint.sls"
          "${STAGE_DIR}/test/support/harness/httparse/test/harness.sls"
  RESULT_VARIABLE fingerprint_exit_expect_rc)
if(NOT fingerprint_exit_expect_rc EQUAL 0)
  message(FATAL_ERROR
    "httparse-mutation: pass 31 could not compute its two-source "
    "expectation (rc ${fingerprint_exit_expect_rc}). The expectation must come from "
    "the staged copies -- the stage is what the run reads -- so nothing "
    "this pass reports would mean anything without it.")
endif()

set(HTTPARSE_MUTATION_VERIFY_COMMAND
  "${CMAKE_COMMAND}" "-E" "env"
  "HTTPARSE_FINGERPRINT_FILES=${FINGERPRINT_EXIT_MANIFEST}"
  "HTTPARSE_EXPECT_FINGERPRINT_FILE=${FINGERPRINT_EXIT_EXPECT_FILE}"
  "--"
  "${HTTPARSE_CHEZ_EXECUTABLE}"
  "--script" "${STAGE_DIR}/test/support/launchers/chez-source.ss"
  "--library-root" "${STAGE_DIR}/test/support/harness"
  "--object-guard" "${GUARD_DIR}"
  "--program" "${STAGE_DIR}/test/support/harness/self/harness-self-tests.sps")

set(RUNNER_BODY test/support/harness/httparse/test/harness.sls)

# Measured: the mutated harness.sls fails its own fingerprint comparison --
# "PROVENANCE-ERROR fingerprint mismatch: the build expected <digest of the
# pristine pair> but this run computed <digest with the mutated harness.sls>"
# -- and the process exits 1 (harness-status-failed, what the mutation put
# in the exit call), not 3 (harness-status-provenance, what the unmutated
# line calls and what the summary text printed just above it still names).
httparse_mutation(
  FILE ${RUNNER_BODY} SPEC httparse.harness.provenance.chez.source
  LABEL "runner: a provenance failure exits as an assertion failure"
  FIND [[  (adapter-exit harness-status-provenance))]]
  REPLACE [[  (adapter-exit harness-status-failed))]]
  EXPECT_STATUS 1
  EXPECT_OUTPUT_MATCHES "PROVENANCE-ERROR fingerprint mismatch")

httparse_mutation_run("${SOURCE_ROOT}" "${STAGE_DIR}")

# Every pass above has now run exactly once, so the accumulated total is
# final. Compared against the numbers declared at the top of this file --
# see EXPECTED_PASSES and EXPECTED_MUTATIONS and the measured-count comment
# beside them -- so a whole pass, or a single mutation inside one, silently
# going missing is a build failure here rather than a stale comment nobody
# rereads.
httparse_mutation_totals(actual_passes actual_mutations)
if(NOT actual_passes EQUAL EXPECTED_PASSES OR NOT actual_mutations EQUAL EXPECTED_MUTATIONS)
  message(FATAL_ERROR
    "httparse-mutation: expected ${EXPECTED_PASSES} passes / "
    "${EXPECTED_MUTATIONS} mutations, got ${actual_passes} "
    "passes / ${actual_mutations} mutations. A httparse_mutation_run call -- "
    "a whole pass -- or a httparse_mutation() declaration within one was "
    "deleted, or one was added without updating the expected count at the top "
    "of this file. This is what notices a deleted pass group when every "
    "individual specification still reports green.")
endif()

message(STATUS
  "httparse-spec: scheme mutation suite complete (${actual_passes} passes, "
  "${actual_mutations} mutations)")

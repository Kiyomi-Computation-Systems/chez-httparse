# Upstream brief: a keyword table waits one byte past a decided match

**For a fresh session working in `byte-machine` (not this repository).**
Recorded here under decision 0006 item 4 — every gap the shakeout consumer
finds is recorded, including the ones it works around and the ones it does
not.

Repository: `github.com/Kiyomi-Computation-Systems/byte-machine`, local
checkout `~/github/byte-machine`. This consumer is pinned at `v0.4.0`
(`18fcc8b`), generated ABI 7. Read `AGENTS.md` and `.superpowers/` first: that
project has its own milestone/slice ritual, decision records, a `CHANGELOG.md`
and a release ledger, and this work is expected to go through them rather than
around them.

This is the **fifth** brief from this consumer. The first three — the empty
span, the keyword table, and a pause's reason — shipped at `v0.2.0`, `v0.3.0`
and `v0.4.0`; the fourth, a parser that cannot be started in a mode, is open
and non-blocking.

**This one is not blocking either, and there is no workaround.** It is filed
because the behaviour is general, because it is observable, and because the
consumer has a reduced reproduction and a live reference implementation that
disagrees.

---

## 1. The ask, in one paragraph

`make-keyword-table-node` returns `need-input` when its input ends exactly on
the last byte of a keyword, even when **no entry in the table can extend that
keyword**. In that position the match is decided and the terminal edge could
be taken. Take it.

## 2. The reduced reproduction

A table with one entry, `AB`, and nothing that extends it:

```scheme
(make-machine 'probe 'entry '()
  (list (make-callback-declaration 'on-hit 'event #t '() #f #f))
  '()
  (list (make-error-declaration 'boom 'strict "boom" #f))
  (list (make-keyword-table-node 'entry
          (list (make-keyword-entry '(65 66) 'hit #f))
          (make-edge 'e 'reexecute) 'e #f #f)
        (make-callback-node 'hit 'on-hit 'park '() 'park #f #f)
        (make-byte-dispatch-node 'park '() (make-edge 'park 'advance) 'done #f)
        (make-finish-node 'done #f)
        (make-error-node 'e 'boom #f))
  'boom #f)
```

Feed it, whole buffer, and count how many times `on-hit` fired:

```
"AB"   status need-input   hits 0
"ABC"  status error        hits 1
```

Two bytes decide the match and the callback does not run. A third byte —
which the table cannot use, and which goes on to fail — makes it run.

## 3. Why it matters here

This consumer is an HTTP parser measured byte-exactly against llhttp's own
recorded traces. llhttp's protocol constant is one such table, and llparse —
the generator llhttp is built with — fires the completion event on the
keyword's last byte. A live llhttp, built from the commit this project's
corpus was vendored from:

```
input "HTTP" as a response, whole buffer

llhttp:  off=0 message begin
         off=0 len=4 span[protocol]="HTTP"
         off=4 protocol complete
ours:    off=0 message begin
         off=0 len=4 span[protocol]="HTTP"
```

And where the completion leads somewhere that needs no further byte, the
divergence is more than one line: `TRACE /x?y=1 RTSP` ends on the protocol,
and llhttp prints `protocol complete` **and** the method-compatibility error
it leads to, both at offset 17.

Across ~110,000 generated-input comparisons against that live llhttp, this is
one of two remaining divergence classes, and the only one filed upstream. The
253-fixture corpus cannot see it: every recorded fixture has a byte after the
token.

## 4. What the shape probably is not

**Not "always take the terminal".** A table holding both `GET` and
`GET_PARAMETER` genuinely cannot decide at `GET` with no further input, and
returning `need-input` there is correct. The claim is narrower: when the
current trie node is terminal and has **no children**, nothing a later byte
could say changes the answer.

**Not a change to the no-match edge.** A walk that has failed already
reexecutes at the byte that broke it; this is about a walk that has
succeeded.

**Not observable through `verify`.** The machine is well-formed either way.
It is a runtime progress question, which is why a consumer found it and a
verifier did not.

## 5. What this consumer can offer

- The reproduction above, which is self-contained and needs no HTTP.
- A live llhttp oracle lane (`HTTPARSE_LLHTTP_ROOT`) that will report the
  class as empty the day this changes, and two pinned witnesses that turn red
  with it.
- A correction to the **second** brief, which is now known to contain a wrong
  fact about llhttp: it says `GET-PARAMETER / HTTP/1.1` must match whole.
  llhttp's method map keys that method `GET_PARAMETER`, with an underscore,
  so the hyphenated spelling matches `GET` and then fails. The prefix-pair
  argument the brief rests on is unaffected — `GET` is still a proper prefix
  of `GET_PARAMETER` — but the example was wrong, and the table shipped for
  the right reason by luck as much as by evidence.

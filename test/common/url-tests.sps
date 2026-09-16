;;; The url sub-parser, asserted in llhttp's own trace text.
;;;
;;; These cases render through the SAME adapter the conformance driver uses,
;;; so an expectation here is a block of lines copied out of a fixture rather
;;; than a transliteration of it.
;;;
;;; WHAT THIS LANE ADDS OVER THE RATCHET, which already runs all 21 of
;;; `url.md` at every chunk size, is TWO things:
;;;
;;;   1. Literal expectations that survive a corpus refresh, one per distinct
;;;      SHAPE rather than one per fixture -- so the eight proxy fixtures that
;;;      differ only in what the host text looks like are left to the ratchet.
;;;
;;;   2. The exits, WHICH NO FIXTURE IN `url.md` REACHES. Not one of its 21
;;;      inputs contains a space, a CR or an LF, and upstream gives every node
;;;      inside a URL an edge for each. Those cases were MEASURED against a
;;;      purpose-built url oracle -- `test/md-test.ts`'s `buildURL()`, built
;;;      through llhttp's own `test/fixtures/index.ts` -- and never read off
;;;      this parser. Decision 0010 is the rule; M9 and M10 set the precedent.
(import (rnrs)
        (httparse test harness)
        (httparse test adapter)
        (httparse test trace-format)
        (httparse url-grammar)
        (byte-machine verify)
        (byte-machine interpret)
        (byte-machine runtime))

(define machine
  (make-interpreted-machine (verify-machine (make-url-machine))))

;; trace : String -> (Listof String)
;; NO MODE AND NO HARNESS MODE. The url binary is built with no `-D` at all,
;; so there is nothing for a fixture's meta to select and nothing to pass.
(define (trace input)
  (let* ((r (make-trace-recorder))
         (p (make-parser machine (trace-recorder-url-bindings r) #f))
         (bv (string->utf8 input))
         (refused
          (call/cc
           (lambda (k)
             (with-exception-handler
              (lambda (e) (if (adapter-error? e) (k #t) (raise e)))
              (lambda ()
                (let ((res (parser-feed! p bv 0 (bytevector-length bv))))
                  (when (eq? (parser-result-status res) 'error)
                    (trace-recorder-note-error! r (parser-result-error res)))
                  #f)))))))
    (append (map utf8->string (trace-format (trace-recorder-events r)))
            (if refused '("(refused)") '()))))

(harness-begin "unit.url")

(harness-group "the shapes url.md records"
  (lambda ()
    (harness-case "an absolute url is five spans"
      (lambda ()
        ;; `url.md` "Absolute URL", copied entire.
        (check-equal "trace" (trace "http://example.com/path?query=value#schema")
                     '("off=0 len=4 span[url.schema]=\"http\""
                       "off=7 len=11 span[url.host]=\"example.com\""
                       "off=18 len=5 span[url.path]=\"/path\""
                       "off=24 len=11 span[url.query]=\"query=value\""
                       "off=36 len=6 span[url.fragment]=\"schema\""))))
    (harness-case "a relative url has no schema and no host"
      (lambda ()
        ;; `url.md` "Relative URL". THE PATH SPAN INCLUDES ITS LEADING SLASH,
        ;; which is why `start` peeks the delimiter into the span rather than
        ;; consuming it first.
        (check-equal "trace" (trace "/path?query=value#schema")
                     '("off=0 len=5 span[url.path]=\"/path\""
                       "off=6 len=11 span[url.query]=\"query=value\""
                       "off=18 len=6 span[url.fragment]=\"schema\""))))
    (harness-case "a fragment may follow a path with no query between"
      (lambda ()
        ;; `url.md` "URL fragment".
        (check-equal "trace" (trace "/toto.html#titi")
                     '("off=0 len=10 span[url.path]=\"/toto.html\""
                       "off=11 len=4 span[url.fragment]=\"titi\""))))
    (harness-case "a second `?` inside a query is ordinary"
      (lambda ()
        ;; The whole point of `url.md` "Extra `?` in query string", at the one
        ;; length that shows it: the query runs THROUGH the second `?` rather
        ;; than ending at it, so this is one span and not two.
        (check-equal "trace" (trace "/p?a=1?b=2")
                     '("off=0 len=2 span[url.path]=\"/p\""
                       "off=3 len=7 span[url.query]=\"a=1?b=2\""))))
    (harness-case "userinfo belongs to the host span, `@` and all"
      (lambda ()
        ;; `url.md` "Complex URL with basic auth ...", shortened to the shape.
        ;; llhttp does not split the userinfo out: one span, from after the
        ;; `//` to the `/`.
        (check-equal "trace" (trace "http://a:b@host.com:8080/p")
                     '("off=0 len=4 span[url.schema]=\"http\""
                       "off=7 len=17 span[url.host]=\"a:b@host.com:8080\""
                       "off=24 len=2 span[url.path]=\"/p\""))))
    (harness-case "a bracketed IPv6 host is host text like any other"
      (lambda ()
        ;; `url.md` "Proxy IPv6 request with port". `[` and `]` are matched
        ;; back into the server node and nothing parses what is between them.
        (check-equal "trace" (trace "http://[1:2::3:4]:67/")
                     '("off=0 len=4 span[url.schema]=\"http\""
                       "off=7 len=13 span[url.host]=\"[1:2::3:4]:67\""
                       "off=20 len=1 span[url.path]=\"/\""))))))

(harness-group "the four errors url.md records"
  (lambda ()
    (harness-case "a schema not followed by `//` reports PAST the slash it ate"
      (lambda ()
        ;; `url.md` "Failing on broken schema", copied entire, and the reason
        ;; this lane exists at all. The offset is 8 and not 7: matching `//`
        ;; against `/p` consumes the `/` before discovering the mismatch, and
        ;; the consumed prefix stays consumed. A machine that checked the two
        ;; bytes without consuming would report 7 and pass every other case.
        (check-equal "trace" (trace "schema:/path?query=value#schema")
                     '("off=0 len=6 span[url.schema]=\"schema\""
                       "off=8 error code=7 reason=\"Unexpected char in url schema\""))))
    (harness-case "a second `@` is refused, and the open host span is not printed"
      (lambda ()
        ;; `url.md` "Double `@`", copied entire. The schema span closed and so
        ;; it prints; the HOST span was open at the error and does not. That
        ;; is the same rule the message parser's `span[method]` follows -- an
        ;; open span is abandoned by an error, never flushed.
        (check-equal "trace" (trace "http://a:b@@hostname:443/")
                     '("off=0 len=4 span[url.schema]=\"http\""
                       "off=12 error code=7 reason=\"Double @ in url\""))))
    (harness-case "a tab is refused one byte PAST itself"
      (lambda ()
        ;; `url.md` "Disallow tab in URL", copied entire. Upstream wraps EVERY
        ;; node in `.match(['\t','\f'], errorInvalid)` -- a match, which
        ;; consumes -- so the offset is 5 for a tab at 4.
        (check-equal "trace" (trace "/foo\tbar/")
                     '("off=5 error code=7 reason=\"Invalid characters in url\""))))
    (harness-case "and so is a form feed, at the same offset"
      (lambda ()
        ;; `url.md` "Disallow form-feed in URL", copied entire. The pair is
        ;; one byte case in one helper, so this case is what says the helper
        ;; covers both rather than one and a typo.
        (check-equal "trace" (trace "/foo\x0c;bar/")
                     '("off=5 error code=7 reason=\"Invalid characters in url\""))))))

;;; NOT ONE OF `url.md`'S 21 INPUTS CONTAINS A SPACE, A CR OR AN LF, and
;;; upstream gives every node inside a URL an edge for each of the three. So
;;; this whole group is graph the corpus cannot reach, and every expectation
;;; below was READ OFF A PURPOSE-BUILT URL ORACLE rather than off this parser.
;;;
;;; The oracle is `test/md-test.ts`'s own `buildURL()`: `new llhttp.URL(p,
;;; true)`, built, with BOTH EXITS LOOPED BACK TO THE ENTRY --
;;;
;;;     node.exit.toHTTP.otherwise(node.entry.normal);
;;;     node.exit.toHTTP09.otherwise(node.entry.normal);
;;;
;;; -- which is why a space does not end the parse here but starts another
;;; URL. That loop is a property of the TEST BUILD, not of the URL parser: in
;;; a real llhttp the two exits join the HTTP machine at `HTTP/`. This machine
;;; is built for that binary, so it has the loop, and these cases are what say
;;; so out loud.
(harness-group "the exits, measured against a url oracle"
  (lambda ()
    (harness-case "a space ends the url and the next one begins"
      (lambda ()
        ;; oracle: `/path /next` -> two path spans, the second at 6.
        (check-equal "trace" (trace "/path /next")
                     '("off=0 len=5 span[url.path]=\"/path\""
                       "off=6 len=5 span[url.path]=\"/next\""))))
    (harness-case "after a space, an alphabetic run is a SCHEMA and not a path"
      (lambda ()
        ;; oracle: `http://host.com xyz` -> the third span is `url.schema`.
        ;; The loop re-enters at `start`, which peeks ALPHA into the schema
        ;; span -- so what follows a space is judged from scratch.
        (check-equal "trace" (trace "http://host.com xyz")
                     '("off=0 len=4 span[url.schema]=\"http\""
                       "off=7 len=8 span[url.host]=\"host.com\""
                       "off=16 len=3 span[url.schema]=\"xyz\""))))
    (harness-case "a CR must bring its LF"
      (lambda ()
        ;; oracle: `/p#frag\rX` -> `Expected CRLF` at 8. The fragment span
        ;; CLOSES first and prints, because the exit edge ends the span before
        ;; it reaches the CRLF check.
        (check-equal "trace" (trace "/p#frag\rX")
                     '("off=0 len=2 span[url.path]=\"/p\""
                       "off=3 len=4 span[url.fragment]=\"frag\""
                       "off=8 error code=7 reason=\"Expected CRLF\""))))
    (harness-case "a CRLF ends the url the way a space does"
      (lambda ()
        ;; oracle: `/p#frag\r\n/q` -> three spans, the last at 9.
        (check-equal "trace" (trace "/p#frag\r\n/q")
                     '("off=0 len=2 span[url.path]=\"/p\""
                       "off=3 len=4 span[url.fragment]=\"frag\""
                       "off=9 len=2 span[url.path]=\"/q\""))))
    (harness-case "a host that ends at a `?` KEEPS the `?`"
      (lambda ()
        ;; oracle: `http://host.com?q=1` -> `span[url.host]="host.com?"`.
        ;;
        ;; A QUIRK, TRANSCRIBED AND NOT REPAIRED. Upstream's edge is
        ;; `.match('?', spanEnd('host', spanStart('query', query)))`, and
        ;; `match` ADVANCES before the span end runs -- so the host span
        ;; closes one byte late. Reading the source would let you argue it
        ;; either way; the oracle does not.
        (check-equal "trace" (trace "http://host.com?q=1")
                     '("off=0 len=4 span[url.schema]=\"http\""
                       "off=7 len=9 span[url.host]=\"host.com?\""
                       "off=16 len=3 span[url.query]=\"q=1\""))))
    (harness-case "a url may not BEGIN with a space, though it may end at one"
      (lambda ()
        ;; oracle: `@nope` -> `Unexpected start char in url` at 0. `start`
        ;; refuses SP, CR and LF outright where every later node treats them
        ;; as the end of the URL.
        (check-equal "trace" (trace "@nope")
                     '("off=0 error code=7 reason=\"Unexpected start char in url\""))))))

(harness-finish)

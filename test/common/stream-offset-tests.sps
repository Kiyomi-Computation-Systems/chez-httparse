;;; What `parser-stream-offset` answers inside a callback.
;;;
;;; `docs/api.org` gives it one answer per kind of callback:
;;;
;;;   EVENT  the bytes the parser has taken before the callback, which is the
;;;          position llhttp's traces print as `off=` for that event;
;;;   SPAN   the position of the fragment's END, so the fragment starts at the
;;;          offset less `(- to from)`, whichever feed delivered it.
;;;
;;; An embedder that measures the bytes no span covers -- the blank lines
;;; before a request line, the space after a method -- subtracts one of these
;;; from another, so both are a contract. This lane holds the COMMITTED parser
;;; to them over every fixture in the corpus, at several chunk sizes.
;;;
;;; EVERY EXPECTED NUMBER COMES FROM OUTSIDE THE PARSER. An event's is the
;;; `off=` its fixture's log records. A fragment's is the driver's own
;;; arithmetic: where its chunk began in the input, plus how far into the chunk
;;; `to` lies.
;;;
;;; EACH CHUNK IS FED FROM A BUFFER OF ITS OWN, AND NOT FROM INDEX 0. That is
;;; what an embedder reading a socket does, and then `from` and `to` index the
;;; buffer in hand and say nothing about the stream. Slices of one whole-input
;;; buffer fed from 0 make `to` equal the stream position by coincidence, and
;;; every other lane that reads the offset in a span callback feeds that way: a
;;; runtime that handed the callback `to` instead passes all of them.
;;;
;;; THE CONFORMANCE LANE SEES THE SPAN HALF ONLY BY THE ADAPTER'S CHOICE. It
;;; renders through the adapter, which reads this offset for both kinds of
;;; line: for an event because nothing else carries a position, and for a span
;;; because it happens to. An adapter that took a span's start from its own
;;; feed bookkeeping would render identical traces and stop checking it. And
;;; the lanes that run the reference interpreter cannot see it at all: there
;;; the offset is current before any callback is reached, so a runtime that
;;; forgot to commit it would pass them.
(import (rnrs)
        (only (chezscheme) directory-list)
        (httparse test harness)
        (httparse test corpus-load)
        (httparse test corpus-decode)
        (httparse test adapter)
        (generated httparse-message)
        (generated httparse-url)
        (byte-machine runtime))

(define (read-text path)
  (utf8->string (call-with-port (open-file-input-port path) get-bytevector-all)))

(define corpus-dir (adapter-environment-variable "HTTPARSE_CORPUS_DIR"))

(define (string-prefix? prefix s)
  (and (<= (string-length prefix) (string-length s))
       (string=? prefix (substring s 0 (string-length prefix)))))

(define (string-suffix? suffix s)
  (let ((n (string-length s)) (m (string-length suffix)))
    (and (>= n m) (string=? (substring s (- n m) n) suffix))))

;; --- the corpus -------------------------------------------------------------

;; corpus-files : String -> (Listof String)
;; Every `.md` in one of the corpus's directories, read from the directory
;; rather than listed, so a refresh that adds a file cannot leave it unswept.
(define (corpus-files dir)
  (map (lambda (name) (string-append dir "/" name))
       (list-sort string<?
                  (filter (lambda (name) (string-suffix? ".md" name))
                          (directory-list (string-append corpus-dir "/" dir))))))

;; fixtures-in : String -> (Listof (Pair String Fixture))
;; Every fixture in one corpus file, keyed by `file#n`.
(define (fixtures-in rel)
  (let loop ((fs (corpus-parse-file (read-text (string-append corpus-dir "/" rel))))
             (i 1) (acc '()))
    (if (null? fs)
        (reverse acc)
        (loop (cdr fs) (+ i 1)
              (cons (cons (string-append rel "#" (number->string i)) (car fs)) acc)))))

(define message-fixtures
  (apply append (map fixtures-in (append (corpus-files "request")
                                         (corpus-files "response")))))

;; The url sub-parser's fixtures: spans only, so they bear on the span half.
(define url-fixtures (fixtures-in "url.md"))

;; --- the oracle's side ------------------------------------------------------

;; split-off : String -> (Option (Pair Nat String))
;; A log line `off=N text` as `(N . text)`; #f for `off=NULL ...`, which has
;; no position.
(define (split-off line)
  (and (string-prefix? "off=" line)
       (let loop ((i 4))
         (cond ((= i (string-length line)) #f)
               ((char=? (string-ref line i) #\space)
                (let ((n (string->number (substring line 4 i))))
                  (and n (cons n (substring line (+ i 1) (string-length line))))))
               (else (loop (+ i 1)))))))

;; event-text? : String -> Boolean
;; Whether a logged line is one an EVENT callback printed. Left out: a span
;; line, whose text opens `len=`; the two lines upstream's DRIVER prints
;; rather than a callback, `pause` and `error ...`; and `skip body`, which the
;; headers-complete callback prints after its own event line.
(define (event-text? text)
  (not (or (string-prefix? "len=" text)
           (string=? text "pause")
           (string=? text "skip body")
           (string-prefix? "error " text))))

;; logged-events : Fixture -> (Listof (Pair Nat String))
;; `(off . text)` for every event line in the fixture's log, in order.
(define (logged-events f)
  (fold-right (lambda (e acc)
                (let ((line (and (not (expectation-pattern? e))
                                 (split-off (expectation-text e)))))
                  (if (and line (event-text? (cdr line))) (cons line acc) acc)))
              '()
              (fixture-expected f)))

;; names-event? : String String -> Boolean
;; Whether a logged line's text is the event llhttp calls `name`: the name
;; alone, or followed by the fields a state or count line prints after it.
(define (names-event? text name)
  (or (string=? text name) (string-prefix? (string-append name " ") text)))

;; llhttp-name : Symbol -> String
;; What llhttp's log calls a callback, from the adapter's own table.
(define (llhttp-name callback)
  (caddr (assq callback adapter-trace-names)))

;; --- the parser's side ------------------------------------------------------

;; Where a chunk sits in the buffer it is fed from. Not 0, so `from` and `to`
;; are never stream positions; filler either side, so a fragment that strayed
;; outside the chunk would carry bytes the input does not have.
(define pad 3)
(define filler (char->integer #\~))

;; chunk-buffer : Bytevector Nat Nat -> Bytevector
;; Bytes `[s,e)` of `bv`, copied into a buffer of their own at index `pad`.
(define (chunk-buffer bv s e)
  (let ((b (make-bytevector (+ pad (- e s) pad) filler)))
    (bytevector-copy! bv s b pad (- e s))
    b))

(define (bytes-of bv s e)
  (let ((b (make-bytevector (- e s))))
    (bytevector-copy! bv s b 0 (- e s))
    b))

;; What the sweep exercised, across every run, printed beside the checks. All
;; but the first are floors below: a sweep that never met the shape a claim is
;; about has not checked the claim.
(define fragments 0)      ; span fragments checked
(define empties 0)        ; of which `from` = `to`
(define flushed 0)        ; of which begun mid-feed and cut off where a feed ended, input left
(define carried 0)        ; of which begun at the start of a feed after the first
(define compared 0)       ; events held against a log line, matching or not
(define later-message 0)  ; events after an `on-reset`: a second message on one parser

;; `(fed offset reported)` for every feed that took its whole chunk and after
;; which the offset was not the bytes fed so far.
(define between '())

;; make-probe : Fixture -> (Values Parser (Bytevector Nat -> Void) (-> ParserResult) (-> (Values (Listof (Pair Symbol Nat)) (Listof String))))
;; A parser for the fixture's machine and init with every callback bound to a
;; recorder; a procedure that feeds it an input, `size` bytes at a time, each
;; chunk from a buffer of its own; one that finishes it; and one that hands
;; back, and forgets, what the callbacks saw -- every event as
;; `(callback . offset)` in order, and a description of every fragment whose
;; offset was not where its end is.
;;
;; THE FEEDING STARTS A STREAM. The driver counts a chunk's position from the
;; first byte of the input it is handed, which is right for a parser just made
;; or just reset and for nothing else.
;;
;; A message fixture gets its kind and lenient flags from its `type` meta, as
;; the conformance driver does, and its `skipBody` meta makes
;; `on-headers-complete` answer `skip-body`. Its `pause` meta is ignored: a
;; resumed parse re-enters where an unpaused one would have gone, so the only
;; difference is the `pause` line upstream's driver prints, which is left out
;; of the log above.
(define (make-probe f)
  (let ((chunk-at 0) (chunk-len 0) (input-len 0) (events '()) (wrong '())
        (after-reset #f) (finishing #f))
    (define (event callback answer)
      (lambda (p ctx)
        (let ((at (parser-stream-offset p)))
          (set! events (cons (cons callback at) events))
          (when after-reset (set! later-message (+ later-message 1)))
          (when (eq? callback 'on-reset) (set! after-reset #t)))
        answer))
    (define (note-wrong! callback at end)
      (set! wrong (cons (string-append (symbol->string callback)
                                       " read " (number->string at)
                                       ", its end is " (number->string end))
                        wrong)))
    (define (span callback)
      (lambda (p ctx buf from to)
        (let ((at (parser-stream-offset p)))
          (if finishing
              ;; A finish has no chunk: every byte is already taken, so a
              ;; fragment's end is all of them, and there is no input left to
              ;; read its bytes against.
              (unless (= at input-len) (note-wrong! callback at input-len))
              (let ((end (+ chunk-at (- to pad)))
                    (start (- at (- to from))))
                (set! fragments (+ fragments 1))
                (when (= from to) (set! empties (+ empties 1)))
                (when (and (> from pad) (= to (+ pad chunk-len))
                           (< (+ chunk-at chunk-len) input-len))
                  (set! flushed (+ flushed 1)))
                (when (and (= from pad) (> chunk-at 0)) (set! carried (+ carried 1)))
                ;; The end first: only once it is right is `start` a position
                ;; worth reading the input at.
                (unless (and (= at end)
                             (<= pad from) (<= from to) (<= to (+ pad chunk-len))
                             (bytevector=? (bytes-of buf from to)
                                           (bytes-of input start at)))
                  (note-wrong! callback at end)))))
        callback-continue))
    (define input #vu8())
    (define skip? (eq? #t (fixture-meta-ref f 'skipBody #f)))
    (define parser
      (if (eq? (fixture-kind f) 'url)
          (make-parser httparse-url-machine
                       (map (lambda (row) (list (car row) (span (car row))))
                            adapter-url-trace-names)
                       #f)
          (make-parser httparse-message-machine
                       (map (lambda (row)
                              (let ((callback (car row)))
                                (list callback
                                      (if (eq? (cadr row) 'span)
                                          (span callback)
                                          (event callback
                                                 (if (and skip? (eq? callback 'on-headers-complete))
                                                     'skip-body
                                                     callback-continue))))))
                            adapter-trace-names)
                       #f
                       (adapter-parser-inits
                        (cons (car (fixture-init-words f)) (fixture-lenient-flags f))))))
    ;; feed! : Bytevector Nat -> Void
    ;; Until the input is taken or the parse stops.
    (define (feed! bv size)
      (set! input bv)
      (set! input-len (bytevector-length bv))
      (set! after-reset #f)
      (let loop ((at 0))
        (when (< at input-len)
          (let ((e (min input-len (+ at size))))
            (set! chunk-at at)
            (set! chunk-len (- e at))
            (let ((r (parser-feed! parser (chunk-buffer bv at e) pad (+ pad (- e at)))))
              (when (eq? (parser-result-status r) 'need-input)
                ;; The whole chunk was taken, so the count is every byte fed.
                (unless (= e (parser-stream-offset parser) (parser-result-stream-offset r))
                  (set! between (cons (list e (parser-stream-offset parser)
                                            (parser-result-stream-offset r))
                                      between)))
                (loop e)))))))
    ;; finish! : -> ParserResult
    (define (finish!)
      (set! finishing #t)
      (let ((r (parser-finish! parser)))
        (set! finishing #f)
        r))
    ;; take! : -> (Values (Listof (Pair Symbol Nat)) (Listof String))
    (define (take!)
      (let ((es (reverse events)) (ws (reverse wrong)))
        (set! events '())
        (set! wrong '())
        (values es ws)))
    (values parser feed! finish! take!)))

;; event-mismatch : Fixture (Listof (Pair Symbol Nat)) -> (Option String)
;; #f when the events are the log's, offset for offset; else the first that
;; is not.
(define (event-mismatch f observed)
  (let loop ((os observed) (ls (logged-events f)) (i 0))
    (cond
     ((and (null? os) (null? ls)) #f)
     ((null? os)
      (string-append "the log has " (number->string (length ls)) " more, from off="
                     (number->string (caar ls)) " " (cdar ls)))
     ((null? ls)
      (string-append "the parser reported " (number->string (length os))
                     " more, from " (symbol->string (caar os))))
     (else
      (set! compared (+ compared 1))
      (if (and (= (cdar os) (caar ls))
               (names-event? (cdar ls) (llhttp-name (caar os))))
          (loop (cdr os) (cdr ls) (+ i 1))
          (string-append "event " (number->string i) ": the log has off="
                         (number->string (caar ls)) " " (cdar ls) ", "
                         (symbol->string (caar os)) " read "
                         (number->string (cdar os))))))))

;; sizes : Nat -> (Listof Nat)
;; Size 1 puts a feed boundary inside every span and the whole buffer puts
;; none but the end, as in the conformance lane's selection. The sizes between
;; are what deliver a fragment that began mid-feed and was cut off where the
;; feed ended.
(define (sizes n)
  (append (filter (lambda (s) (< s n)) '(1 2 3 7))
          (list (max n 1))))

;; sweep : (Listof (Pair String Fixture)) -> (Values (Listof String) (Listof String))
;; Every fixture at every size, each on a parser of its own. Answers the
;; fragments whose offset was not their end, and the runs whose events were
;; not the log's, each labelled with the fixture and the size.
(define (sweep entries)
  (let loop ((es entries) (spans '()) (logs '()))
    (if (null? es)
        (values (reverse spans) (reverse logs))
        (let* ((id (caar es)) (f (cdar es))
               (bv (corpus-decode-input (fixture-input-text f))))
          (let size-loop ((ss (sizes (bytevector-length bv))) (spans spans) (logs logs))
            (if (null? ss)
                (loop (cdr es) spans logs)
                (let-values (((p feed! finish! take!) (make-probe f)))
                  (feed! bv (car ss))
                  (let-values (((observed wrong) (take!)))
                    (let ((label (string-append id " at " (number->string (car ss)))))
                      (size-loop
                       (cdr ss)
                       (append (map (lambda (w) (string-append label ": " w)) (reverse wrong))
                               spans)
                       (let ((m (and (not (eq? (fixture-kind f) 'url))
                                     (event-mismatch f observed))))
                         (if m (cons (string-append label ": " m) logs) logs))))))))))))

(define swept #f)

;; swept! : -> (List (Listof String) (Listof String) (Listof String))
;; The two sweeps, run once and inside whichever case asks first -- a raise is
;; then that case's failure rather than the lane's death -- with the tally
;; printed beside them. Answers the message fragments not ending at their
;; offset, the message runs whose events are not the log's, and the url
;; fragments not ending at their offset.
(define (swept!)
  (unless swept
    (let-values (((message-spans message-events) (sweep message-fixtures)))
      (let-values (((url-spans url-events) (sweep url-fixtures)))
        (display (string-append
                  "httparse-harness: stream-offset fixtures="
                  (number->string (length message-fixtures)) "+"
                  (number->string (length url-fixtures)) " url"
                  " events=" (number->string compared)
                  " after-reset=" (number->string later-message)
                  " fragments=" (number->string fragments)
                  " empty=" (number->string empties)
                  " flushed=" (number->string flushed)
                  " carried=" (number->string carried) "\n"))
        (set! swept (list message-spans message-events url-spans)))))
  swept)

(harness-begin "unit.stream-offset")

(harness-group "inside an event callback, the offset is llhttp's off="
  (lambda ()
    (harness-case "every event in the corpus, at every size"
      (lambda ()
        (check-equal "runs whose events are not the log's" (cadr (swept!)) '())
        ;; A log with no event lines would agree with a parser that reported
        ;; nothing.
        (check "some event offsets were compared" (> compared 0))))))

(harness-group "inside a span callback, the offset is the fragment's end"
  (lambda ()
    (harness-case "every fragment in the corpus, at every size"
      (lambda ()
        (check-equal "message fragments not ending at the offset" (car (swept!)) '())
        (check-equal "url fragments not ending at the offset" (caddr (swept!)) '())))

    ;; Each shape a fragment can take is one the claim covers, and one a
    ;; sweep could miss: a fragment cut off where its feed ended (the doc
    ;; names it), one carried over from an earlier feed, and an empty one,
    ;; where `(- to from)` is 0 and the offset is the start as well as the
    ;; end.
    (harness-case "the sweep met every shape of fragment"
      (lambda ()
        (swept!)
        (check "a fragment cut off where its feed ended" (> flushed 0))
        (check "a fragment carried over from an earlier feed" (> carried 0))
        (check "an empty fragment" (> empties 0))))))

;;; Both kinds of callback read one count, so what it counts from is one
;;; question for both.
(harness-group "the count starts when the parser does"
  (lambda ()
    ;; Not when the message does. The pipelining fixtures log a second
    ;; message on one parser where it sits in the stream, and the event sweep
    ;; above holds those numbers like any other; this says it met some.
    (harness-case "the sweep held a second message on one parser to its log"
      (lambda ()
        (swept!)
        (check "some event came after an on-reset" (> later-message 0))))

    ;; `parser-reset!` is the one thing that starts the count again, so the
    ;; same input on a reset parser must log the same numbers twice.
    (harness-case "after parser-reset!, the same input reads its log's offsets again"
      (lambda ()
        (let ((f (cdr (assoc "request/sample.md#1" message-fixtures))))
          (let-values (((p feed! finish! take!) (make-probe f)))
            (let ((bv (corpus-decode-input (fixture-input-text f))))
              (feed! bv (bytevector-length bv))
              (let-values (((events wrong) (take!)))
                (check-equal "events, first parse" (event-mismatch f events) #f)
                (check-equal "fragments, first parse" wrong '()))
              (parser-reset! p)
              (feed! bv (bytevector-length bv))
              (let-values (((events wrong) (take!)))
                (check-equal "events, after the reset" (event-mismatch f events) #f)
                (check-equal "fragments, after the reset" wrong '())))))))

    ;; What a callback reads is the count a result reports, read live: after
    ;; a feed that took its whole chunk, both are every byte fed so far.
    (harness-case "between feeds, it is the bytes taken, as the result says"
      (lambda ()
        (swept!)
        (check-equal "feeds where the two disagree with the bytes fed" between '())))

    ;; The corpus never finishes, so this is the one place a callback runs
    ;; with no feed under it. `response/finish.md#1` logs `finish=1`: the
    ;; message is complete once the input is said to have ended, and
    ;; `on-message-complete` runs at the finish. By then every byte is taken.
    (harness-case "a callback parser-finish! runs reads the whole input"
      (lambda ()
        (let ((f (cdr (assoc "response/finish.md#1" message-fixtures))))
          (let-values (((p feed! finish! take!) (make-probe f)))
            (let ((bv (corpus-decode-input (fixture-input-text f))))
              (feed! bv (bytevector-length bv))
              (let-values (((events wrong) (take!)))
                (check-equal "events, fed" (event-mismatch f events) #f))
              (check-equal "the finish" (parser-result-status (finish!)) 'finished)
              (let-values (((events wrong) (take!)))
                (check-equal "events at the finish"
                             (map cdr events)
                             (map (lambda (e) (bytevector-length bv)) events))
                (check "some event ran at the finish" (pair? events))
                (check-equal "fragments at the finish" wrong '())))))))))

(harness-finish)

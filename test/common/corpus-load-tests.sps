;;; Tests for (httparse test corpus-load): reading corpus files into fixtures.
;;;
;;; Two halves. The first judges the parser on hand-built markdown, so a
;;; failure names the rule that broke. The second runs it over the real
;;; vendored corpus and asserts counts and total decodability, measured rather
;;; than asserted in prose.
(import (rnrs)
        (httparse test harness)
        (httparse test corpus-load)
        (httparse test corpus-decode))

(define (read-text path)
  (utf8->string
   (call-with-port (open-file-input-port path) get-bytevector-all)))

(define corpus-dir (adapter-environment-variable "HTTPARSE_CORPUS_DIR"))

(harness-begin "unit.corpus-load")

(harness-group "splitting lines"
  (lambda ()
    (harness-case "a trailing newline yields a final empty line"
      (lambda ()
        (check-equal "a\\n" (corpus-split-lines "a\n") '("a" ""))))
    (harness-case "no trailing newline yields no empty tail"
      (lambda ()
        (check-equal "a" (corpus-split-lines "a") '("a"))))
    (harness-case "the empty string is one empty line"
      (lambda ()
        (check-equal "empty" (corpus-split-lines "") '(""))))
    (harness-case "consecutive newlines yield empty lines between them"
      (lambda ()
        (check-equal "a\\n\\nb" (corpus-split-lines "a\n\nb") '("a" "" "b"))))))

(harness-group "the meta object"
  (lambda ()
    (harness-case "a string value"
      (lambda ()
        (check-equal "type" (corpus-parse-meta "{\"type\": \"request\"}")
                     '((type . "request")))))
    (harness-case "a boolean value"
      (lambda ()
        (check-equal "noScan" (corpus-parse-meta "{\"noScan\": true}")
                     '((noScan . #t)))))
    (harness-case "false is read as false, not as absent"
      (lambda ()
        ;; #f and 'missing must stay distinguishable, or a lane could read a
        ;; disabled option as an unset one.
        (check-equal "false" (corpus-parse-meta "{\"skip\": false}")
                     '((skip . #f)))))
    (harness-case "several pairs keep their order"
      (lambda ()
        (check-equal "two" (corpus-parse-meta "{\"type\": \"request\", \"noScan\": true}")
                     '((type . "request") (noScan . #t)))))
    (harness-case "an empty object is an empty alist"
      (lambda ()
        (check-equal "{}" (corpus-parse-meta "{}") '())))
    (harness-case "a numeric value is refused, not approximated"
      (lambda ()
        (check-raises "number" corpus-load-error?
          (lambda () (corpus-parse-meta "{\"n\": 1}")))))
    (harness-case "a nested object is refused"
      (lambda ()
        (check-raises "nested" corpus-load-error?
          (lambda () (corpus-parse-meta "{\"a\": {\"b\": true}}")))))
    (harness-case "text that is not an object is refused"
      (lambda ()
        (check-raises "not an object" corpus-load-error?
          (lambda () (corpus-parse-meta "\"request\"")))))))

(define simple-file
  (string-append
   "## A request\n"
   "\n"
   "<!-- meta={\"type\": \"request\"} -->\n"
   "```http\n"
   "GET / HTTP/1.1\n"
   "\n"
   "\n"
   "```\n"
   "\n"
   "```log\n"
   "off=0 message begin\n"
   "off=0 len=3 span[method]=\"GET\"\n"
   "```\n"))

(harness-group "parsing a file"
  (lambda ()
    (harness-case "one fixture is found"
      (lambda ()
        (check-equal "count" (length (corpus-parse-file simple-file)) 1)))
    (harness-case "the meta is attached"
      (lambda ()
        (let ((f (car (corpus-parse-file simple-file))))
          (check-equal "type" (fixture-meta-ref f 'type 'missing) "request"))))
    (harness-case "an absent meta key returns the caller's default"
      (lambda ()
        (let ((f (car (corpus-parse-file simple-file))))
          (check-equal "noScan" (fixture-meta-ref f 'noScan 'missing) 'missing))))
    (harness-case "the kind is http"
      (lambda ()
        (check-equal "kind" (fixture-kind (car (corpus-parse-file simple-file))) 'http)))
    (harness-case "the input block keeps its blank lines and trailing newline"
      (lambda ()
        (check-equal "input" (fixture-input-text (car (corpus-parse-file simple-file)))
                     "GET / HTTP/1.1\n\n\n")))
    (harness-case "the input decodes to CRLF-framed bytes"
      (lambda ()
        ;; The loader and decoder meeting: the reason the input block keeps its
        ;; trailing newline is that the decoder's first pass removes exactly one.
        (check-equal "decoded"
                     (corpus-decode-input (fixture-input-text (car (corpus-parse-file simple-file))))
                     (u8-list->bytevector
                      '(#x47 #x45 #x54 #x20 #x2F #x20 #x48 #x54 #x54 #x50 #x2F #x31 #x2E #x31
                        #x0D #x0A #x0D #x0A)))))
    (harness-case "both expectation lines are kept, without a trailing empty one"
      (lambda ()
        (check-equal "expected" (length (fixture-expected (car (corpus-parse-file simple-file)))) 2)))
    (harness-case "an expectation is literal text"
      (lambda ()
        (let ((e (car (fixture-expected (car (corpus-parse-file simple-file))))))
          (check-equal "pattern?" (expectation-pattern? e) #f)
          (check-equal "text" (expectation-text e) "off=0 message begin"))))
    (harness-case "the heading is kept for diagnostics"
      (lambda ()
        (check-equal "title" (fixture-title (car (corpus-parse-file simple-file))) "## A request")))))

(harness-group "association is by order, not adjacency"
  (lambda ()
    (harness-case "prose between the input and log blocks does not lose the fixture"
      (lambda ()
        ;; Five fixtures in the vendored corpus look like this. Pairing on
        ;; adjacency drops every one of them.
        (let ((text (string-append
                     "<!-- meta={\"type\": \"request\"} -->\n"
                     "```http\n" "GET /\n" "\n" "\n" "```\n"
                     "\n"
                     "_Note the trailing CRLF above_\n"
                     "\n"
                     "```log\n" "off=0 message begin\n" "```\n")))
          (check-equal "count" (length (corpus-parse-file text)) 1))))
    (harness-case "two input blocks before a log block are refused"
      (lambda ()
        (check-raises "two inputs" corpus-load-error?
          (lambda ()
            (corpus-parse-file
             (string-append "```http\n" "A\n" "```\n" "```http\n" "B\n" "```\n"
                            "```log\n" "x\n" "```\n"))))))
    (harness-case "a log block with no input before it is refused"
      (lambda ()
        (check-raises "orphan log" corpus-load-error?
          (lambda () (corpus-parse-file (string-append "```log\n" "x\n" "```\n"))))))
    (harness-case "an input block with no log block is refused"
      (lambda ()
        (check-raises "orphan input" corpus-load-error?
          (lambda () (corpus-parse-file (string-append "```http\n" "A\n" "```\n"))))))
    (harness-case "an unterminated fence is refused"
      (lambda ()
        (check-raises "unterminated" corpus-load-error?
          (lambda () (corpus-parse-file (string-append "```http\n" "A\n"))))))))

(harness-group "expectations"
  (lambda ()
    (harness-case "a backslash-t in an expected line becomes a tab"
      (lambda ()
        (let* ((text (string-append "```http\n" "A\n" "```\n"
                                    "```log\n" "a\\tb\n" "```\n"))
               (e (car (fixture-expected (car (corpus-parse-file text))))))
          (check-equal "tab" (expectation-text e) "a\tb"))))
    (harness-case "a slash-delimited line is a pattern, not literal text"
      (lambda ()
        (let* ((text (string-append "```url\n" "/x\n" "```\n"
                                    "```log\n" "/off=\\d+ ok/\n" "```\n"))
               (e (car (fixture-expected (car (corpus-parse-file text))))))
          (check-equal "pattern?" (expectation-pattern? e) #t)
          (check-equal "text" (expectation-text e) "off=\\d+ ok"))))
    (harness-case "an ordinary line is not treated as a pattern"
      (lambda ()
        (let* ((text (string-append "```http\n" "A\n" "```\n"
                                    "```log\n" "off=0 message begin\n" "```\n"))
               (e (car (fixture-expected (car (corpus-parse-file text))))))
          (check-equal "pattern?" (expectation-pattern? e) #f))))))

;; --- the real vendored corpus ----------------------------------------------

(define corpus-files
  '("request/connection.md" "request/content-length.md" "request/finish.md"
    "request/invalid.md" "request/lenient-header-value-relaxed.md"
    "request/lenient-headers.md" "request/lenient-version.md" "request/method.md"
    "request/pausing.md" "request/pipelining.md" "request/sample.md"
    "request/transfer-encoding.md" "request/uri.md"
    "response/connection.md" "response/content-length.md" "response/finish.md"
    "response/invalid.md" "response/lenient-version.md" "response/pausing.md"
    "response/pipelining.md" "response/sample.md" "response/transfer-encoding.md"
    "url.md"))

(define (load-all)
  (apply append
         (map (lambda (rel)
                (corpus-parse-file (read-text (string-append corpus-dir "/" rel))))
              corpus-files)))

;; Every reason llhttp's chunk-extension states can emit, in the order
;; `src/llhttp/http.ts` writes them.
(define chunk-extension-reasons
  '("Invalid character in chunk extensions"
    "Invalid character in chunk extensions name"
    "Missing expected CR after chunk extension name"
    "Invalid character in chunk extensions value"
    "Missing expected CR after chunk extension value"
    "Invalid character in chunk extensions quoted value"
    "Invalid quoted-pair in chunk extensions quoted value"
    "Invalid character in chunk extensions quote value"))

;; Does any expectation line in the corpus carry this reason? Matched as a
;; SUBSTRING of the whole line, because a reason arrives inside
;; `off=N error code=C reason="..."`.
(define (corpus-records-reason? reason)
  (let ((lines (map expectation-text
                    (apply append (map fixture-expected (load-all))))))
    (exists (lambda (line) (substring-of? reason line)) lines)))

(define (substring-of? needle hay)
  (let ((n (string-length needle)) (h (string-length hay)))
    (let loop ((i 0))
      (cond ((> (+ i n) h) #f)
            ((string=? needle (substring hay i (+ i n))) #t)
            (else (loop (+ i 1)))))))

;; llhttp's FLAGS, the two that mean "this message says how long its body is".
;; Both are read off the `headers complete` line, which prints them as `%x`.
(define framing-flags (+ 8 32))     ; CHUNKED | CONTENT_LENGTH

;; The prefix a `headers complete` line carries for one status code, and the
;; flags that follow it. Returns #f when the line is not one.
(define (headers-complete-flags line code)
  (let ((head (string-append "headers complete status=" (number->string code) " v=")))
    (and (substring-of? head line)
         (let* ((i (+ (index-of head line) (string-length head)))
                (j (index-of " flags=" (substring line i (string-length line)))))
           (and j
                (let ((k (+ i j (string-length " flags="))))
                  (hex-prefix line k)))))))

(define (index-of needle hay)
  (let ((n (string-length needle)) (h (string-length hay)))
    (let loop ((i 0))
      (cond ((> (+ i n) h) #f)
            ((string=? needle (substring hay i (+ i n))) i)
            (else (loop (+ i 1)))))))

(define (hex-prefix line k)
  (let loop ((i k) (acc 0) (any #f))
    (if (>= i (string-length line))
        (and any acc)
        (let ((d (hex-digit (string-ref line i))))
          (if d (loop (+ i 1) (+ (* acc 16) d) #t) (and any acc))))))

(define (hex-digit c)
  (cond ((and (char<=? #\0 c) (char<=? c #\9)) (- (char->integer c) 48))
        ((and (char<=? #\a c) (char<=? c #\f)) (- (char->integer c) 87))
        (else #f)))

(define (corpus-frames-status? code)
  (let ((lines (map expectation-text
                    (apply append (map fixture-expected (load-all))))))
    (exists (lambda (line)
              (let ((f (headers-complete-flags line code)))
                (and f (not (= 0 (bitwise-and f framing-flags))))))
            lines)))

(harness-group "the vendored corpus"
  (lambda ()
    (harness-case "the corpus directory was provided to the lane"
      (lambda ()
        (check "HTTPARSE_CORPUS_DIR is set" (and corpus-dir (not (string=? corpus-dir ""))))))
    (harness-case "every vendored file parses and the fixture count is 274"
      (lambda ()
        (check-equal "total" (length (load-all)) 274)))
    (harness-case "253 are http fixtures"
      (lambda ()
        (check-equal "http"
                     (length (filter (lambda (f) (eq? (fixture-kind f) 'http)) (load-all)))
                     253)))
    (harness-case "21 are url fixtures"
      (lambda ()
        (check-equal "url"
                     (length (filter (lambda (f) (eq? (fixture-kind f) 'url)) (load-all)))
                     21)))
    (harness-case "every http fixture declares a type"
      (lambda ()
        (check-equal "typeless http fixtures"
                     (length (filter (lambda (f)
                                       (and (eq? (fixture-kind f) 'http)
                                            (eq? (fixture-meta-ref f 'type 'missing) 'missing)))
                                     (load-all)))
                     0)))
    (harness-case "every fixture carries at least one expectation"
      (lambda ()
        (check-equal "expectation-less fixtures"
                     (length (filter (lambda (f) (null? (fixture-expected f))) (load-all)))
                     0)))
    (harness-case "every fixture's input decodes to bytes"
      (lambda ()
        ;; All 274 load AND decode.
        (check-equal "undecodable fixtures"
                     (length (filter (lambda (f)
                                       (guard (e (#t #t))
                                         (corpus-decode-input (fixture-input-text f))
                                         #f))
                                     (load-all)))
                     0)))
    (harness-case "no expectation in the corpus is a pattern"
      (lambda ()
        ;; Upstream's driver treats a /slash-delimited/ expectation as a regular
        ;; expression, and the loader reads one as a pattern -- but the vendored
        ;; corpus contains none. (The two /.../ lines in url.md are URL *inputs*,
        ;; `/foo\tbar/` and `/foo\fbar/`, not expectations; a grep that ignores
        ;; block structure miscounts them.)
        ;; So the comparator may compare literal text only. If a refresh ever
        ;; introduces a real pattern this goes red, which is the notice that the
        ;; comparator needs teaching rather than a fixture silently mismatching.
        (check-equal "patterns"
                     (length (filter expectation-pattern?
                                     (apply append (map fixture-expected (load-all)))))
                     0)))
    (harness-case "only two of llhttp's eight chunk-extension reasons are recorded"
      (lambda ()
        ;; WHICH ARMS THE ORACLE CAN JUDGE. llhttp's chunk-extension states can
        ;; emit eight distinct reasons; the vendored corpus records two. The six
        ;; below are translated from `src/llhttp/http.ts` and no fixture can
        ;; confirm their offsets, so a mutation to one of their arms can survive
        ;; in EVERY lane -- a gap in the corpus rather than in the grammar.
        ;;
        ;; This is the notice that the situation changed: a refresh that adds a
        ;; fixture for any of the six turns this red, and the response is to
        ;; check the arm against the new trace, not to update the number.
        (check-equal "recorded"
                     (filter (lambda (reason) (corpus-records-reason? reason))
                             chunk-extension-reasons)
                     '("Invalid character in chunk extensions"
                       "Invalid character in chunk extensions quoted value"))))
    (harness-case "only one of the status line's two reasons is recorded"
      (lambda ()
        ;; THE SAME FINDING ONE PRODUCTION ALONG. llhttp's status line emits
        ;; two reasons under code 13: `Invalid status code` when one of the
        ;; three digits is not a digit, and `Invalid response status` when
        ;; what follows them is neither a space nor a line ending. No fixture
        ;; carries the second, so nothing in the corpus can judge the three
        ;; arms that produce it -- including the bare-LF one, which is the
        ;; `.match`-consumes trap, easiest to get wrong exactly where no
        ;; fixture looks.
        ;;
        ;; The grammar names the llparse idiom behind each of those arms and
        ;; where that idiom IS measured. This is the other half: a refresh
        ;; that adds a fixture for the second turns this red, and the right
        ;; response is to check the arms against the new trace rather than to
        ;; update the list.
        (check-equal "recorded"
                     (filter (lambda (reason) (corpus-records-reason? reason))
                             '("Invalid status code" "Invalid response status"))
                     '("Invalid status code"))))
    (harness-case "only one of the five no-body status codes is recorded with framing"
      (lambda ()
        ;; WHY A MUTATION HERE CAN SURVIVE EVERY LANE. llhttp asks two
        ;; overlapping questions about a response: the body decision names
        ;; 100, 102, 103, 204 and 304 exactly, and `message_needs_eof` names
        ;; 1xx, 204 and 304 again. On a message with NO framing header the two
        ;; agree, so either alone produces the right trace and a mutation to
        ;; one of them changes nothing. They part only when such a status
        ;; arrives WITH a `Content-Length` or a `Transfer-Encoding`, and the
        ;; corpus records that for 304 alone -- so a mutation to the 304 arm
        ;; is caught and the same mutation to the 204 arm is not.
        ;;
        ;; A fact about the fixtures, so it needs no parser and can be neither
        ;; a snapshot nor a change-detector. A refresh that brings a `204` or
        ;; a `103` with a body length turns this red, and the right response
        ;; is to check the arm against the new trace rather than to update the
        ;; list.
        (check-equal "framed"
                     (filter corpus-frames-status? '(100 102 103 204 304))
                     '(304))))))

(harness-finish)

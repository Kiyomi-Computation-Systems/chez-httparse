;;; (httparse test trace-format): render parser events as llhttp's trace text.
;;;
;;; Decision 0008 makes conformance bit-exact textual equality against the
;;; vendored expected blocks, so this is the instrument the parser is measured
;;; with. It may RENAME, never COMPUTE: everything it emits comes from the event
;;; it was handed. It is tested on hand-built events, before any parser exists,
;;; because an uncalibrated instrument cannot measure anything.
;;;
;;; TWO UPSTREAM BEHAVIOURS ARE REPRODUCED EXACTLY. Neither is obvious and both
;;; change which traces match.
;;;
;;; 1. SPANS ARE SPLIT AT CR AND LF (llparse__print_span). A span's bytes are
;;;    emitted as quoted runs, with each CR or LF on its own line as
;;;    `len=1 span[x]=cr` / `=lf`. An EMPTY span still prints one empty quoted
;;;    line -- the C loop's `len != 0 || (lf == NULL && cr == NULL)` guard.
;;;
;;; 2. CONTIGUOUS FRAGMENTS ARE COALESCED AND MOVED TO THE END (the driver's
;;;    normalizeSpans). When a quoted fragment for span X begins exactly where
;;;    the previous fragment for X ended, the two merge -- and the merged line
;;;    is REMOVED FROM ITS POSITION AND APPENDED. That reordering is observable
;;;    whenever other lines fall between the fragments, which is exactly what
;;;    happens when a body span is interrupted by a chunk boundary. The `=cr`
;;;    and `=lf` lines do not match the quoted shape and are never coalesced.
;;;
;;; WHY BYTES, NOT STRINGS. A span's content is raw input bytes. In this corpus
;;; the six fixtures carrying a non-ASCII byte are all marked noScan, so a
;;; fragment boundary never falls inside a multi-byte character -- but building
;;; the line as bytes makes that a non-question rather than a relied-upon
;;; property, and coalescing bytes is exact where concatenating decoded text
;;; would not be.
(library (httparse test trace-format)
  (export make-trace-span make-trace-mark make-trace-mark-at-null
          trace-format
          ;; exported so each half is judged alone
          trace-expand-span trace-normalize)
  (import (rnrs))

  ;; An event is one of:
  ;;   (span  name offset bytes)   a span fragment, `offset` absolute
  ;;   (mark  offset text)         `off=N text`
  ;;   (null-mark text)            `off=NULL text`
  (define-record-type trace-span (fields name offset bytes))
  (define-record-type trace-mark (fields offset text))
  (define-record-type trace-mark-at-null (fields text))

  ;; An item is what a line will be rendered from:
  ;;   (quoted name off len bytes)  -- coalescable
  ;;   (raw text)                   -- never coalesced
  (define-record-type quoted-item (fields name off (mutable len) (mutable bytes)))
  (define-record-type raw-item (fields text))

  (define (bytes-index bv start end byte)
    (let loop ((i start))
      (cond ((>= i end) #f)
            ((= (bytevector-u8-ref bv i) byte) i)
            (else (loop (+ i 1))))))

  ;; trace-expand-span : String Nat Bytevector -> (Listof Item)
  ;; Mirrors llparse__print_span.
  (define (trace-expand-span name offset bv)
    (let ((end (bytevector-length bv)))
      (let loop ((p 0) (acc '()))
        (let* ((cr0 (bytes-index bv p end #x0D))
               (lf0 (bytes-index bv p end #x0A))
               ;; when both are present only the earlier one is taken
               (cr (if (and cr0 lf0) (and (< cr0 lf0) cr0) cr0))
               (lf (if (and cr0 lf0) (and (not (< cr0 lf0)) lf0) lf0))
               (run (cond (lf (- lf p)) (cr (- cr p)) (else (- end p))))
               (acc (if (or (not (= run 0)) (and (not lf) (not cr)))
                        (cons (make-quoted-item name (+ offset p) run
                                                (bv-slice bv p (+ p run)))
                              acc)
                        acc))
               (p (+ p run)))
          (cond
           (lf (let ((acc (cons (make-raw-item
                                 (string-append "off=" (number->string (+ offset p))
                                                " len=1 span[" name "]=lf"))
                                acc))
                     (p (+ p 1)))
                 (if (= p end) (reverse acc) (loop p acc))))
           (cr (let ((acc (cons (make-raw-item
                                 (string-append "off=" (number->string (+ offset p))
                                                " len=1 span[" name "]=cr"))
                                acc))
                     (p (+ p 1)))
                 (if (= p end) (reverse acc) (loop p acc))))
           (else (if (= p end) (reverse acc) (loop p acc))))))))

  (define (bv-slice bv from to)
    (let ((out (make-bytevector (- to from))))
      (bytevector-copy! bv from out 0 (- to from))
      out))

  (define (bv-concat a b)
    (let ((out (make-bytevector (+ (bytevector-length a) (bytevector-length b)))))
      (bytevector-copy! a 0 out 0 (bytevector-length a))
      (bytevector-copy! b 0 out (bytevector-length a) (bytevector-length b))
      out))

  ;; trace-normalize : (Listof Item) -> (Listof Item)
  ;; Mirrors the driver's normalizeSpans, INCLUDING the move-to-end.
  (define (trace-normalize items)
    (let loop ((items items) (res '()) (last-of '()))
      ;; `res` is reversed; `last-of` maps span name -> the item standing for it
      (if (null? items)
          (reverse res)
          (let ((item (car items)))
            (if (raw-item? item)
                (loop (cdr items) (cons item res) last-of)
                (let ((prev (assoc (quoted-item-name item) last-of)))
                  (if (and prev
                           (= (+ (quoted-item-off (cdr prev)) (quoted-item-len (cdr prev)))
                              (quoted-item-off item)))
                      (let ((merged (cdr prev)))
                        (quoted-item-len-set! merged (+ (quoted-item-len merged)
                                                        (quoted-item-len item)))
                        (quoted-item-bytes-set! merged (bv-concat
                                                        (quoted-item-bytes merged)
                                                        (quoted-item-bytes item)))
                        ;; remove from its position, then append: `res` is
                        ;; reversed, so appending is consing at the head.
                        (loop (cdr items)
                              (cons merged (item-remove merged res))
                              last-of))
                      (loop (cdr items) (cons item res)
                            (cons (cons (quoted-item-name item) item)
                                  (del-assoc (quoted-item-name item) last-of))))))))))

  (define (item-remove x ls)
    (cond ((null? ls) '())
          ((eq? (car ls) x) (cdr ls))
          (else (cons (car ls) (item-remove x (cdr ls))))))

  (define (del-assoc key ls)
    (cond ((null? ls) '())
          ((string=? (caar ls) key) (cdr ls))
          (else (cons (car ls) (del-assoc key (cdr ls))))))

  (define (item->bytes item)
    (if (raw-item? item)
        (string->utf8 (raw-item-text item))
        (bv-concat
         (string->utf8 (string-append "off=" (number->string (quoted-item-off item))
                                      " len=" (number->string (quoted-item-len item))
                                      " span[" (quoted-item-name item) "]=\""))
         (bv-concat (quoted-item-bytes item) (string->utf8 "\"")))))

  ;; trace-format : (Listof Event) -> (Listof Bytevector)
  ;; One bytevector per trace line, in the order the comparison expects.
  (define (trace-format events)
    (map item->bytes
         (trace-normalize
          (apply append
                 (map (lambda (e)
                        (cond
                         ((trace-span? e)
                          (trace-expand-span (trace-span-name e) (trace-span-offset e)
                                             (trace-span-bytes e)))
                         ((trace-mark? e)
                          (list (make-raw-item
                                 (string-append "off=" (number->string (trace-mark-offset e))
                                                " " (trace-mark-text e)))))
                         ((trace-mark-at-null? e)
                          (list (make-raw-item
                                 (string-append "off=NULL " (trace-mark-at-null-text e)))))
                         (else (assertion-violation 'trace-format "not a trace event" e))))
                      events))))))

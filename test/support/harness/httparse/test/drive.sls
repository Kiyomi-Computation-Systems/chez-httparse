;;; (httparse test drive): run one input through one executor and render the
;;; trace, for the lanes whose inputs are generated rather than vendored.
;;;
;;; WHY THIS IS NOT THE CONFORMANCE DRIVER. That driver answers a question
;;; about a FIXTURE -- which chunk sizes to replay, whether the fixture asks
;;; for a finish line, how a refusal is reported against a recorded
;;; expectation. A generated input has none of those: there is no recorded
;;; trace, no `noScan`, and no `*-finish` type. What is left is the part both
;;; need, and it is small enough to state once here rather than have two
;;; copies drift.
;;;
;;; A REFUSAL IS RETURNED, NOT RAISED. The adapter refuses a callback or error
;;; code it has no row for, which is the right behaviour and is exactly what a
;;; generated input is most likely to provoke. A lane that let it escape would
;;; report a crash where the finding is "the parser produced something llhttp's
;;; vocabulary has no word for", so this catches it and hands back the detail
;;; as a value.
(library (httparse test drive)
  (export drive-trace drive-init drive-refusal? drive-refusal-detail
          drive-chunk-ladder drive-feed! drive-requested-pause? drive-result)
  (import (rnrs)
          (httparse test adapter)
          (httparse test trace-format)
          (httparse test conformance)
          (byte-machine runtime))

  (define-record-type drive-refusal (fields detail))

  ;; drive-chunk-ladder : Nat -> (Listof Nat)
  ;; The chunk sizes a generated input is replayed at. Every size for a short
  ;; input, a sparse ladder for a long one, and the whole buffer always -- it
  ;; is the size the others are compared against. Upstream replays every size
  ;; from 1 to the length; for generated input the run is unbounded, so the
  ;; ladder buys the sizes that matter (1 fragments every span) without making
  ;; the count quadratic in the input.
  (define (drive-chunk-ladder len)
    (let ((n (max len 1)))
      (if (<= n 24)
          (let loop ((i n) (acc '())) (if (< i 1) acc (loop (- i 1) (cons i acc))))
          (let keep ((ls '(1 2 3 5 8 13 21 34)) (acc '()))
            (cond ((null? ls) (reverse (cons n acc)))
                  ((< (car ls) n) (keep (cdr ls) (cons (car ls) acc)))
                  (else (reverse (cons n acc))))))))

  ;; drive-requested-pause? : ParserResult -> Boolean
  ;; A pause THIS HARNESS ASKED FOR, as against one the machine declared. The
  ;; discriminator is the reason slot and it is not a convention: a pause
  ;; reason is declared on a NODE, so the machine's own pause node carries one
  ;; and a callback answering `callback-pause` cannot. Upstream prints the two
  ;; differently -- a bare `off=N pause` for the first, an error line for the
  ;; second -- so telling them apart is what makes either renameable.
  (define (drive-requested-pause? res)
    (and (eq? (parser-result-status res) 'paused)
         (not (parser-error? (parser-result-pause res)))))

  ;; drive-feed! : Recorder Parser Bytevector Nat Nat -> ParserResult
  ;; Feed [from,to) and answer the outcome the caller must act on. A requested
  ;; pause is not one: it is recorded, resumed, and the rest of the SAME chunk
  ;; fed, because that is what upstream's driver does -- `off=N pause` appears
  ;; mid-trace and the parse runs on to the end. A pause carrying a reason is
  ;; the machine's own and is handed back untouched, as is every other outcome.
  ;;
  ;; THE LOOP TERMINATES BECAUSE A RESUME RE-ENTERS PAST THE CALLBACK. Each
  ;; pausing callback declares its pause continuation as the place an unpaused
  ;; run would have gone, so the same node cannot pause twice without input
  ;; between, and a chain of zero-width callbacks is finite -- the generator's
  ;; verifier refuses a zero-progress cycle outright. An empty remainder is fed
  ;; rather than special-cased: the runtime answers `need-input` for it, which
  ;; is the right answer and one this code does not have to invent.
  (define (drive-feed! r p bv from to)
    (let loop ((at from))
      (let ((res (parser-feed! p bv at to)))
        (if (drive-requested-pause? res)
            (begin
              (trace-recorder-note-requested-pause! r (parser-stream-offset p))
              (parser-resume! p)
              (loop (parser-result-next res)))
            res))))

  ;; drive-init : Symbol (Listof Symbol) -> Init
  ;; The adapter's vocabulary for "what the embedder writes before the first
  ;; byte": a kind and the lenient flags it is to set. Built here so a lane
  ;; never has to know the shape.
  (define (drive-init kind flags) (cons kind flags))

  ;; drive-parser : Machine Init Recorder -> Parser
  ;; THE KIND CHOOSES THE BINDING LIST, because the two machines declare
  ;; disjoint callbacks. A url parser bound with the message parser's rows
  ;; would be handed names its machine never declares; a message parser bound
  ;; with the url parser's rows would lose every event it has.
  ;;
  ;; IT ALSO CHOOSES WHETHER THERE ARE INITIALS AT ALL. `s->type` and
  ;; `s->lenient_flags` are the message parser's fields, and llhttp's url
  ;; binary is built with no `-D` and no init hook -- so a url parser is
  ;; constructed with three arguments, which is the same thing said in the
  ;; conformance driver for `url.md`'s fixtures. A url init carrying flags is
  ;; REFUSED rather than ignored: it would be compared against a binary that
  ;; has no way to honour them.
  (define (drive-parser machine init r)
    (if (eq? (car init) 'url)
        (begin
          (unless (null? (cdr init))
            (assertion-violation 'drive-parser
              "the url parser has no lenient flags to set" init))
          (make-parser machine (trace-recorder-url-bindings r) #f))
        (make-parser machine (trace-recorder-bindings r init #f) #f
                     (adapter-parser-inits init))))

  ;; drive-trace : Machine Init Bytevector Nat -> (Listof Bytevector) or Refusal
  ;; The trace `machine` produces for `bv` fed in `size`-byte chunks, under
  ;; `init` -- `(kind . lenient-flags)`, which the embedder supplies and a
  ;; generated input cannot imply. A zero-length input is one run of no
  ;; chunks, matching the scan schedule's rule that an empty input still
  ;; executes.
  (define (drive-trace machine init bv size)
    (call/cc
     (lambda (k)
       (with-exception-handler
        (lambda (e)
          (if (adapter-error? e)
              (k (make-drive-refusal (adapter-error-detail e)))
              (raise e)))
        (lambda ()
          (let-values (((r result) (drive-run machine init bv size)))
            (when (and result (eq? (parser-result-status result) 'error))
              (trace-recorder-note-error! r (parser-result-error result)))
            (when (and result (eq? (parser-result-status result) 'paused))
              (trace-recorder-note-paused! r (parser-result-pause result)))
            (trace-format (trace-recorder-events r))))))))

  ;; drive-result : Machine Init Bytevector Nat -> (Option ParserResult)
  ;; The outcome `drive-trace` renders, before it is rendered: the last result
  ;; of feeding `bv` in `size`-byte chunks under `init`. A lane asking about
  ;; something no trace line prints -- an error's node name, say -- reads it
  ;; here and gets the same feeding, pauses and all. #f for an empty input,
  ;; which runs no chunks.
  (define (drive-result machine init bv size)
    (let-values (((r result) (drive-run machine init bv size)))
      result))

  ;; drive-run : Machine Init Bytevector Nat -> (Values Recorder (Option ParserResult))
  ;; Feed `bv` in `size`-byte chunks until it is taken or the parse stops, and
  ;; answer the recorder with the last result. The one loop both of the above
  ;; share, so they cannot disagree about where a parse ended.
  (define (drive-run machine init bv size)
    (let* ((r (make-trace-recorder))
           (p (drive-parser machine init r)))
      (let loop ((bounds (corpus-chunk-bounds (bytevector-length bv) size))
                 (result #f))
        (if (null? bounds)
            (values r result)
            (let ((res (drive-feed! r p bv (caar bounds) (cdar bounds))))
              (if (eq? (parser-result-status res) 'need-input)
                  (loop (cdr bounds) res)
                  (values r res)))))))
)

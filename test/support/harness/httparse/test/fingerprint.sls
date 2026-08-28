;;; Content fingerprint for the text a lane runs.
;;;
;;; A run reports the digest of the sources it executed so that a stale
;;; artifact or a copied variant is detectable rather than merely unlikely. A
;;; matching fingerprint means the declared text is unchanged -- not that the
;;; run loaded exactly those files; the manifest is declared, not observed
;;; (decision 0004, unchanged by the include collapse).
;;;
;;; This is a change detector, not a cryptographic digest. It is a polynomial
;;; rolling hash modulo the Mersenne prime 2^61-1. Do not use it for anything
;;; security relevant.
;;;
;;; TWO CONSUMERS, ONE IMPLEMENTATION
;;;
;;; (httparse test harness) re-exports this library's surface, and
;;; fingerprint-manifest.ss imports it to compute build-time expectations.
;;; That is why this is a library of its own rather than text inlined into
;;; the harness: the expectation and the runner share one implementation
;;; through the module system, so they cannot drift apart (decision 0006).
;;;
;;; The arithmetic is deliberately not bitwise: the algorithm needs nothing
;;; beyond exact integers of unbounded range, which R6RS guarantees.
;;; Intermediate products exceed 64 bits, which is what makes exact bignums
;;; load-bearing rather than incidental.

(library (httparse test fingerprint)
  (export harness-fingerprint-bytevector
          harness-fingerprint-file
          harness-fingerprint-combine
          harness-fingerprint->string)
  (import (rnrs) (only (rnrs r5rs) modulo quotient remainder))
(define harness-fingerprint-modulus 2305843009213693951) ; 2^61 - 1
(define harness-fingerprint-multiplier 1000003)
(define harness-fingerprint-seed 14695981039346656)

;; Fold one byte at a time. The +1 keeps leading zero bytes significant: without
;; it a NUL contributes nothing and two files differing only by a run of leading
;; NULs fingerprint identically.
(define (harness-fingerprint-bytevector bv)
  (let ((n (bytevector-length bv)))
    (let loop ((i 0)
               (h (modulo harness-fingerprint-seed harness-fingerprint-modulus)))
      (if (= i n)
          h
          (loop (+ i 1)
                (modulo (+ (* h harness-fingerprint-multiplier)
                           (+ (bytevector-u8-ref bv i) 1))
                        harness-fingerprint-modulus))))))

;; Fingerprints a file's exact bytes. A binary port, so the value is a
;; fingerprint of bytes rather than of decoded characters -- and so an LF is
;; an LF on a platform whose text ports would translate it.
;; get-bytevector-all returns the EOF object for an empty file rather than a
;; zero-length bytevector, so an empty file fingerprints as the seed instead
;; of raising. This library reads files itself: the adapter-file-bytes
;; indirection existed for the retired dialect ceiling, and (rnrs io ports)
;; is all the reader ever needed.
(define (harness-fingerprint-read-bytes path)
  (let* ((port (open-file-input-port path))
         (bytes (get-bytevector-all port)))
    (close-port port)
    (if (eof-object? bytes) (make-bytevector 0) bytes)))

(define (harness-fingerprint-file path)
  (harness-fingerprint-bytevector (harness-fingerprint-read-bytes path)))

;; Combine per-file fingerprints in the order given. Order is significant, so a
;; reordered manifest is a different combined value: the result identifies a
;; sequence of sources, not a set of them.
(define (harness-fingerprint-combine fingerprints)
  (let loop ((rest fingerprints)
             (h (modulo harness-fingerprint-seed harness-fingerprint-modulus)))
    (if (null? rest)
        h
        (loop (cdr rest)
              (modulo (+ (* h harness-fingerprint-multiplier) (+ (car rest) 1))
                      harness-fingerprint-modulus)))))

;; Lowercase hex from an explicit digit table, never number->string with a
;; radix. Measured 2026-08-17: Chez yields "FF" for (number->string 255 16).
;; That is not wrong -- the standards do not fix the case -- so a radix
;; conversion would make the one claim this file exists to establish depend on
;; a detail an implementation is free to answer differently. Comparing
;; case-insensitively later would be worse: it would hide exactly the class of
;; divergence this file exists to expose.
(define harness-hex-digits "0123456789abcdef")

(define (harness-fingerprint->string h)
  (if (= h 0)
      "0"
      (let loop ((n h) (acc (list)))
        (if (= n 0)
            (list->string acc)
            (loop (quotient n 16)
                  (cons (string-ref harness-hex-digits (remainder n 16)) acc))))))
)

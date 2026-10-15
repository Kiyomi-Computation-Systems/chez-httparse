;;; The program check-akku.sh runs inside a consumer project, with only the
;;; library path Akku's activate script sets. It imports what an embedder
;;; imports, parses a request that arrives in two pieces, and prints what it
;;; read: `GET /index.html complete`.
(import (rnrs)
        (generated httparse-message)
        (httparse modes)
        (byte-machine runtime))

(define (text bv from to)
  (let ((b (make-bytevector (- to from))))
    (bytevector-copy! bv from b 0 (- to from))
    (utf8->string b)))

(define method "")
(define target "")
(define complete? #f)

(define (ignore-event p ctx) callback-continue)
(define (ignore-span p ctx bv from to) callback-continue)

;; Every callback the machine declares must be bound.
(define ignored-events
  '(on-reset on-message-begin on-method-complete on-url-complete
    on-protocol-complete on-version-complete on-status-complete
    on-header-field-complete on-header-value-complete on-headers-complete
    on-chunk-header on-chunk-extension-name-complete
    on-chunk-extension-value-complete on-chunk-complete))

(define ignored-spans
  '(on-protocol-data on-version-data on-status-data on-header-field-data
    on-header-value-data on-body-data on-chunk-extension-name-data
    on-chunk-extension-value-data))

(define parser
  (make-parser
   httparse-message-machine
   (append
    (list (list 'on-method-data
                (lambda (p ctx bv from to)
                  (set! method (string-append method (text bv from to)))
                  callback-continue))
          (list 'on-url-data
                (lambda (p ctx bv from to)
                  (set! target (string-append target (text bv from to)))
                  callback-continue))
          (list 'on-message-complete
                (lambda (p ctx) (set! complete? #t) callback-continue)))
    (map (lambda (name) (list name ignore-event)) ignored-events)
    (map (lambda (name) (list name ignore-span)) ignored-spans))
   #f
   (list (cons 'type (httparse-message-type-value 'request)))))

(for-each
 (lambda (piece)
   (let* ((bv (string->utf8 piece))
          (r (parser-feed! parser bv 0 (bytevector-length bv))))
     (unless (eq? (parser-result-status r) 'need-input)
       (error 'consumer "the parser stopped" (parser-result-status r)))))
 '("GET /index.ht" "ml HTTP/1.1\r\nHost: example.com\r\n\r\n"))

(display method)
(display " ")
(display target)
(display (if complete? " complete" " incomplete"))
(newline)

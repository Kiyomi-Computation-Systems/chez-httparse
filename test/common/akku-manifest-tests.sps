;;; docs.akku-manifest: Akku.manifest against the versions it must agree with.
;;;
;;; The manifest is what `akku publish` sends to the index, so two of its
;;; numbers have to match something else in the tree, and nothing else
;;; notices when they stop:
;;;
;;;   - the package version is the latest release in CHANGELOG.md, so the
;;;     release that adds a heading also moves the manifest;
;;;   - each dependency's range is a caret range whose floor is the version
;;;     vendored in vendor/<name>, the copy the test suite runs against. A
;;;     consumer can then resolve no version older than the one tested here.
;;;
;;; A manifest with no dependency is also refused: the generated parsers
;;; import the generator's runtime, so a package without it installs and
;;; then fails at first import.
;;;
;;; The synthetic cases pin each diagnostic, and a clean manifest must
;;; produce none. The last group reads the real files.
(import (rnrs)
        (httparse test harness))

;; --- the checker ------------------------------------------------------------

(define (read-text path)
  (utf8->string
   (call-with-port (open-file-input-port path) get-bytevector-all)))

;; String -> (Listof String)
(define (text-lines s)
  (let loop ((i 0) (start 0) (out '()))
    (cond ((= i (string-length s))
           (reverse (if (> i start) (cons (substring s start i) out) out)))
          ((char=? #\newline (string-ref s i))
           (loop (+ i 1) (+ i 1) (cons (substring s start i) out)))
          (else (loop (+ i 1) start out)))))

(define (prefix? p s)
  (and (<= (string-length p) (string-length s))
       (string=? p (substring s 0 (string-length p)))))

;; The version of the first released heading, `## [X.Y.Z] - date`, skipping
;; `## [Unreleased]`; #f when there is none.
;; String -> (U String #f)
(define (changelog-latest-release text)
  (let loop ((ls (text-lines text)))
    (cond ((null? ls) #f)
          ((and (prefix? "## [" (car ls))
                (> (string-length (car ls)) 4)
                (char-numeric? (string-ref (car ls) 4)))
           (let ((l (car ls)))
             (let scan ((j 4))
               (cond ((= j (string-length l)) #f)
                     ((char=? #\] (string-ref l j)) (substring l 4 j))
                     (else (scan (+ j 1)))))))
          (else (loop (cdr ls))))))

;; The `(akku-package ...)` form among a manifest's datums, or #f.
;; (Listof Datum) -> (U Datum #f)
(define (find-package datums)
  (cond ((null? datums) #f)
        ((and (pair? (car datums)) (eq? 'akku-package (caar datums)))
         (car datums))
        (else (find-package (cdr datums)))))

(define (read-datums text)
  (let ((p (open-string-input-port text)))
    (let loop ((out '()))
      (let ((d (read p)))
        (if (eof-object? d) (reverse out) (loop (cons d out)))))))

(define (package-version pkg) (cadr (cadr pkg)))

(define (package-depends pkg)
  (cond ((assq 'depends (cddr pkg)) => cdr)
        (else '())))

;; Every way the manifest disagrees with the tree, as tagged lists; '() when
;; it agrees. `vendored-version` maps a dependency name to the latest release
;; of vendor/<name>, or #f when nothing is vendored under that name.
;; (U Datum #f) (U String #f) (String -> (U String #f)) -> (Listof Diagnostic)
(define (manifest-diagnostics pkg changelog-version vendored-version)
  (if (not pkg)
      '((no-package))
      (let ((version (package-version pkg))
            (depends (package-depends pkg)))
        (append
         (if (equal? version changelog-version)
             '()
             (list (list 'version-mismatch version changelog-version)))
         (if (null? depends) '((no-dependencies)) '())
         (apply append
                (map (lambda (dep)
                       (let ((name (car dep))
                             (range (cadr dep)))
                         (cond ((not (prefix? "^" range))
                                (list (list 'range-not-caret name range)))
                               ((vendored-version name)
                                => (lambda (v)
                                     (let ((floor (substring range 1 (string-length range))))
                                       (if (string=? floor v)
                                           '()
                                           (list (list 'range-floor-mismatch name floor v))))))
                               (else (list (list 'dependency-not-vendored name))))))
                     depends))))))

;; --- the cases --------------------------------------------------------------

(define (pkg version . depends)
  `(akku-package ("chez-httparse" ,version)
     (synopsis "s")
     ,@(if (null? depends) '() (list (cons 'depends depends)))))

(define (vendored name)
  (and (string=? name "dep") "1.2.0"))

(define changelog
  (string-append "# Changelog\n\n## [Unreleased]\n\n- a change\n\n"
                 "## [0.4.5] - 2026-10-01\n\n## [0.4.4] - 2026-09-30\n"))

(harness-begin "docs.akku-manifest")

(harness-group "reading a changelog"
  (lambda ()
    (harness-case "the first released heading, past Unreleased"
      (lambda ()
        (check-equal "latest" (changelog-latest-release changelog) "0.4.5")))
    (harness-case "only Unreleased is no release"
      (lambda ()
        (check-equal "none"
                     (changelog-latest-release "## [Unreleased]\n\n- x\n")
                     #f)))))

(harness-group "each diagnostic, alone"
  (lambda ()
    (harness-case "a manifest that agrees produces none"
      (lambda ()
        (check-equal "clean"
                     (manifest-diagnostics (pkg "0.4.5" '("dep" "^1.2.0"))
                                           "0.4.5" vendored)
                     '())))
    (harness-case "no package form"
      (lambda ()
        (check-equal "no package"
                     (manifest-diagnostics (find-package '((import (x))))
                                           "0.4.5" vendored)
                     '((no-package)))))
    (harness-case "a version the changelog has not released"
      (lambda ()
        (check-equal "version"
                     (manifest-diagnostics (pkg "0.5.0" '("dep" "^1.2.0"))
                                           "0.4.5" vendored)
                     '((version-mismatch "0.5.0" "0.4.5")))))
    (harness-case "no dependency"
      (lambda ()
        (check-equal "no depends"
                     (manifest-diagnostics (pkg "0.4.5") "0.4.5" vendored)
                     '((no-dependencies)))))
    (harness-case "a range that is not a caret range"
      (lambda ()
        (check-equal "not caret"
                     (manifest-diagnostics (pkg "0.4.5" '("dep" "~1.2.0"))
                                           "0.4.5" vendored)
                     '((range-not-caret "dep" "~1.2.0")))))
    (harness-case "a floor below the vendored version"
      (lambda ()
        (check-equal "floor"
                     (manifest-diagnostics (pkg "0.4.5" '("dep" "^1.1.0"))
                                           "0.4.5" vendored)
                     '((range-floor-mismatch "dep" "1.1.0" "1.2.0")))))
    (harness-case "a dependency nothing vendors"
      (lambda ()
        (check-equal "not vendored"
                     (manifest-diagnostics (pkg "0.4.5" '("other" "^1.0.0"))
                                           "0.4.5" vendored)
                     '((dependency-not-vendored "other")))))))

(harness-group "the real manifest"
  (lambda ()
    (harness-case "Akku.manifest agrees with CHANGELOG.md and vendor/"
      (lambda ()
        (let* ((manifest (adapter-environment-variable "HTTPARSE_AKKU_MANIFEST"))
               (changelog (adapter-environment-variable "HTTPARSE_CHANGELOG"))
               (vendor (adapter-environment-variable "HTTPARSE_VENDOR_ROOT"))
               (pkg (find-package (read-datums (read-text manifest))))
               (vendored-version
                (lambda (name)
                  (let ((path (string-append vendor "/" name "/CHANGELOG.md")))
                    (and (file-exists? path)
                         (changelog-latest-release (read-text path)))))))
          (check-equal "diagnostics"
                       (manifest-diagnostics
                        pkg
                        (changelog-latest-release (read-text changelog))
                        vendored-version)
                       '())
          (when pkg
            (display (string-append
                      "httparse-akku-manifest: version " (package-version pkg)
                      ", dependencies checked against vendor/: "
                      (number->string (length (package-depends pkg))) "\n"))))))))

(harness-finish)

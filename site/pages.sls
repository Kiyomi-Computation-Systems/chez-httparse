#!r6rs
(library (site pages)
  (export pages)
  (import (rnrs))
  ;; The nav's single source of order and labels. test/site/site-check.sps
  ;; asserts the file set here equals docs/*.md (plus the home).
  (define pages
    '(("index.md"       . "Home")
      ("installing.md"  . "Installing")
      ("usage.md"       . "Usage")
      ("reference.md"   . "API reference")
      ("callbacks.md"   . "Callbacks")
      ("modes.md"       . "Modes")
      ("errors.md"      . "Errors")
      ("pausing.md"     . "Pausing and upgrades")
      ("connection.md"  . "Parser state")
      ("url.md"         . "The URL parser")
      ("conformance.md" . "Conformance")
      ("performance.md" . "Performance")
      ("building.md"    . "Building"))))

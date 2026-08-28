;;; A deterministic in-tree PRNG (parent §22.6): no host `random`, no global
;;; state, seed reproducible. 64-bit LCG (Knuth MMIX constants) masked to 63 bits;
;;; prng-next returns a value in [0,bound) and the next state, so callers thread
;;; state explicitly and a failing seed replays exactly.
(library (httparse test prng)
  (export make-prng prng-next)
  (import (rnrs))
  (define mask (- (expt 2 63) 1))
  (define (make-prng seed) (bitwise-and mask (+ seed 1)))
  (define (step s)
    (bitwise-and mask (+ (* s 6364136223846793005) 1442695040888963407)))
  ;; Return (values k s') with 0 <= k < bound, using the high bits of the next
  ;; state (low LCG bits are the least random).
  (define (prng-next s bound)
    (let ((s2 (step s)))
      (values (mod (bitwise-arithmetic-shift-right s2 17) bound) s2))))

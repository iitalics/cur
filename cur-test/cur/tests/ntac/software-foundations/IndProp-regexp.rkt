#lang cur
(require cur/stdlib/sugar
         cur/stdlib/equality
         ;cur/stdlib/prop
         cur/stdlib/nat
         cur/stdlib/list
         cur/ntac/base
         cur/ntac/standard
         cur/ntac/rewrite
         rackunit/turnstile
         "./IndProp-regexp-data.rkt"
         "../rackunit-ntac.rkt")

(check-type (m-app Nat
                   (build-list Nat 1)
                   (build-list Nat 2)
                   (char 1)
                   (char 2)
                   (m-char Nat 1)
                   (m-char Nat 2))
            : (ExpMatch Nat
                        (build-list Nat 1 2)
                        (app (char 1) (char 2))))

(check-type (m-star-app Nat
                        (build-list Nat 5)
                        (build-list Nat 5)
                        (char 5)
                        (m-char Nat 5)
                        (m-star-app Nat
                                    (build-list Nat 5)
                                    (nil Nat)
                                    (char 5)
                                    (m-char Nat 5)
                                    (m-star0 Nat (char 5))))
            : (ExpMatch Nat
                        (build-list Nat 5 5)
                        (star (char 5))))

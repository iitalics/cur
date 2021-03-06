#lang racket/base
(require
 ;; TODO: Ought just these core language forms, without for-syntax, modules, etc... somewhere
 (rename-in
  cur/curnel/racket-impl/type-check
  [typed-Type Type]
  [typed-define define]
  [typed-λ λ]
  [typed-Π Π]
  [typed-app #%app]
  [typed-axiom axiom]
  [typed-data data]
  [typed-elim new-elim]
  [deprecated-typed-elim elim])
 (for-syntax
  racket/base
  chk
  cur/curnel/racket-impl/reflection)

 #;(for-syntax (except-in racket/base sub1 add1 odd? exp even?) chk)
; "../../../../cur-lib/cur/curnel/turnstile/cur-to-turnstile.rkt"
 #;cur
#;(for-syntax
  (except-in "../../../../cur-lib/cur/curnel/turnstile/equiv.rkt" cur-equal?)
 "../../../../cur-lib/cur/curnel/turnstile/stxutils.rkt"
 "../../../../cur-lib/cur/curnel/turnstile/reflection.rkt"))

(begin-for-syntax
  (define test-env1 `((,#'x . ,#'X) (,#'X . ,#'(Type 1))))
  (chk
   #:x (cur-equal? #'x #'x) ""
   #:t (cur-equal? #'x #'x #:local-env `((,#'x . ,#'(Type 0))))

   #:eq cur-equal? (cur-type-infer #'X #:local-env `((,#'X . ,#'(Type 0)))) #'(Type 0)
   #:eq cur-equal? (cur-type-infer #'X #:local-env test-env1) #'(Type 1)

   ;; When comparing open terms, need to specify the environment under which they are equal
   #:eq (lambda (x y) (cur-equal? x y #:local-env test-env1))
     (cur-type-infer #'x #:local-env test-env1)
     #'X

   #:t (cur-type-check? #'x #'(Type 0) #:local-env `((,#'x . ,#'(Type 0))))

   #:do (define test-env2 `((,#'f . ,#'(Π (x : (Type 0)) (Type 0))) (,#'x . ,#'(Type 0))))
   #:eq cur-equal? (cur-type-infer #'f #:local-env test-env2)
   #'(Π (x : (Type 0)) (Type 0))

   #:eq (lambda (x y) (cur-equal? x y #:local-env test-env2))
     (cur-normalize #'(f x) #:local-env test-env2)
     #'(f x)))

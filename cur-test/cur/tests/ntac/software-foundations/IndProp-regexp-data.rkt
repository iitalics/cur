#lang cur
(require cur/stdlib/sugar
         ;cur/stdlib/equality
         ;cur/stdlib/prop
         cur/stdlib/list
         #|
         cur/ntac/base
         cur/ntac/standard
         cur/ntac/rewrite
         |#
         rackunit/turnstile
         "../rackunit-ntac.rkt")

(provide
 (all-defined-out))

(define-datatype RegExp [T : Type] : Type
  [empty-set* : (RegExp T)]
  [empty-str* : (RegExp T)]
  [char* [t : T] : (RegExp T)]
  [app* [r1 r2 : (RegExp T)] : (RegExp T)]
  [union* [r1 r2 : (RegExp T)] : (RegExp T)]
  [star* [r : (RegExp T)] : (RegExp T)])

(define-implicit empty-set = empty-set* 1)
(define-implicit empty-str = empty-str* 1)
(define-implicit char = char* 1)
(define-implicit app = app* 1)
(define-implicit union = union* 1)
(define-implicit star = star* 1)

(define-datatype ExpMatch [T : Type] : (-> (List T) (RegExp T) Type)
  [m-empty : (ExpMatch T (nil T) (empty-str T))]
  [m-char [t : T] : (ExpMatch T (build-list T t) (char T t))]
  [m-app [s1 s2 : (List T)] [r1 r2 : (RegExp T)]
         : (-> (ExpMatch T s1 r1)
               (ExpMatch T s2 r2)
               (ExpMatch T (list-append T s2 s1) (app T r1 r2)))]
  [m-unionL [s : (List T)] [r1 r2 : (RegExp T)]
            : (-> (ExpMatch T s r1)
                  (ExpMatch T s (union T r1 r2)))]
  [m-unionR [s : (List T)] [r1 r2 : (RegExp T)]
            : (-> (ExpMatch T s r2)
                  (ExpMatch T s (union T r1 r2)))]
  [m-star0 [r : (RegExp T)]
           : (ExpMatch T (nil T) (star T r))]
  [m-star-app [s1 s2 : (List T)] [r : (RegExp T)]
              : (-> (ExpMatch T s1 r)
                    (ExpMatch T s2 (star T r))
                    (ExpMatch T (list-append T s2 s1) (star T r)))])

(define-implicit ExpMatchImplicit = ExpMatch 1)

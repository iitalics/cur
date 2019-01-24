#lang s-exp "../main.rkt"

(provide (for-syntax (all-defined-out)))

(require
 (for-syntax "utils.rkt"
             (except-in macrotypes/stx-utils)
             (only-in macrotypes/typecheck-core subst substs)
             racket/exn
             racket/dict
             racket/list
             racket/match
             racket/pretty
             syntax/stx
             (for-syntax racket/base))
 "../stdlib/sugar.rkt"
 "base.rkt")

;; define-nttz-cmd ?
(define-for-syntax (nop ptz) ptz)

;; exceptions for tactics
(begin-for-syntax
  ;; ntac exceptions
  (struct exn:fail:ntac exn:fail ())

  ;; ntac exception for when the goal is not as expected.
  (struct exn:fail:ntac:goal exn:fail:ntac ())
  (define (raise-ntac-goal-exception msgf . rest)
    (raise (exn:fail:ntac:goal (apply format msgf rest) (current-continuation-marks))))

  (define-syntax-rule (ntac-match goal [pattern branch] ...)
    (cur-match goal
      [pattern branch]
      ...
      [_ (raise-ntac-goal-exception
          "Goal ~a did not match; you can use the `try` meta tactic to ignore this."
          goal)])))

;; display tactic
;; TODO: print number of subgoals
(begin-for-syntax
  (define (display-focus tz)
    (match (nttz-focus tz)
      [(ntt-hole _ goal)
       (for ([(k v) (in-dict (nttz-context tz))])
         (printf "~a : ~a\n" (stx->datum k) (stx->datum (cur-pretty-print v))))
       (printf "--------------------------------\n")
       (printf "~a\n\n" (stx->datum (cur-pretty-print goal)))]
      [(ntt-done _ _ _)
       (printf "Proof complete.\n")]
      [_
       ;; XXX
       (printf "Not at hole.\n")])
    tz)
  (define (display-focus/raw tz)
    (match (nttz-focus tz)
      [(ntt-hole _ goal)
       (for ([(k v) (in-dict (nttz-context tz))])
         (printf "~a : ~a\n" (syntax->datum k) (syntax->datum (cur-pretty-print v))))
       (for ([(k v) (in-dict (nttz-context tz))])
         (printf "~a : ~a\n" (syntax->datum k) (syntax->datum v)))
       (printf "--------------------------------\n")
       (printf "~a\n" (syntax->datum (cur-pretty-print goal)))
       (pretty-print (syntax->datum goal))
       (printf "\n\n")]
      [(ntt-done _ _ _)
       (printf "Proof complete.\n")]
      [_
       ;; XXX
       (printf "Not at hole.\n")])
    tz))

(begin-for-syntax
  (define current-proof null)
  (define (reset-current-proof!)
    (set! current-proof null))
  (define (current-proof-add! stx)
    (set! current-proof (cons stx current-proof)))
(define (interactive ptz)
  (display-focus ptz)
  (define cmd-stx
    (let/ec esc
      (parameterize ([current-eval
                      (λ (in)
                        (syntax-case in ()
                          [(_ . cmd)
                           (esc #'cmd)]))])
        (read-eval-print-loop))))
  (current-proof-add! cmd-stx)
  (define next-ptz
    (with-handlers ([exn:fail:ntac:goal?
                     (lambda (e)
                       (displayln (exn->string e))
                       ptz)])
      (eval-proof-step ptz cmd-stx)))
  (if (nttz-done? next-ptz)
      (begin
        (printf "complete proof script:\n")
        (for-each
         (λ (stx) (printf "~a\n" (syntax->datum stx)))
         (reverse (stx->list current-proof)))
        (reset-current-proof!)
        next-ptz)
      (interactive next-ptz))))

(define-for-syntax ((fill t) ptz)
  (define new-foc (t (nttz-context ptz) (nttz-focus ptz)))
  ;; XXX Maybe new-foc could be #f for failure?
  (next
   (struct-copy nttz ptz [focus new-foc])))

;; meta tactic; not a tactic (which take tacticals); takes a tactic.
(define-for-syntax ((try t) ptz)
  (with-handlers ([exn:fail:ntac:goal? (lambda (e) ptz)])
    (t ptz)))

;; define-tactical

(begin-for-syntax

  (define ((assert H ty) ctxt pt)
    (match-define (ntt-hole _ goal) pt)

    (make-ntt-apply
     goal
     (let ([ty+ (normalize ty ctxt)])
       (list
        (make-ntt-hole ty+)
        (make-ntt-context
         (λ (old-ctxt)
           (dict-set old-ctxt H ty+))
         (make-ntt-hole goal))))
     (lambda (arg-pf body-pf)
       (quasisyntax/loc goal
         ((λ (#,H : #,ty)
            #,body-pf)
          #,arg-pf)))))

  (define-syntax (by-assert syn)
    (syntax-case syn ()
      [(_ H ty)
       #`(fill (assert #'H #'ty))])))

(define-for-syntax ((intro [name #f]) ctxt pt)
  ;; TODO: ntt-match(-define) to hide this extra argument. Maybe also add ntt- to constructors in pattern?
  (match-define (ntt-hole _ goal) pt)
  (ntac-match goal
   [(~Π (x:id : P:expr) body:expr)
    (let ()
      (define the-name (or name (fresh #'x)))
      (make-ntt-apply
       goal
       (list
        (make-ntt-context
         (lambda (old-ctxt)
           (dict-set old-ctxt the-name #'P))
         (make-ntt-hole (cur-rename the-name #'x #'body))))
       (lambda (body-pf)
         (quasisyntax/loc goal (λ (#,the-name : #,(unexpand #'P)) #,body-pf)))))]))

;; A pattern emerges:
;; tacticals must take additional arguments as ntac-syntax
;; define-tactical should generate a phase 2 definition like the one below, and a functional version
;; of the tactical (perhaps by-tactical-name)
(begin-for-syntax
  (define-syntax (by-intro syn)
    (syntax-case syn ()
      [(_ syn #:as paramss)
       #`(compose (fill (destruct #'syn #'paramss)) (fill (intro #'syn)))]
      [(_ syn)
       #`(fill (intro #'syn))]
      [_
       #`(fill (intro))])))

(define-for-syntax (intros names)
  (for/fold ([t nop])
            ([n (in-list names)])
    (compose (fill (intro n)) t)))
(begin-for-syntax
  (define-syntax (by-intros syn)
    (syntax-case syn ()
      [(_ id ...)
       #`(intros (list #'id ...))])))

;; define-tactical
(define-for-syntax ((exact a) ctxt pt)
  (match-define (ntt-hole _ goal) pt)
  (unless (cur-type-check? a goal #:local-env (ctxt->env ctxt))
    (raise-ntac-goal-exception "~a does not have type ~a"
                               (stx->datum (resugar-type a))
                               (stx->datum (resugar-type goal))))
  (make-ntt-exact goal a))

(begin-for-syntax
  (define-syntax (by-exact syn)
    (syntax-case syn ()
      [(_ syn)
       #`(fill (exact #'syn))])))

;;define-tactical
(define-for-syntax (assumption ctxt pt)
  (match-define (ntt-hole _ goal) pt)
  ;; TODO: Actually, need to collect (k v) as we search for a matching assumption, otherwise we might
  ;; break dependency. Hopefully we have some invariants that prevent that from actually happening.
  (define ntt
    (for/or ([(k v) (in-dict ctxt)]
           #:when (cur-equal? v goal #:local-env (ctxt->env ctxt)))
      (make-ntt-exact goal k)))
  (unless ntt
    (raise-ntac-goal-exception "could not find matching assumption for goal ~a" goal))
  ntt)

(begin-for-syntax
  (define-syntax (by-assumption syn)
    (syntax-case syn ()
      [_
       #`(fill assumption)]))

  (define (obvious ctxt pt)
    (match-define (ntt-hole _ goal) pt)
    (ntac-match goal
      [(~Π (a : P) body)
       ((intro) ctxt pt)]
      [a:id
       (assumption ctxt pt)]))

  (define (by-obvious ptz)
    (define nptz ((fill obvious) ptz))
    (if (nttz-done? nptz)
        nptz
        (by-obvious nptz)))

  (define (simpl ptz)
    (match-define (ntt-hole _ goal) (nttz-focus ptz))
    (next
     ;; TODO: should this be a copy?
     (struct-copy nttz ptz
                  [focus
                   (make-ntt-hole (normalize goal (nttz-context ptz)))])))

  (define-syntax (by-destruct syn)
    (syntax-case syn ()
      [(_ x)
       #`(fill (destruct #'x))]
      [(_ x #:as param-namess)
       #`(fill (destruct #'x #'param-namess))]))

  (define ((destruct e [param-namess #f]) ctxt pt)
    (match-define (ntt-hole _ goal) pt)

    (define e-ty (or (and (identifier? e) (dict-ref ctxt e #f))
                     (typeof (normalize e ctxt))))
    (define name (if (identifier? e) e (generate-temporary)))
    (define/syntax-parse (_ _ [C ([_ τ] ...) _] ...) (get-match-info e-ty))

    (define Cs #'(C ...))
    (define paramss (or param-namess (stx-map (λ _ #'()) Cs)))
    (define pats
      (stx-map
       (λ (C ps)
         (if (null? (syntax->list ps))
             C
             #`(#,C . #,ps)))
       Cs paramss))

    ;; changed-env-tys: listof listof [x ty], one list for each destruct clause
    ;; the xs are the ctxt vars affected (ie in scope) of the destructed var
    (define changed-env-tys null)
    
    (make-ntt-apply
     goal
     (stx-map
      (λ (pat C-types params)
        ;; find which ctxt entries are affected by the destruct
        ;; - these are used by the proof term
        (set! changed-env-tys
              (append
               changed-env-tys
               (list
                (for/list ([(k v) (in-dict ctxt)]
                           #:when (has-term? e v))
                 (list k v)))))
        (define (update-ctxt old-ctxt)
          (define tmp-ctxt
            (foldr ; update ty in ctxt with (subst-term pat e _)
             (λ (k v acc)
               (dict-set/flip k (subst-term (normalize pat acc) e v) acc))
             (foldr ; add params
              dict-set/flip
              (mk-empty-ctxt) ;old-ctxt ; need fresh context to get binding ordering right
              (syntax->list params)
              (syntax->list C-types))
            (dict-keys old-ctxt)
            (dict-values old-ctxt)))
          (if (identifier? e)
              (dict-remove tmp-ctxt e) ; remove e if it's a name
              tmp-ctxt))
        (make-ntt-context
          update-ctxt
          (make-ntt-hole (normalize (subst-term pat e goal) (update-ctxt ctxt)))))
      pats
      #'((τ ...) ...)
      paramss)
     (λ pfs
       (quasisyntax/loc goal
         ;; each match body must be an eta-expansion of the pf \in pfs,
         ;; and the match term must be applied to the env bindings whose tys ref the destructed var
         ((match #,e
            #:as #,name
            #:in #,e-ty
            #:return (-> #,@(map (λ (k+v) (subst-term name e (cadr k+v))) (car changed-env-tys))
                         #,(subst-term name e goal))
                 . #,(stx-map
                      (λ (pat pf changed)
                        #`[#,pat
                           (λ #,@(map (λ (k+v) #`[#,(car k+v) : #,(subst-term pat e (cadr k+v))]) changed)
                             #,pf)])
                      pats
                      pfs
                      changed-env-tys))
          #,@(map car (car changed-env-tys)))))))

  (define-syntax (by-induction syn)
    (syntax-case syn ()
      [(_ x #:as param-namess)
       #'(by-induction x #:as param-namess #:params ())]
      [(_ x #:as param-namess #:params Xs)
       #`(fill (induction #'x #'param-namess #'Xs))]))

  ;; TODO: similar to destruct; merge somehow?
  ;; TODO: use match or elim as proof term?
  (define ((induction name paramss Xs) ctxt pt)
    (match-define (ntt-hole _ goal) pt)

    (define name-ty (dict-ref ctxt name))
    (define/syntax-parse (_ ([A _] ...) [C ([x τ_] ...) ((xrec . _) ...)] ...) (get-match-info name-ty))
    (define Cs #'(C ...))
    (define/syntax-parse (X ...) Xs)
    (define/syntax-parse ((τ ...) ...) (substs Xs #'(A ...) #'((τ_ ...) ...)))
    (define pats ; TODO: check length of paramss against (τ...) ...?
      (stx-map
       (λ (C τs ps)
         (if (and (null? (syntax->list ps)) (null? Xs))
             C
             #`(#,C X ... . #,(stx-take ps (stx-length τs)))))
       Cs #'((τ ...) ...) paramss))

    ;; for each param, type is either
    ;; - argument types from C-type (if arg)
    ;; - subst xrec for name in goal (if IH)
    ;;   - where xrec specified by the "match info"
    (define param-typess
      (stx-map
       (λ (params τs xs xrecs)
         ;; params = regular C args + IHs
         (match-define (list ps IHs) (stx-split-at params (stx-length τs)))
         #`(#,@τs .
            #,(for/list ([ih IHs])
                (for/fold ([g goal])
                          ([p ps] [x (in-stx-list xs)] #:when (stx-member x xrecs))
                  ;; TODO: is this right? subst xrecs (assuming only 1) for name in goal
                  (subst p name goal)))))
       paramss
       #'((τ ...) ...)
       #'((x ...) ...)
       #'((xrec ...) ...)))

    (make-ntt-apply
     goal
     (stx-map
      (λ (pat params param-types)
        (define (update-ctxt old-ctxt)
          ; drop `name` from ctxt
          ; but add bindings for:
          ; - constructor arguments of `name`
          ; - IHs for args with type name-ty
          (dict-remove
           (foldl
            dict-set/flip
            old-ctxt
            (syntax->list params)
            (syntax->list param-types))
           name))
        (make-ntt-context
         update-ctxt
         (make-ntt-hole
          (normalize (subst pat name goal) (update-ctxt ctxt)))))
      pats
      paramss
      param-typess)
     (λ pfs
       (quasisyntax/loc goal
         (new-elim
          #,name
          (λ [#,name : #,name-ty] #,goal)
          .
          #,(stx-map
             (λ (params param-types pf)
               (if (null? (syntax->list params))
                   pf
                   (foldr
                    (λ (p ty e) #`(λ [#,p : #,ty] #,e))
                    pf
                    (syntax->list params)
                    (syntax->list param-types))))
             paramss
             param-typess
             pfs)))))))

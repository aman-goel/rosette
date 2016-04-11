#lang racket

(provide select rosette-evaluator rosette-log-evaluator logfile)

(require 
  (for-label racket racket/generic)
  (only-in rosette rosette union union-contents union?)
  racket/sandbox racket/serialize scribble/eval
  (only-in scribble/manual elem racket))

(define lifted? 
  (let ([lifted (apply set (rosette))])
    (lambda (id) (set-member? lifted id))))

(define (select racket-ids)
   (apply elem 
          (add-between (map (lambda (id) (racket #,#`#,id)) 
                            (filter lifted? racket-ids)) ", ")))

(define (rosette-evaluator [eval-limits #f])
   (parameterize ([sandbox-output 'string]
                  [sandbox-error-output 'string]
                  [sandbox-path-permissions `((execute ,(byte-regexp #".*")))]
                  [sandbox-memory-limit #f]
                  [sandbox-eval-limits eval-limits])
     (make-evaluator 'rosette/safe)))

(define logfile
  (let ([files (make-hash)])
    (lambda (root [base "log"])
      (let ([cnt (hash-ref files root 0)])
        (hash-set! files root (add1 cnt))
        (build-path root (format "~a-~a.txt" base cnt))))))

(define (serialize-for-logging v)
  (match v
    [(or (? boolean?) (? number?) (? string?) (? void?)) v]
    [(? box?) (box (serialize-for-logging (unbox v)))]
    [(? pair?) (cons (serialize-for-logging (car v)) (serialize-for-logging (cdr v)))]
    [(? list?) (map serialize-for-logging v)]
    [(? vector?) (list->vector (map serialize-for-logging (vector->list v)))]
    [(? custom-write?)
     (let ([output-str (open-output-string)])
       ((custom-write-accessor v) v output-str 1)
       (opaque (get-output-string output-str)))]
    [_ v]))

(serializable-struct opaque (str)
  #:methods gen:custom-write
  [(define (write-proc self port mode)
     (fprintf port "~a" (opaque-str self)))])

(define (serializing-evaluator evaluator)
  (lambda (expr) (serialize-for-logging (evaluator expr))))

(define (rosette-log-evaluator logfile [eval-limits #f])  
  (if (file-exists? logfile)
      (make-log-based-eval logfile 'replay)
      (parameterize ([current-eval (serializing-evaluator (rosette-evaluator eval-limits))])
        (make-log-based-eval logfile 'record))))

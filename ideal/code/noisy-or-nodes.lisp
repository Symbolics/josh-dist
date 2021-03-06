;;; -*- Mode: LISP; Syntax: Common-Lisp; Package: Ideal;  Base: 10 -*-


(in-package :ideal)

;;;;********************************************************
;;;;  Copyright (c) 1989, 1992 Rockwell International -- All rights reserved.
;;;;  Rockwell International Science Center Palo Alto Lab
;;;;********************************************************


;;;;;;;;;;;;;;;;;;;;;;;; Sampath ;;;;;;;;;;;;;;;;;;;;


(export '(NOISY-OR-NODE-P
	   NOISY-OR-SUBTYPE
	   CONVERT-NOISY-OR-NODE-TO-CHANCE-NODE
	   CONVERT-CHANCE-NODE-TO-NOISY-OR-NODE 
	   INHIBITOR-PROB-OF
	   NOISY-OR-DET-FN-OF
	   COMPILE-NOISY-OR-DISTRIBUTION
	   NOISY-OR-FALSE-CASE-P
	   CONVERT-NOISY-OR-NODE-TO-SUBTYPE))

;-----------------------------------------------------------------------------------------
;---------- ABSTRACT data structure level ----------------------------------------
;-----------------------------------------------------------------------------------------

(defun noisy-or-node-p (node)
  (and (chance-node-p node)
       (discrete-dist-noisy-or-p (node-distribution node))))

(defun noisy-or-subtype (node)
  (discrete-dist-noisy-or-subtype (node-distribution node)))

(defun set-noisy-or-subtype (node val)
  ; Also allows the subtype to be set to NIL to account for the case
  ; where one is unsetting the subtype, i,e, converting the noisy-or
  ; node to a chance node.
  (or (null val)
      (ecase val (:BINARY)(:NARY)(:GENERIC)))
  (setf (discrete-dist-noisy-or-subtype (node-distribution node)) val))

(defsetf noisy-or-subtype set-noisy-or-subtype)

;--------------------------------------------------------

(defun set-noisy-or-flag (node &key subtype)
  (cond
    ((not (chance-node-p node))
     (error "Cant set Noisy Or flag for node ~A since its not a chance node"))
    (t (setf  (discrete-dist-noisy-or-p (node-distribution node)) t)
       (setf (noisy-or-subtype node) subtype))))

(defun unset-noisy-or-flag (node)
  (cond
    ((not (chance-node-p node))
     (error "Cant set Noisy Or flag for node ~A since its not a chance node"))
    (t (setf  (discrete-dist-noisy-or-p (node-distribution node)) nil)
       (setf (noisy-or-subtype node) nil)
       (setf (discrete-dist-noisy-or-info (node-distribution node)) nil))))

;---

; When calling this function all other internal state in the node is in
; a consistent state and so we just switch the type.

;  (This 'consistent state' ensured by careful coding -- basiclly the
; thing to note is to always compile the noisy or distribution after it
; changes in any way -- for eg in add-arcs)

(defun convert-noisy-or-node-to-chance-node (n)
  (when (noisy-or-node-p n)
    (ideal-debug-msg "~%Converting ~A noisy or node ~A to a chance node"
		     (noisy-or-subtype n) n)
    (unset-noisy-or-flag n))
  (values n))

(defun convert-noisy-or-nodes-to-chance-nodes (diagram)
  (dolist (n diagram)
    (convert-noisy-or-node-to-chance-node n)))

; Converts a chance to node to a noisy-or node of type :BINARY (if it
; has two states) or of type :NARY otherwise. If the chance node is a
; deterministic chance node then it is converted to be a :GENERIC
; noisy-or node with the det function being the same as the deterministi
; chance node's det function.

(defun convert-chance-node-to-noisy-or-node (n)
  (cond
    ((not (chance-node-p n))
     (error "Cannot convert ~A to noisy-or node since it is of type ~A, not :CHANCE"
	    n (node-type n)))
    (t 	; Sets the noisy or flag
     (setf (discrete-dist-noisy-or-p (node-distribution n)) t)
     (cond
       ((deterministic-node-p n)
	(let ((det-fn-array (distribution-repn n)))
	  (setf (noisy-or-subtype n) :GENERIC)
	  (setf (relation-type n) :PROB)
	  (create-empty-distribution n)
	  (for-all-cond-cases (pred-case (node-predecessors n))
	    (setf (noisy-or-det-fn-of n pred-case)
		  (contents-of-det-array-location
		    det-fn-array pred-case (node-predecessors n))))))
       ((probabilistic-node-p n)
	(setf (noisy-or-subtype n)
	      (if (= (number-of-states n) 2) :BINARY :NARY))
	(create-empty-distribution n)
	(set-noisy-or-det-fn-to-standard-nary-or-fn n))
       (t
	(error "Node ~A is neither deterministic or probabilistic" n)))
	; Compile the distribution
     (compile-noisy-or-distribution n)
     (values n))))
       
;-----------------------

(defun create-empty-noisy-or-distribution (node &key (default-inhibitor-prob 0))
  (labels ((create-prob-list-for-predecessor (p)
	     (mapcar #'(lambda (s)(cons s default-inhibitor-prob)) (state-labels p)))
	   (make-inhibitor-prob-structure (node)
	     (mapcar #'(lambda (p)(cons p (create-prob-list-for-predecessor p)))
		     (node-predecessors node))))
    (setf (discrete-dist-noisy-or-info (node-distribution node))
	  (make-noisy-or
	    :inhibitor-probs (make-inhibitor-prob-structure node)
	    :det-fn-array (make-probability-array (node-predecessors node)
						  :element-type 'LABEL
						  :initial-element (make-label :name 'DUMMY))
	    ; This field is purely so that a visible backpointer is available
	    ; during debugging. Is not actually used by the code at all.
	    :owner-node node))
    (values)))

(defun get-noisy-or-info (node)
  (discrete-dist-noisy-or-info (node-distribution node)))

; Returns the pair state.prob if found or :NO-ENTRY if error-mode is
; nil. If not an error.

(defun get-noisy-or-inhibitor-prob-entry (noisy-or-info pred-case &key (error-mode t))
  (cond
    ((not (exactly-one pred-case))
     (error "~A should be a conditioning case containing exactly one node state pair"
	    pred-case))
    (t (or (assoc (state-in pred-case)
		  (cdr (assoc (node-in pred-case)
			      (noisy-or-inhibitor-probs noisy-or-info))))
	   (if (not error-mode) :NO-ENTRY)
	   (error "No entry inhibitor prob of ~A in ~A" pred-case noisy-or-info)))))

;-------------------------------

(defun inhibitor-prob-of (node pred-case)
  (cdr (get-noisy-or-inhibitor-prob-entry
	 (discrete-dist-noisy-or-info (node-distribution node))
	 pred-case)))

(defun set-inhibitor-prob-of  (node pred-case value)
  (setf (cdr (get-noisy-or-inhibitor-prob-entry
	       (discrete-dist-noisy-or-info (node-distribution node))
	       pred-case)) value))

(defsetf inhibitor-prob-of set-inhibitor-prob-of)

; If entry is not found and non-nil default is specified then default is
; returned. No entry and no default causes an error.

(defun get-inhibitor-prob-from-noisy-or-info (noisy-or-info pred-case &key default)
  (let ((entry (get-noisy-or-inhibitor-prob-entry
		 noisy-or-info pred-case :error-mode nil)))
    (cond
      ((eq entry :NO-ENTRY)
       (or default
	   (error "No entry for ~A in ~A and no default specified" pred-case noisy-or-info)))
      (t (cdr entry)))))

;---------------------------

(defun noisy-or-det-fn-of (node pred-case)
  (get-det-fn-value-from-noisy-or-info
    (discrete-dist-noisy-or-info (node-distribution node))
    (node-predecessors node)
    pred-case))

; This additional level of indirection is because this function is used
; to retrieve information from the previous det fn array when modifying
; the det fn array in diagram editing functions like add-arcs, delete-arcs,
; add-state etc.

(defun get-det-fn-value-from-noisy-or-info (noisy-or-info predecessors pred-case)
  (read-probability-array (noisy-or-det-fn-array noisy-or-info)
			  pred-case
			  predecessors))

(defun set-noisy-or-det-fn-of (node pred-case value)
  (write-probability-array (noisy-or-det-fn-array
			     (discrete-dist-noisy-or-info
			       (node-distribution node)))
			   pred-case
			   (node-predecessors node)
			   value))

(defsetf noisy-or-det-fn-of set-noisy-or-det-fn-of)

;------------------------------

; Copies inhibitor probs from noisy-or-info into the present
; noisy-or-info of node. If values are not found for some location
; <default> is used instead if it is not nil, if <default> is nil an
; error is signalled.

(defun copy-inhibitor-probs (node noisy-or-info &key (default nil))
  (dolist (p (node-predecessors node))
    (for-all-cond-cases (pred-case p)
      (setf (inhibitor-prob-of node pred-case)
	    (get-inhibitor-prob-from-noisy-or-info
	      noisy-or-info pred-case :default default)))))

;-----------------------------------------------------------------------------------------
;---------------------- High level -------------------------------------------------------
;-----------------------------------------------------------------------------------------

(defun compile-noisy-or-distribution (node)
  (for-all-cond-cases (u (node-predecessors node))
    (for-all-cond-cases (x node)
      (setf (prob-of x u) 0))
    (let (x x-case)
      (for-all-cond-cases (u-prime (node-predecessors node))
	(setq x (noisy-or-det-fn-of node u-prime))
	(setq x-case (make-conditioning-case (list (cons node x))))
	(incf (prob-of x-case u)
	      (calc-transformation-prob node u-prime u)))))
  (values nil))

; Used for consistency checking only. Is much more inefficient to use
; this directly rather than to compile the table as above.

(defun calc-noisy-or-prob-of (node-case cond-case)
  (let ((s (state-in node-case))
	(n (node-in node-case))
	(total 0))
    (for-all-cond-cases (u-prime (node-predecessors n))
      (when (eq (noisy-or-det-fn-of n u-prime) s)
	(incf total (calc-transformation-prob n u-prime cond-case))))
    (values total)))

; Calculates the probability of conditoning case bold-u being
; transformed to conditioning case bold-u-prime taking into account both
; normal operation and failures of nodes.

; Note: in doing in the map to walk down both u-prime and u
; simultaneously, I am assuming that the order in which the nodes appear
; in u-prime and in u are the same.  <individual-transformation-prob>
; relies on this prooperty (though it does make a check).

; The assumption is ok because of the implementation details of
; for-all-cond-cases but it bears explicit mentioning since it is an
; implementation dependant hack.

(defun calc-transformation-prob (node bold-u-prime bold-u)
  (multiply-over ((u-prime bold-u-prime)(u bold-u))
    (individual-transformation-prob node u-prime u)))

(defun individual-transformation-prob (node u-prime u)
  (let ((u-prime-node (car u-prime))
	(u-prime-state (cdr u-prime))
	(u-node (car u))
	(u-state (cdr u)))
    (unless (eq u-prime-node u-node)
      (error "Program error. The node in u-prime, ~A and in u, ~A should be the same.
                         See comments near this function's definition. Needs debugging."
	     u-prime-node u-node))
    (cond
      ((eq u-state u-prime-state)
       (+ (prob-of-all-inhibitors-being-normal node u-node)
	  (inhibitor-prob-of node (make-conditioning-case (list u-prime)))))
      (t (inhibitor-prob-of node (make-conditioning-case (list u-prime)))))))

; Could have cached this 'normal' probability in the data structure
; but what the heck, this is a"compile time" step and so we can be
; a little inefficient.

(defun prob-of-all-inhibitors-being-normal (node predecessor)
  (let ((total-failure-prob 0))
    (for-all-cond-cases (pred-case predecessor)
      (incf total-failure-prob (inhibitor-prob-of node pred-case)))
    (values (- 1 total-failure-prob))))

;----------------------------

(defun find-label-numbered (node m)
  (or (find m (state-labels node) :key #'label-id-number :test #'=)
      (error "Could not find label numbered ~A of node ~A" m node)))

(defun generalized-nary-or-function (node pred-case)
  (labels ((largest-state-number (n)
	     (- (number-of-states n) 1))
	   (ratio (n m)
	     (if (zerop n) 0 (/ n m))))
    (find-label-numbered node
      (ceiling
	(* (ratio
	     (sum-over (pred.state pred-case)
	       (ratio
		 (label-id-number (cdr pred.state))(largest-state-number (car pred.state))))
	     (number-of-predecessors node))
	   (largest-state-number node))))))

(defun set-noisy-or-det-fn-to-standard-nary-or-fn (node)
  (for-all-cond-cases (case (node-predecessors node))
    (setf (noisy-or-det-fn-of node case)
	  (generalized-nary-or-function node case))))

(defun set-noisy-or-det-fn-randomly (node)
  (let ((random-state (first (state-labels node))))
    (for-all-cond-cases (case (node-predecessors node))
      (setf (noisy-or-det-fn-of node case)
	    random-state))))

; This function and immediate following functions are temporary and not necessary
; for IDEAL to function. used for examples for the Noisy Or paper.

(defun reset-noisy-or-det-fn (node function)
  (for-all-cond-cases (case (node-predecessors node))
    (setf (noisy-or-det-fn-of node case)
	  (find-label-numbered
	    node
	    (apply function
		   (mapcar #'(lambda (n.s)(label-id-number (cdr n.s))) case)))))
	; The following call takes care of recompiling the distribution too.
  (convert-noisy-or-node-to-subtype node :GENERIC))

(defun and-f (&rest args)
  (cond
    ((not (every #'(lambda (a)(and (numberp a)(or (= a 0)(= a 1)))) args))
     (error "Incorrect argument pattern ~A"))
    (t (if (every #'(lambda (a) (= a 1)) args) 1 0))))


(defun xor-f (&rest args)
  (cond
    ((not (every #'(lambda (a)(and (numberp a)(or (= a 0)(= a 1)))) args))
     (error "Incorrect argument pattern ~A"))
    ((not (= (length args) 2))
     (error "Incorrect arg pattern"))
    (t (if (= (apply #'+ args) 1) 1 0))))


(defun or-f (&rest args)
  (cond
    ((not (every #'(lambda (a)(and (numberp a)(or (= a 0)(= a 1)))) args))
     (error "Incorrect argument pattern ~A"))
    (t (if (some #'(lambda (a) (= a 1)) args) 1 0))))

(defun add-f (&rest args)
  (cond
    ((not (every #'(lambda (a)(numberp a)) args))
     (error "Incorrect argument pattern ~A"))
    (t (apply #'+ args))))

;--------------------------------------

(defun noisy-or-false-case-p (node-case)
  (= (label-id-number (state-in node-case)) 0))

(defun conv (node)
  (convert-noisy-or-node-to-subtype node :GENERIC)
  (dolist (s (state-labels node))
    (setf (label-name s)
	  (ecase (label-name s)
	    (:TRUE :S-0)
	    (:FALSE :S-1))))
  (add-state node :S-2)
  (add-state node :S-3)
  (reset-noisy-or-det-fn node #'add-f))

;------------------------------------------

(defun convert-noisy-or-node-to-subtype (node new-subtype)
  (when (and (eq new-subtype :BINARY)(> (number-of-states node) 2))
    (setq new-subtype :NARY))
  (setf (noisy-or-subtype node) new-subtype)
  ; Make all inhibitor probs except for the false case 0 if the new type
  ; is binary.
  (when (eq new-subtype :BINARY)
    (dolist (p (node-predecessors node))
      (for-all-cond-cases (pred-case p)
	(if (not (noisy-or-false-case-p pred-case))
	    (setf (inhibitor-prob-of node pred-case) 0)))))
  (ecase new-subtype
    ((:BINARY :NARY)
     (set-noisy-or-det-fn-to-standard-nary-or-fn node))
    ((:GENERIC) ; Just let the old function be. 
     ;;; (set-noisy-or-det-fn-randomly node)
     ))
  (compile-noisy-or-distribution node)
  (values node))

;;; -*- Mode: LISP; Syntax: Common-Lisp; Package: Ideal;  Base: 10 -*-

(in-package :ideal)


;;;;********************************************************
;;;;  Copyright (c) 1989, 1992 Rockwell International -- All rights reserved.
;;;;  Rockwell International Science Center Palo Alto Lab
;;;;********************************************************

;;;;;;;;;;;;;;;;;;;;;;;; Sampath ;;;;;;;;;;;;;;;;;;;;


(export '(IDEAL-STRUCTURE IDEAL-STRUCT-P))

;------------------------------------------

; Structures have to be printed in default lisp readable format when
; writing diagrams to file using the fn save-diagram. To do this without
; resorting to implementation dependant hacks one has to keep a record
; of the field names and access-fns for each structure type. The
; following macro should be called immediately after a call to
; defstruct. It stores the names of the fields and access-fns in the
; format ((field . access-fn) ...) as the property IDEAL-STRUCT-FIELDS
; on the name of the structure.  The argument pattern is identical to
; defstruct. When defining the print-function (if any ) for these
; structures the macro "defidealprintfn" (see below) HAS TO be used
; instead of defun.

(defmacro store-ideal-struct-info (name-et-al . field-info)
  `(let* ((name-etc ',name-et-al)
	  (fields ',field-info)
	  (struct-name (get-name-symbol name-etc))
	  (field-names (mapcar #'get-name-symbol fields))
	  (conc-name-list (find-if-mentioned :CONC-NAME name-etc))
	  (new-copier-name (find-if-mentioned :COPIER name-etc))
	  (include (find-if-mentioned :INCLUDE name-etc)))
	; What to do when :include is specified
     (cond
       ((and include (not (ideal-struct-name-p (cadr include))))
	(error "You may not include structure ~A in structure ~A since ~A ~
                    has no stored ideal struct info"
	       struct-name (cadr include) struct-name))
       (new-copier-name
	(error "You may not specify the :COPIER argument. This macro cannot ~
                handle it"))
       (conc-name-list
	(error "You may not specify the :CONC-NAME argument. This macro cannot ~
                handle it")))
     ; Keeping a record of the field names & access-functions on the plist of the struct-name.
       (setf (get struct-name 'IDEAL-STRUCT-FIELDS)
	     (append
	       (if include (get (cadr include) 'IDEAL-STRUCT-FIELDS))
	       (mapcar #'(lambda (field)
			   (cons-field&access-fn field struct-name))  field-names)))
  (construct-and-install-recursive-copy-function name-etc)
  (pushnew struct-name *ideal-structure-types*)))

(defun find-if-mentioned (key name-list)
  (cond
    ((atom name-list) nil)
    ( t (assoc key (cdr name-list)))))

(defun get-name-symbol (object)
  (if (atom object) object (car object)))

(defun ideal-struct-name-p (symbol)
  (let ((failure-flag (gentemp)))
    (not (eq failure-flag (get symbol 'IDEAL-STRUCT-FIELDS failure-flag)))))

(defun cons-field&access-fn (field struct-name)
  (let* ((access-fn-string-name (format nil "~A-~A" (symbol-name struct-name) (symbol-name field)))
	 (access-fn-symbol (find-symbol access-fn-string-name)))
    (cond
      ((not (fboundp access-fn-symbol))
       (error "Function of the name ~A does not exist. You probably made a call to ~
              the macro STORE-IDEAL-STRUCT-INFO before defining the structure ~A ~
              with a defstruct" access-fn-string-name struct-name))
      (t (cons field (symbol-function access-fn-symbol))))))


; This macro defines the print function in such a way that if
; *default-ideal-structure-printing* is t then the structure is printed
; in default lisp readable format. If *default-ideal-structure-printing*
; is nil the structure is printed according to the definition given by
; the user.  The arguments (print-fn-name (n s) . body) are like
; defining a function using labels.

(defmacro defidealprintfn (struct-name (print-fn-name (n s). body))
  `(compile ',print-fn-name
	    '(lambda (,n ,s depth)
	       (declare (ignore depth))
	       (cond
		 (*default-ideal-structure-printing*
		  (print-structure-in-default-format ',struct-name ,n ,s))
		 (t ,@body)))))

(defun print-structure-in-default-format (struct-type structure stream)
  (format stream "#s(~S" struct-type)
  (dolist (field.access-fn (get struct-type 'IDEAL-STRUCT-FIELDS))
    (format stream "~%:~S ~S" (car field.access-fn)
	    (funcall (cdr field.access-fn) structure)))
  (format stream ")"))


; This installs a lambda fn which recursively copies a structure whose
; name is in name-et-al as the property RECURSIVE-COPIER of the
; structure's name symbol. The lambda fn calls a function called
; RECURSIVELY-COPY which is defined in the file copy-diagram.lisp. When
; the dont-copy-top-level-structure argument to the lambda fn is true
; the contents of each field of the structure are replaced by a
; recursive copy of the contents but the top level structure is returned
; as is instead of being copied. This is required because NODE
; structures have to be handled in a special way.

(defun construct-and-install-recursive-copy-function (name-etc)
  (let* ((struct-name (get-name-symbol name-etc))
	 (fn (compile nil
		      `(lambda (struct new-diag &key (dont-copy-top-level-structure nil))
			 (let ((new-struct (cond
					     (dont-copy-top-level-structure struct)
					     ( t (,(get-copier-name struct-name) struct)))))
			   ,@(mapcar
			       #'(lambda (name.access-fn)
				   `(setf (,(get-field-name struct-name (car name.access-fn))
					   new-struct)
					  (recursively-copy
					    (,(get-field-name struct-name (car name.access-fn))
					     new-struct) new-diag)))
			       (get struct-name 'IDEAL-STRUCT-FIELDS))
			   (values new-struct))))))
    (setf (get struct-name 'recursive-copier) fn)))


(defun get-copier-name (sym)
  (find-symbol  (format nil "~a-~A" (symbol-name :copy) sym)))

(defun get-field-name (struct-name field)
  (find-symbol (format nil "~A-~A" (symbol-name struct-name) (symbol-name field))))


; This type definition is used in recursive-copy

(deftype ideal-structure ()
  `(satisfies ideal-struct-p))

(defun ideal-struct-p (object)
  (some #'(lambda (ideal-struct-type)
	    (typep object ideal-struct-type)) *ideal-structure-types*))

;-- Needed coz we dont want to copy some junk structures.

(deftype non-copiable-structure ()
  `(satisfies non-copiable-structure-p))

(defun non-copiable-structure-p (object)
  (some #'(lambda (type)
	    (typep object type)) *non-copiable-structure-types*))


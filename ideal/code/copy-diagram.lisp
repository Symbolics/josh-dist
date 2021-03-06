;;; -*- Mode: LISP; Syntax: Common-Lisp; Package: Ideal;  Base: 10 -*-

(in-package :ideal)


;;;;********************************************************
;;;;  Copyright (c) 1989, 1992 Rockwell International -- All rights reserved.
;;;;  Rockwell International Science Center Palo Alto Lab
;;;;********************************************************


;;;;;;;;;;;;;;;;;;;;;;;; Sampath ;;;;;;;;;;;;;;;;;;;;



(export '(COPY-DIAGRAM))

;--------------------------------------------------------
      
; This function recursively copies a diagram to yield a new copy. If a
; clique diagram belonging to the diagram is also provided the clique
; diagram is also copied recursively.

; This copying process is complicated by the fact that the diagram and
; clique diagram have cross pointers (eg., the component nodes of a
; clique node are nodes in the diagram) and circular pointers (eg., the
; predecessors of a node are nodes in the diagram). Appropriate cross
; and circular pointers have also to be translated to the copy. To do
; this the fn copy-diagram-1 first makes a "read-table" of the nodes and
; node-labels (of both the inf diagram and clique diagram). Later when
; recursively copying through the entire diagram structure it identifies
; any node or label it encounters in the read table and puts in the
; appropriate pointer in the copy. (Actually, the fn first copies the
; top level structure of each node and creates the read table out of
; these copied top level structures. Later it goes thru copying the
; contents of each of these node structures. Whenever it encounters a
; node or a label it replaces it with the appropriate node or label
; (meaning the node or label of the same NAME) from the read table, thus
; maintaining the cross pointers. Note that it is CRUCIAL that
; node-names and label-names are symbols.)

(defun copy-diagram (&optional (diagram *diagram*) clique-diagram)
  (copy-diagram-1 diagram clique-diagram :mode :NORMAL))

; --- The following two functions are used by save-diagram and
; load-diagram respectively.  see file-io.lisp

; Copies the diagram such that the copy is non-circular.

(defun copy-for-saving (diagram clique-diagram)
  (copy-diagram-1 diagram clique-diagram :mode :FOR-SAVING))

; Is given a non-circular diagram which has just been read from file as
; input and this fn makes a copy with the proper circular pointers by
; replacing the node-refs with the appropriate nodes and by uniquefying
; the labels.

(defun copy-after-loading (diagram clique-diagram)
  (copy-diagram-1 diagram clique-diagram :mode :FOR-LOADING))


;---- The actual copier. Makes a check for hidden nodes if 
;hidden-node-check is t. Makes a non circular-copy (suitable for 
;writing to file) if non-circular-copy is t. Returns the copied 
;diagram.

(defun copy-diagram-1 (original-diagram clique-diagram &key mode)
						; Binding *non-circular-copy* appropriately
  (let* ((*non-circular-copy*
	   (ecase mode (:FOR-SAVING t)(:FOR-LOADING nil)(:NORMAL nil))))
    (when clique-diagram
      (check-if-clique-diagram-belongs-to-diagram original-diagram clique-diagram mode))
    (multiple-value-bind (new-node-table new-diag new-clique-diag)
	(make-new-node-table original-diagram clique-diagram mode)
      (dolist (node new-diag)
	(recursively-copy node new-node-table :top-level-call t))
      (dolist (c-node new-clique-diag)
	(recursively-copy c-node new-node-table :top-level-call t))
      (ecase mode
	((:FOR-LOADING :NORMAL)
	 (values (delete-if #'dummy-node-p new-diag)
		 (delete-if #'dummy-clique-node-p new-clique-diag)))
	((:FOR-SAVING)
	 (values new-diag new-clique-diag))))))

; We actually should have a diagram structure instead of making these
; checks in this hacked way but its too late to think of that.

(defun check-if-clique-diagram-belongs-to-diagram (diagram clique-diagram mode)
  (ecase mode
    (:FOR-LOADING t)
    ((:FOR-SAVING :NORMAL)
     (dolist (clique-node clique-diagram)
       (dolist (component-node (clique-node-component-nodes clique-node))
	 (when  (not (member component-node diagram))
	   (error "Component node ~A of node ~A of the clique diagram is not a ~
                member of the associated belief net" component-node clique-node))))
     (values t))))
;-----------------------------

(defun make-new-node-table (diagram clique-diagram mode)
  (multiple-value-bind (new-diag diag-node-table)
      (make-partial-new-node-table diagram mode)
    (multiple-value-bind (new-clique-diag clique-diag-node-table)
	(make-partial-new-node-table clique-diagram mode)
      (values (nconc diag-node-table clique-diag-node-table) new-diag new-clique-diag))))

(defun make-partial-new-node-table (diagram mode)
  (let* ((extended-diagram (ecase mode
			     (:FOR-LOADING diagram)
			     ((:FOR-SAVING :NORMAL)(generate-diagram diagram))))
	 (diagram-nodes-and-labels (mapcar #'copy-node-and-labels extended-diagram))
	 (new-diagram (mapcar #'car diagram-nodes-and-labels)))
    (values new-diagram diagram-nodes-and-labels)))

(defun copy-node-and-labels (node)
  (let* ((new-node
	; This cond should be actually be an etypecase. However, the
	; CLIQUE-NODE type is defined only after this file is loaded
	; during a :Compile System and so if this is replaced by an
	; etypecase it leads to a compiler error (in Genera, at least).
	   (cond
	     ((clique-node-p node)(copy-clique-node node))
	     ((node-p node)(copy-node node))
	     (t (error "~A is neither a NODE nor a CLIQUE-NODE" node))))
	 (new-labels nil))
	; This line can be removed if there are no diagrams in the old format.
    (hack-for-old-format-diagrams node)
    ; Clique nodes have no state labels. So no need to try and keep them consistent.
    (when (not (clique-node-p node))
      (setq new-labels (mapcar #'copy-label (state-labels node)))
      (if *non-circular-copy*
	  (dolist (new-lab new-labels)
	    (setf (label-node new-lab)(make-node-ref :name (node-name new-node))))
	  (dolist (new-lab new-labels)
	    (setf (label-node new-lab) new-node))))
    (cons new-node new-labels)))

; In the old format the label-node field of the saved label structures
; was nil.  In the new format the label-node field is a node-ref to the
; node that owns the label. This hack will make sure that the fn
; copy-after-loading still works as expected. Will not handle
; deterministic chance nodes.

(defun hack-for-old-format-diagrams (node)
  (when *old-format-diagram*
    (dolist (old-lab (state-labels node))
      (setf (label-node old-lab) node))))

; The following three functions are used in-line by recursively-copy.
; They basically manipulate the new-node-table data structure.

(defun find-new-node-to-replace-node-ref (item new-node-table)
  (car (assoc (node-ref-name item) new-node-table :key #'node-name)))

(defun find-new-node-to-replace-node (item new-node-table)
  (car (assoc (node-name item) new-node-table :key #'node-name)))

(defun find-new-label-to-replace-label (label new-node-table)
  (let ((name-of-node-corresponding-to-label
	  (etypecase (label-node label)
	    (NODE-REF (node-ref-name (label-node label)))
	    (NODE (node-name (label-node label))))))
    (find (label-name label)
	  (cdr (assoc name-of-node-corresponding-to-label
		      new-node-table :key #'node-name)) :key #'label-name)))

(proclaim '(inline find-new-node-to-replace-node-ref
		   find-new-node-to-replace-node
		   find-new-label-to-replace-label))

(defun recursively-copy (item new-node-table &key (top-level-call nil))
  (etypecase item
    (NODE-REF (find-new-node-to-replace-node-ref item new-node-table))
    (NODE ; remember that clique-nodes are also nodes (CLtL page 313 Last para)
     (cond
       (top-level-call
	(recursive-ideal-structure-copy item new-node-table :dont-copy-top-level t))
       (*non-circular-copy* (make-node-ref :name (node-name item)))
       (t (or (find-new-node-to-replace-node item new-node-table)
	      (error "Encountered a node ~A which is not in new nodes and ~
                             labels list~A. Cant copy" item new-node-table)))))
    (LABEL (find-new-label-to-replace-label item new-node-table))
    (IDEAL-STRUCTURE (recursive-ideal-structure-copy item new-node-table))
    ; Structures that dont need to be copied are just replaced with nil
    ; in the copy. See doc of  *non-copiable-structure-types* in global-vars.lisp
    (NON-COPIABLE-STRUCTURE nil)
    (CONS (recursive-cons-copy item new-node-table))
    (STRING (recursive-string-copy item new-node-table))
    (ARRAY (recursive-array-copy item new-node-table))
    (NUMBER item)
    (SYMBOL item)))

(defun recursive-cons-copy (item new-node-table)
  (cond
    ((consp item)(cons (recursive-cons-copy (car item) new-node-table)
		       (recursive-cons-copy (cdr item) new-node-table)))
    (t (recursively-copy item new-node-table))))

; Not really recursive. This is just "string-copy", actually.

(defun recursive-string-copy (item  &optional new-node-table)
  (declare (ignore new-node-table)) 
  (format nil "~A" item))


; After all old diagrams have been converted, new-recursive-array-copy
; should become recursive-array-copy and old-recursive-array-copy should
; be trashed (14 Apr).

(defun recursive-array-copy (old-array new-node-table)
  (if *old-format-diagram*
      (old-recursive-array-copy old-array new-node-table)
      (new-recursive-array-copy old-array new-node-table)))

; This version works for only unidimensional arrays. This is the new
; version.

(defun new-recursive-array-copy (old-array new-node-table)
  (let* ((dimension (first (array-dimensions old-array)))
	(new-array (make-array dimension)))
    (dotimes (loc dimension new-array)
      (setf (aref new-array loc)
	    (recursively-copy (aref old-array loc) new-node-table)))))

; This needs to be around in case old diagrams have to loaded.

(defun old-recursive-array-copy (old-array new-node-table)
  (let ((new-array (make-array (array-dimensions old-array))))
    (for-each-location (loc new-array)
      (setf (apply #'aref (cons new-array loc))
	    (recursively-copy (apply #'aref (cons old-array loc)) new-node-table)))
    (values new-array)))


; Copying structures whose properties have been stored away using the
; macro STORE-IDEAL-STRUCT-INFO

(defun recursive-ideal-structure-copy (struct new-node-table &key dont-copy-top-level)
  (funcall (find-recursive-copier struct)
	   struct
	   new-node-table
	   :dont-copy-top-level-structure dont-copy-top-level))

(defun find-recursive-copier (struct)
  (let ((copier (get (type-of struct) 'RECURSIVE-COPIER)))
    (if (functionp copier) copier
	(error "Cant find a recursive copier for object ~A of type ~A.
               The plist of ~A contains ~A as the RECURSIVE COPIER property"
	       struct (type-of struct) (type-of struct) copier))))

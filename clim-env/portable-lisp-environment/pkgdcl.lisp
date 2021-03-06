;;; -*- Mode: Lisp; Syntax: ANSI-Common-Lisp; Package: CL-USER; Base: 10; Lowercase: Yes -*-

;;; Copyright (c) 1994-2000, Scott McKay.
;;; Copyright (c) 2001-2003, Scott McKay and Howard Shrobe.
;;; All rights reserved.  No warranty is expressed or implied.
;;; See COPYRIGHT for full copyright and terms of use.

(in-package #-ansi-90 :user #+ansi-90 :common-lisp-user)

;;; CLIM Environment package 
(defpackage clim-environment
  (:use clim-lisp aisl-clos clim)
  (:nicknames clim-env)
  #+Genera
  (:import-from "CLOS" "GENERIC-FUNCTION-NAME" "GENERIC-FUNCTION-LAMBDA-LIST"
		"SLOT-DEFINITION-INITARGS" "CLASS-DIRECT-SLOTS"
		"CLASS-DIRECT-DEFAULT-INITARGS" "SLOT-DEFINITION-INITFORM")
  #+Genera
  (:import-from "TIME" "PRINT-UNIVERSAL-TIME")

  (:SHADOW "YES-OR-NO-P" "Y-OR-N-P" "yes-or-no-p" "y-or-n-p")

  (:shadowing-import-from cl-user
			  method structure-object)

  (:shadowing-import-from pyrex
			  pixmap)

  (:shadowing-import-from clim-utils
			  #+Genera pattern
			  defun
			  flet labels
			  defgeneric defmethod
			  #+(and Allegro (or :rs6000 (not (version>= 4 1)))) with-slots
			  dynamic-extent 
			  #-(or Allegro Lucid Lispworks) non-dynamic-extent)

  (:export
   define-lisp-listener-command
   start-clim-environment
   shutdown-clim-environment
   ;; Used in debugger-hooks
   listener-restarts
   enter-debugger
   ))

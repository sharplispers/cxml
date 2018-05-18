(defpackage :cxml-system
  (:use :asdf :cl))
(in-package :cxml-system)

(defclass dummy-cxml-component () ())

(defmethod asdf:component-name ((c dummy-cxml-component))
  :cxml)

(progn
  (format t "~&;;; Checking for wide character support...")
  (force-output)
  (flet ((test (code)
           (and (< code char-code-limit) (code-char code))))
    (cond
      ((not (test 50000))
       (format t " no, reverting to octet strings.~%")
       #+rune-is-character
       (error "conflicting unicode configuration.  Please recompile.")
       (pushnew :rune-is-integer *features*))
      ((test 70000)
       (when (test #xD800)
         (format t " WARNING: Lisp implementation doesn't use UTF-16, ~
                     but accepts surrogate code points.~%"))
       (format t " yes, using code points.~%")
       #+(or rune-is-integer rune-is-utf-16)
       (error "conflicting unicode configuration.  Please recompile.")
       (pushnew :rune-is-character *features*))
      (t
       (format t " yes, using UTF-16.~%")
       #+(or rune-is-integer (and rune-is-character (not rune-is-utf-16)))
       (error "conflicting unicode configuration.  Please recompile.")
       (pushnew :rune-is-utf-16 *features*)
       (pushnew :rune-is-character *features*)))))

(defclass closure-source-file (cl-source-file) ())

#+scl
(pushnew 'uri-is-namestring *features*)

#+sbcl
(defmethod perform :around ((o compile-op) (s closure-source-file))
  ;; shut up already.  Correctness first.
  (handler-bind ((sb-ext:compiler-note #'muffle-warning))
    (let (#+sbcl (*compile-print* nil))
      (call-next-method))))

(asdf:defsystem :cxml-xml
  :default-component-class closure-source-file
  :pathname #+asdf2 "xml/"
            #-asdf2 (merge-pathnames
                     "xml/"
                     (make-pathname :name nil :type nil :defaults *load-truename*))
  :components
  ((:file "package")
   (:file "util"            :depends-on ("package"))
   (:file "sax-handler")
   (:file "xml-name-rune-p" :depends-on ("package" "util"))
   (:file "split-sequence"  :depends-on ("package"))
   (:file "xml-parse"       :depends-on ("package" "util" "sax-handler" "split-sequence" "xml-name-rune-p"))
   (:file "unparse"         :depends-on ("xml-parse"))
   (:file "xmls-compat"     :depends-on ("xml-parse"))
   (:file "recoder"         :depends-on ("xml-parse"))
   (:file "xmlns-normalizer" :depends-on ("xml-parse"))
   (:file "space-normalizer" :depends-on ("xml-parse"))
   (:file "catalog"         :depends-on ("xml-parse"))
   (:file "sax-proxy"       :depends-on ("xml-parse"))
   (:file "atdoc-configuration" :depends-on ("package")))
  :depends-on (:closure-common :puri #-scl :trivial-gray-streams))

(defclass utf8dom-file (closure-source-file) ((of)))

(defmethod output-files ((operation compile-op) (c utf8dom-file))
  (let* ((normal (car (call-next-method)))
         (name (concatenate 'string (pathname-name normal) "-utf8")))
    (list (make-pathname :name name :defaults normal))))

;; must be an extra method because of common-lisp-controller's :around method
(defmethod output-files :around ((operation compile-op) (c utf8dom-file))
  (let ((x (call-next-method)))
    (setf (slot-value c 'of) (car x))
    x))

(defmethod perform ((o load-op) (c utf8dom-file))
  (load (slot-value c 'of)))

(defmethod perform ((operation compile-op) (c utf8dom-file))
  (let ((*features* (cons 'utf8dom-file *features*))
        (*readtable*
         (symbol-value (find-symbol "*UTF8-RUNES-READTABLE*"
                                    :closure-common-system))))
    (call-next-method)))

(asdf:defsystem :cxml-dom
  :default-component-class closure-source-file
  :pathname #+asdf2 "dom/"
            #-asdf2 (merge-pathnames
                     "dom/"
                     (make-pathname :name nil :type nil :defaults *load-truename*))
  :components
  ((:file "package")
   (:file rune-impl :pathname "dom-impl" :depends-on ("package"))
   (:file rune-builder :pathname "dom-builder" :depends-on (rune-impl))
   #+rune-is-integer
   (utf8dom-file utf8-impl :pathname "dom-impl" :depends-on ("package"))
   #+rune-is-integer
   (utf8dom-file utf8-builder :pathname "dom-builder" :depends-on (utf8-impl))
   (:file "dom-sax"         :depends-on ("package")))
  :depends-on (:cxml-xml))

(asdf:defsystem :cxml-klacks
  :default-component-class closure-source-file
  :pathname #+asdf2 "klacks/"
            #-asdf2 (merge-pathnames
                     "klacks/"
                     (make-pathname :name nil :type nil :defaults *load-truename*))
    :serial t
    :components
    ((:file "package")
     (:file "klacks")
     (:file "klacks-impl")
     (:file "tap-source"))
    :depends-on (:cxml-xml))

(asdf:defsystem :cxml-test
  :default-component-class closure-source-file
  :pathname #+asdf2 "test/"
            #-asdf2 (merge-pathnames
                     "test/"
                     (make-pathname :name nil :type nil :defaults *load-truename*))
  :components ((:file "domtest") (:file "xmlconf"))
  :depends-on (:cxml-xml :cxml-klacks :cxml-dom))

(asdf:defsystem :cxml
  :components ()
  :depends-on (:cxml-dom :cxml-klacks #-allegro :cxml-test))

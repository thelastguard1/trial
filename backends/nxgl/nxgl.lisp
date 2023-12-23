(defpackage #:org.shirakumo.fraf.nxgl
  (:use #:cl)
  (:export
   #:nxgl
   #:init
   #:shutdown
   #:create-context
   #:destroy-context
   #:make-current
   #:swap-buffers
   #:swap-interval
   #:resize
   #:width
   #:height
   #:poll
   #:proc-address
   #:open-url
   #:username))

(in-package #:org.shirakumo.fraf.nxgl)

(cffi:define-foreign-library nxgl
    (T (:or "libnxgl.nro" "libnxgl")))

(cffi:defcstruct (event-handlers :conc-name NIL)
    (user-data :pointer)
  (focus-gain :pointer)
  (focus-lose :pointer)
  (resize :pointer)
  (quit :pointer)
  (mouse-move :pointer)
  (mouse-press :pointer)
  (mouse-release :pointer)
  (mouse-wheel :pointer)
  (key-press :pointer)
  (key-release :pointer))

(cffi:defcfun (init "nxgl_init") :void)

(cffi:defcfun (shutdown "nxgl_shutdown") :void)

(cffi:defcfun (%create-context "nxgl_create_context") :pointer
  (width :int)
  (height :int)
  (config-attributes :pointer)
  (context-attributes :pointer)
  (handlers :pointer))

(cffi:defcfun (destroy-context "nxgl_destroy_context") :void
  (context :pointer))

(cffi:defcfun (make-current "nxgl_make_current") :bool
  (context :pointer))

(cffi:defcfun (swap-buffers "nxgl_swap_buffers") :bool
  (context :pointer))

(cffi:defcfun (swap-interval "nxgl_swap_interval") :bool
  (context :pointer)
  (interval :int))

(cffi:defcfun (resize "nxgl_resize") :bool
  (context :pointer)
  (width :int)
  (height :int))

(cffi:defcfun (width "nxgl_width") :int
  (context :pointer))

(cffi:defcfun (width "nxgl_height") :int
  (context :pointer))

(cffi:defcfun (poll "nxgl_poll") :int
  (context :pointer))

(cffi:defcfun (proc-address "nxgl_get_proc_address") :pointer
  (name :string))

(cffi:defcfun (open-url "nxgl_open_url") :bool
  (url :string))

(cffi:defcfun (%username "nxgl_username") :bool
  (nick :pointer)
  (size :int))

(cffi:defcfun (set-thread-name "nxgl_set_thread_name") :int
  (thread :pointer)
  (name :string))

(defun username ()
  (cffi:with-foreign-object (nick :char 33)
    (when (%username nick 33)
      (cffi:foreign-string-to-lisp nick :max-chars 33))))

(defconstant EGL-DONT-CARE                     -1)
(defconstant EGL-TRUE                          1)
(defconstant EGL-FALSE                         0)
(defconstant EGL-NONE                          #x3038)
(defconstant EGL-ALPHA-SIZE                    #x3021)
(defconstant EGL-BLUE-SIZE                     #x3022)
(defconstant EGL-DEPTH-SIZE                    #x3025)
(defconstant EGL-GREEN-SIZE                    #x3023)
(defconstant EGL-RED-SIZE                      #x3024)
(defconstant EGL-CONTEXT-MAJOR-VERSION         #x3098)
(defconstant EGL-CONTEXT-MINOR-VERSION         #x30FB)
(defconstant EGL-CONTEXT-OPENGL-PROFILE-MASK   #x30FD)
(defconstant EGL-CONTEXT-OPENGL-CORE-PROFILE-BIT #x00000001)
(defconstant EGL-CONTEXT-OPENGL-COMPATIBILITY-PROFILE-BIT #x00000002)
(defconstant EGL-CONTEXT-OPENGL-DEBUG          #x31B0)
(defconstant EGL-CONTEXT-OPENGL-FORWARD-COMPATIBLE #x31B1)
(defconstant EGL-CONTEXT-OPENGL-ROBUST-ACCESS  #x31B2)
(defconstant EGL-OPENGL-API                    #x30A2)
(defconstant EGL-RENDERABLE-TYPE               #x3040)
(defconstant EGL-OPENGL-ES-BIT                 #x0001)
(defconstant EGL-OPENGL-BIT                    #x0008)

(defun create-context (width height
                       &key user-data focus-gain focus-lose resize quit mouse-move mouse-press mouse-release mouse-wheel key-press key-release
                            (alpha-size 8) (red-size 8) (green-size 8) (blue-size 8)
                            (context-version-major 3) (context-version-minor 3)
                            (opengl-profile :any) robustness forward-compat debug-context)
  (cffi:with-foreign-objects ((config-attributes :int 64)
                              (context-attributes :int 64)
                              (handlers '(:struct event-handlers)))
    (macrolet ((%set (&rest names)
                 `(setf ,@(loop for name in names
                                collect `(cffi:foreign-slot-value handlers '(:struct event-handlers) ,name)
                                collect `(or ,name (cffi:null-pointer))))))
      (%set user-data focus-gain focus-lose resize quit mouse-move mouse-press mouse-release mouse-wheel key-press key-release))
    (flet ((%set (list &rest args)
             (let ((i 0))
               (loop for (k v) on args by #'cddr
                     do (setf (cffi:mem-aref list :int (+ i 0)) k)
                        (setf (cffi:mem-aref list :int (+ i 1)) k)))
             (setf (cffi:mem-aref list :int (length args)) EGL-NONE)))
      (%set config-attributes
            EGL-RENDERABLE-TYPE EGL-OPENGL-BIT
            EGL-RED-SIZE red-size
            EGL-GREEN-SIZE green-size
            EGL-BLUE-SIZE blue-size
            EGL-ALPHA-SIZE alpha-size)
      (%set context-attributes
            EGL-CONTEXT-MAJOR-VERSION context-version-major
            EGL-CONTEXT-MINOR-VERSION context-version-minor
            EGL-CONTEXT-OPENGL-PROFILE-MASK (case opengl-profile
                                              (:compatibility
                                               EGL-CONTEXT-OPENGL-COMPATIBILITY-PROFILE-BIT)
                                              (:core
                                               EGL-CONTEXT-OPENGL-CORE-PROFILE-BIT)
                                              (T
                                               (logior EGL-CONTEXT-OPENGL-CORE-PROFILE-BIT
                                                       EGL-CONTEXT-OPENGL-COMPATIBILITY-PROFILE-BIT)))
            EGL-CONTEXT-OPENGL-DEBUG (if debug-context EGL-TRUE EGL-FALSE)
            EGL-CONTEXT-OPENGL-FORWARD-COMPATIBLE (if forward-compat EGL-TRUE EGL-FALSE)
            EGL-CONTEXT-OPENGL-ROBUST-ACCESS (if robustness EGL-TRUE EGL-FALSE)))
    (%create-context width height config-attributes context-attributes handlers)))

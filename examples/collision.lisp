(in-package #:org.shirakumo.fraf.trial.examples)

(define-shader-entity collision-body (vertex-entity colored-entity rigidbody listener)
  ((vertex-array :initform NIL)
   (color :initform (vec 0 0 1 0.5)))
  (:inhibit-shaders (colored-entity :fragment-shader)))

(defmethod shared-initialize :after ((body collision-body) slots &key primitive)
  (when primitive (setf (physics-primitive body) primitive)))

(defmethod physics-primitive ((body collision-body))
  (aref (physics-primitives body) 0))

(defmethod (setf physics-primitive) ((primitive primitive) (body collision-body))
  (setf (physics-primitives body) (vector primitive))
  (if (vertex-array body)
      (replace-vertex-data (vertex-array body) primitive)
      (setf (vertex-array body) (make-vertex-array primitive NIL))))

(define-handler (collision-body pre-tick) ()
  (start-frame collision-body))

(define-class-shader (collision-body :fragment-shader)
  "in vec3 v_view_position;
in vec3 v_world_position;
uniform vec4 objectcolor;
out vec4 color;

void main(){
  vec3 normal = cross(dFdx(v_view_position), dFdy(v_view_position));
  normal = normalize(normal * sign(normal.z));

  // Shitty phong diffuse lighting
  vec3 light_dir = normalize(vec3(0, 5, 0) - v_world_position);
  vec3 reflect_dir = reflect(-light_dir, normal);
  vec3 radiance = vec3(0.75) * (objectcolor.xyz * max(dot(normal, light_dir), 0));
  radiance += vec3(0.2) * objectcolor.xyz;
  color = vec4(radiance, objectcolor.w);
}")

(define-shader-entity collision-player (collision-body)
  ((hit :initform (make-hit) :accessor hit)
   (test-method :initform 'gjk :accessor test-method)))

(defun detect-hit* (method a b &optional (hit (make-hit)))
  (let ((array (make-array 1))
        (a (physics-primitive a))
        (b (physics-primitive b)))
    (declare (dynamic-extent array))
    (setf (aref array 0) hit)
    (let ((count (ecase method
                   (generic (detect-hits a b array 0 1))
                   (gjk (org.shirakumo.fraf.trial.gjk:detect-hits a b array 0 1))
                   (v-clip (org.shirakumo.fraf.trial.v-clip:detect-hits a b array 0 1)))))
      (when (< 0 count)
        hit))))

(define-handler (collision-player tick :after) (dt)
  (let ((spd (* 3.0 dt)))
    (cond ((retained :shift)
           (when (retained :a)
             (nq* (orientation collision-player) (qfrom-angle +vy3+ (+ spd))))
           (when (retained :d)
             (nq* (orientation collision-player) (qfrom-angle +vy3+ (- spd))))
           (when (retained :w)
             (nq* (orientation collision-player) (qfrom-angle +vx3+ (+ spd))))
           (when (retained :s)
             (nq* (orientation collision-player) (qfrom-angle +vx3+ (- spd))))
           (when (retained :c)
             (nq* (orientation collision-player) (qfrom-angle +vz3+ (+ spd))))
           (when (retained :space)
             (nq* (orientation collision-player) (qfrom-angle +vz3+ (- spd)))))
          (T
           (when (retained :a)
             (incf (vx (location collision-player)) (- spd)))
           (when (retained :d)
             (incf (vx (location collision-player)) (+ spd)))
           (when (retained :w)
             (incf (vz (location collision-player)) (- spd)))
           (when (retained :s)
             (incf (vz (location collision-player)) (+ spd)))
           (when (retained :c)
             (incf (vy (location collision-player)) (- spd)))
           (when (retained :space)
             (incf (vy (location collision-player)) (+ spd)))))
    (debug-clear)
    (setf (color collision-player) #.(vec 0 1 0 0.5))
    (let ((hit (detect-hit* (test-method collision-player) collision-player (node :a (container collision-player)) (hit collision-player))))
      (when hit
        (setf (color collision-player) #.(vec 1 0 0 0.5))
        (debug-line (hit-location hit) (v+* (hit-location hit) (hit-normal hit) 2)
                    :color-a #.(vec 0 0 0) :color-b #.(vec 0 1 0))))))

(define-example collision
  :title "Collision Detection"
  (enter (make-instance 'display-controller) scene)
  (enter (make-instance 'vertex-entity :vertex-array (// 'trial 'grid)) scene)
  (enter (make-instance 'collision-body :name :a :primitive (make-triangle)) scene)
  (enter (make-instance 'collision-player :name :b :primitive (make-triangle) :location (vec 0 0 +2.5)) scene)
  (enter (make-instance 'target-camera :location (vec3 0.0 8 9) :target (vec 0 0 0) :fov 50) scene)
  (observe! (hit-location (hit (node :b scene))) :title "Location")
  (observe! (hit-normal (hit (node :b scene))) :title "Normal")
  (observe! (hit-depth (hit (node :b scene))) :title "Depth")
  (enter (make-instance 'render-pass) scene))

(defmethod setup-ui ((scene collision-scene) panel)
  (let ((layout (make-instance 'alloy:grid-layout :col-sizes '(T 120 200) :row-sizes '(30)))
        (focus (make-instance 'alloy:vertical-focus-list)))
    (flet ((shapes ()
             (list (make-sphere)
                   (make-box)
                   (make-cylinder)
                   (make-pill)
                   (make-plane)
                   (make-half-space)
                   (make-triangle))))
      (alloy:enter "Shape A" layout :row 0 :col 1)
      (alloy:represent (physics-primitive (node :a scene)) 'alloy:combo-set
                       :value-set (shapes) :layout-parent layout :focus-parent focus)
      (alloy:enter "Shape B" layout :row 1 :col 1)
      (alloy:represent (physics-primitive (node :b scene)) 'alloy:combo-set
                       :value-set (shapes) :layout-parent layout :focus-parent focus)
      (alloy:enter "Method" layout :row 2 :col 1)
      (alloy:represent (test-method (node :b scene)) 'alloy:combo-set
                       :value-set '(generic gjk v-clip) :layout-parent layout :focus-parent focus)
      (alloy:finish-structure panel layout focus))))
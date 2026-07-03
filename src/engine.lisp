;;;; engine.lisp — the whole v0 pipeline: twin-set -> match payload.
;;;; Pure, deterministic, in-memory. See src/package.lisp for the contract
;;;; header and FINDINGS.md for the finding-code vocabulary.

(in-package :lovemotion)

;;; ---------------------------------------------------------------------
;;; Structs — mirror of the schema's semantics, not its tables
;;; ---------------------------------------------------------------------

(defstruct axis-value
  axis-id            ; keyword
  value              ; number | keyword | list of keywords (typed by axis)
  confidence         ; 0.0 - 1.0; must NEVER default silently to 1.0
  provenance         ; :observed | :self-reported | :inferred
  observed-at)       ; universal-time; append-only history lives in the DB

(defstruct twin
  id                                       ; opaque "tw_..." string, minted by HeyU
  (axis-values (make-hash-table :test #'eq)))

(defun axis (twin axis-id)
  "The axis-value struct for AXIS-ID on TWIN, or NIL if unobserved."
  (gethash axis-id (twin-axis-values twin)))

;;; ---------------------------------------------------------------------
;;; Config — the TimeWarp pattern: knobs live in data, not code
;;; ---------------------------------------------------------------------

(defparameter *default-config*
  '(:schema-version      1
    :work-ethic-floor    0.40
    :work-ethic-readmit  0.45   ; hysteresis: re-entry threshold (needs prior
                                ; run state to enforce; single-threshold in v0)
    :gate-min-confidence 0.70
    :ambition-floor      0.30
    :low-band-threshold  0.50
    :min-findings        1
    :max-findings        4))

(defun cfg (config key)
  (getf config key))

;;; ---------------------------------------------------------------------
;;; Axis registry — rules as data; the scoring dispatcher runs on this
;;; ---------------------------------------------------------------------

(defparameter *axes*
  '((:chronotype      :scoring :scalar       :weight 1.0)
    (:home-vs-outside :scoring :scalar       :weight 1.0)
    (:conflict-style  :scoring :matrix       :weight 1.5)
    (:attachment      :scoring :matrix       :weight 1.5)
    (:ambition        :scoring :scalar-floor :weight 1.0)
    (:humor           :scoring :tag-set      :weight 1.0)
    (:curiosity       :scoring :scalar       :weight 1.0))
  "The seven. Matrix axes carry extra weight pending evidence.
:cross stays in the dispatcher, unused, until an axis earns it.")

;;; ---------------------------------------------------------------------
;;; Matrices — literature-seeded v0, approved 2026-07-01
;;; Semantics: work estimates, not grades. High = low predictable
;;; maintenance. Cells may carry a finding annotation (code + severity).
;;; Immutable by rule: tuning = new version, never edit v0.
;;; ---------------------------------------------------------------------

(defparameter *conflict-order*
  '(:direct-loud :slow-burn :avoid-explode :calm-dissect))

(defparameter *attachment-order*
  '(:secure :anxious :avoidant :disorganized))

(defun canonical-pair (a b order)
  "Symmetric matrices store each unordered pair once, in ORDER's order."
  (if (<= (position a order) (position b order))
      (cons a b)
      (cons b a)))

(defparameter *conflict-matrix-v0*
  '(((:direct-loud   . :direct-loud)   . (:score 0.70))
    ((:direct-loud   . :slow-burn)     . (:score 0.30))
    ((:direct-loud   . :avoid-explode) . (:score 0.40))
    ((:direct-loud   . :calm-dissect)  . (:score 0.80 :finding :asymmetric-pairing
                                          :severity :watch))
    ((:slow-burn     . :slow-burn)     . (:score 0.20 :finding :quiet-cold-war
                                          :severity :attention))
    ((:slow-burn     . :avoid-explode) . (:score 0.20))
    ((:slow-burn     . :calm-dissect)  . (:score 0.60))
    ((:avoid-explode . :avoid-explode) . (:score 0.15 :finding :mutual-detonation
                                          :severity :structural))
    ((:avoid-explode . :calm-dissect)  . (:score 0.50))
    ((:calm-dissect  . :calm-dissect)  . (:score 0.90))))

(defparameter *attachment-matrix-v0*
  '(((:secure       . :secure)       . (:score 0.90))
    ((:secure       . :anxious)      . (:score 0.65))
    ((:secure       . :avoidant)     . (:score 0.60))
    ((:secure       . :disorganized) . (:score 0.45 :finding :stabilizer-load
                                        :severity :attention))
    ((:anxious      . :anxious)      . (:score 0.35))
    ((:anxious      . :avoidant)     . (:score 0.20 :finding :pursue-withdraw
                                        :severity :structural))
    ((:anxious      . :disorganized) . (:score 0.20))
    ((:avoidant     . :avoidant)     . (:score 0.30 :finding :intimacy-starved
                                        :severity :attention))
    ((:avoidant     . :disorganized) . (:score 0.25))
    ((:disorganized . :disorganized) . (:score 0.15 :finding :dual-disorganized
                                        :severity :structural))))

(defun matrix-for (axis-id)
  (ecase axis-id
    (:conflict-style (values *conflict-matrix-v0* *conflict-order*))
    (:attachment     (values *attachment-matrix-v0* *attachment-order*))))

(defun matrix-cell (axis-id a b)
  "Cell plist (:score s [:finding code :severity sev]) for values A, B."
  (multiple-value-bind (matrix order) (matrix-for axis-id)
    (let ((cell (assoc (canonical-pair a b order) matrix :test #'equal)))
      (unless cell
        (error "No ~a matrix cell for ~a x ~a" axis-id a b))
      (cdr cell))))

(defparameter *matrix-versions*
  '(:conflict-style 0 :attachment 0)
  "Stamped into every payload. Source: :literature-seeded-v0.")

;;; ---------------------------------------------------------------------
;;; Stage 1 — eligibility gate (pool construction)
;;; Computed fresh every run; never stored on the twin.
;;; ---------------------------------------------------------------------

(defun eligibility (twin config)
  "Three states. :unassessed is NOT :ineligible — never gate on noise."
  (let ((av (axis twin :work-ethic)))
    (cond ((or (null av)
               (< (axis-value-confidence av) (cfg config :gate-min-confidence)))
           :unassessed)
          ((< (axis-value-value av) (cfg config :work-ethic-floor))
           :ineligible)
          (t :eligible))))

;;; v0 product call: only :eligible twins enter the pool. Whether
;;; :unassessed twins match on partial data is an open product decision.

;;; ---------------------------------------------------------------------
;;; Stage 2 — pair dealbreakers
;;; Plain predicates over pairs. Any hit -> no match, no score.
;;; ---------------------------------------------------------------------

(defun axis-val (twin axis-id)
  (let ((av (axis twin axis-id)))
    (and av (axis-value-value av))))

(defparameter *substance-use-order*
  '(:none :social :regular)
  "Ordered by intensity. A boundary admits use up to a rank (below).")

(defparameter *substance-boundary-rank*
  '((:none-acceptable . 0)                 ; partner must be :none
    (:social-ok       . 1)                 ; up to :social
    (:no-limit        . 2))                ; anything
  "Max acceptable *substance-use* rank per boundary value.")

(defun substance-clash-p (user boundary-holder)
  "Does USER's :substance-use exceed BOUNDARY-HOLDER's stated boundary?
Missing data on either side never dealbreaks."
  (let ((use (axis-val user :substance-use))
        (boundary (axis-val boundary-holder :substance-boundary)))
    (and use boundary
         (> (position use *substance-use-order*)
            (cdr (assoc boundary *substance-boundary-rank*))))))

(defun sexual-limit-clash-p (requirer limiter)
  "Does REQUIRER need something on LIMITER's hard-limit list? Tags are
opaque to the engine — HeyU owns the vocabulary; this is set math only."
  (let ((requirements (axis-val requirer :sexual-requirements))
        (limits (axis-val limiter :sexual-limits)))
    (and requirements limits
         (intersection requirements limits))))

(defparameter *dealbreakers*
  (list
   ;; Family plans: hard yes vs hard no. :open collides with neither.
   (lambda (a b)
     (let ((pa (axis-val a :family-plans))
           (pb (axis-val b :family-plans)))
       (and pa pb
            (or (and (eq pa :yes) (eq pb :no))
                (and (eq pa :no)  (eq pb :yes))))))
   ;; Pet allergy vs must-have-pet, both directions.
   (lambda (a b)
     (or (and (axis-val a :pet-allergy) (axis-val b :must-have-pet))
         (and (axis-val b :pet-allergy) (axis-val a :must-have-pet))))
   ;; Substance use vs stated boundary, both directions.
   (lambda (a b)
     (or (substance-clash-p a b) (substance-clash-p b a)))
   ;; Sexual requirements vs hard limits, both directions.
   (lambda (a b)
     (or (sexual-limit-clash-p a b) (sexual-limit-clash-p b a)))))

(defun pair-compatible-p (a b)
  (notany (lambda (pred) (funcall pred a b)) *dealbreakers*))

;;; ---------------------------------------------------------------------
;;; Stage 3 — per-axis scoring dispatch
;;; ---------------------------------------------------------------------

(defun jaccard (set-a set-b)
  (let ((u (union set-a set-b)))
    (if (null u)
        0.0
        (float (/ (length (intersection set-a set-b))
                  (length u))))))

(defun score-axis (scoring axis-id a b config)
  "A and B are raw axis values (already unwrapped)."
  (ecase scoring
    (:scalar
     (- 1.0 (abs (- a b))))
    (:scalar-floor
     (let ((base (- 1.0 (abs (- a b)))))
       (if (< (min a b) (cfg config :ambition-floor))
           (* 0.5 base)                 ; penalized, not zeroed
           base)))
    (:matrix
     (getf (matrix-cell axis-id a b) :score))
    (:tag-set
     (jaccard a b))
    (:cross
     ;; Dormant. Value is (give . receive). Combine with MIN:
     ;; one starved direction is the failure mode; averaging hides it.
     (error ":cross has no live axis in v0"))))

;;; ---------------------------------------------------------------------
;;; Stage 4 — pair composite
;;; ---------------------------------------------------------------------

(defun score-pair (a b config)
  "Returns (values composite axis-scores-alist).
Axes missing on either twin are skipped: absent evidence contributes
nothing, in either direction. Confidence discounts the weight — the
engine leans hardest on what it knows best (the involuntary-channels
thesis, expressed as one multiply)."
  (let ((axis-scores '())
        (total 0.0)
        (weight-sum 0.0))
    (dolist (spec *axes*)
      (destructuring-bind (axis-id &key scoring (weight 1.0)) spec
        (let ((av-a (axis a axis-id))
              (av-b (axis b axis-id)))
          (when (and av-a av-b)
            (let ((s (score-axis scoring axis-id
                                 (axis-value-value av-a)
                                 (axis-value-value av-b)
                                 config))
                  (w (* weight (min (axis-value-confidence av-a)
                                    (axis-value-confidence av-b)))))
              (push (cons axis-id s) axis-scores)
              (incf total (* w s))
              (incf weight-sum w))))))
    (values (if (zerop weight-sum) 0.0 (/ total weight-sum))
            (nreverse axis-scores))))

;;; ---------------------------------------------------------------------
;;; Stage 5 — findings
;;; Total function: every match ships a maintenance schedule.
;;; Oil-change sticker, not recall notice.
;;; ---------------------------------------------------------------------

(defun severity-rank (severity)
  (ecase severity (:structural 3) (:attention 2) (:watch 1)))

(defun matrix-findings (a b axis-scores)
  "Cell-annotation findings: known dynamics of specific pairings,
independent of score."
  (loop for (axis-id . nil) in axis-scores
        when (member axis-id '(:conflict-style :attachment))
          append (let* ((cell (matrix-cell axis-id
                                           (axis-val a axis-id)
                                           (axis-val b axis-id)))
                        (code (getf cell :finding)))
                   (when code
                     (list (list :axis axis-id
                                 :code code
                                 :detail (list (axis-val a axis-id)
                                               (axis-val b axis-id))
                                 :severity (getf cell :severity)))))))

(defun low-band-findings (axis-scores config)
  "Any axis under the low band in an otherwise-accepted match."
  (loop for (axis-id . s) in axis-scores
        when (< s (cfg config :low-band-threshold))
          collect (list :axis axis-id
                        :code :low-band
                        :detail s
                        :severity :attention)))

(defun maintenance-findings (axis-scores)
  "Universal rule: the two RELATIVE weak points are the maintenance
schedule even when nothing is wrong. Guarantees a non-blank schedule."
  (loop for (axis-id . s) in (subseq (sort (copy-list axis-scores)
                                           #'< :key #'cdr)
                                     0 (min 2 (length axis-scores)))
        collect (list :axis axis-id
                      :code :maintenance
                      :detail s
                      :severity :watch)))

(defun generate-findings (a b axis-scores config)
  "Merge all rule outputs, one finding per axis (highest severity wins),
sort by severity desc then axis score asc, cap at :max-findings."
  (let* ((raw (append (matrix-findings a b axis-scores)
                      (low-band-findings axis-scores config)
                      (maintenance-findings axis-scores)))
         (per-axis '()))
    ;; Dedupe: keep the highest-severity finding per axis.
    (dolist (f raw)
      (let* ((axis-id (getf f :axis))
             (existing (assoc axis-id per-axis)))
        (if existing
            (when (> (severity-rank (getf f :severity))
                     (severity-rank (getf (cdr existing) :severity)))
              (setf (cdr existing) f))
            (push (cons axis-id f) per-axis))))
    (let ((merged (mapcar #'cdr per-axis)))
      (subseq (sort merged
                    (lambda (f g)
                      (let ((sf (severity-rank (getf f :severity)))
                            (sg (severity-rank (getf g :severity))))
                        (if (/= sf sg)
                            (> sf sg)
                            (< (or (cdr (assoc (getf f :axis) axis-scores)) 1.0)
                               (or (cdr (assoc (getf g :axis) axis-scores)) 1.0))))))
              0 (min (cfg config :max-findings) (length merged))))))

;;; ---------------------------------------------------------------------
;;; The pipeline — one pure function, twin-set -> payload
;;; ---------------------------------------------------------------------

(defun run-matching (twins &key (config *default-config*)
                                (run-id "run-local-0"))
  "Contract v1 payload as a plist. Serialization to MessagePack and the
Spaces courier are adapters; this s-expression IS the payload."
  (let* ((pool (remove-if-not (lambda (tw) (eq (eligibility tw config) :eligible))
                              twins))
         (matches '()))
    (loop for (a . rest) on pool
          do (loop for b in rest
                   when (pair-compatible-p a b)
                     do (multiple-value-bind (score axis-scores)
                            (score-pair a b config)
                          ;; Canonical pair order at the single write site.
                          ;; No triggers, no magic: one string<.
                          (let* ((swap (string> (twin-id a) (twin-id b)))
                                 (ta (if swap b a))
                                 (tb (if swap a b)))
                            (push (list :twin-a (twin-id ta)
                                        :twin-b (twin-id tb)
                                        :score score
                                        :findings (generate-findings
                                                   a b axis-scores config))
                                  matches)))))
    (list :contract-version 1
          :run-id run-id
          :matrix-versions *matrix-versions*
          :pool-size (length pool)
          :matches (sort matches #'> :key (lambda (m) (getf m :score))))))

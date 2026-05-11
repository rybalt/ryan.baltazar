;;; rb-org-todos.el --- Org-mode TODO keyword sequences -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Design Question (DQ_) keyword sequence for AI-assisted research documents.
;; Used by Claude to track design decisions in org-mode files.
;;
;; States:
;;   DQ_OPEN    — question is unresolved (active)
;;   DQ_LEANING — recommendation exists, awaiting sign-off (active)
;;   DQ_SETTLED — decision made (done, auto-timestamped)
;;   DQ_DROPPED — question abandoned or superseded (done, auto-timestamped)
;;
;; Structure rules (for Claude):
;;   - Set :claude: tag on the parent heading; children inherit it for
;;     agenda filtering (e.g. C-c a m +claude, or /DQ_OPEN+claude).
;;   - Do NOT emit #+TODO: lines in files — keywords are configured here.
;;   - Property drawers:
;;       :SEVERITY:       — low, medium, or high (when assigned)
;;       :RECOMMENDATION: — short label on DQ_LEANING items; prose rationale
;;                          goes in the body text
;;   - Org auto-records an inactive timestamp on DQ_SETTLED / DQ_DROPPED
;;     transitions via the (!) logging suffix.
;;
;; Example:
;;   * Design Questions                                       :claude:
;;   ** DQ_OPEN Notification model for SetExtendedData
;;      :PROPERTIES:
;;      :SEVERITY: low
;;      :END:
;;      Passive vs active event dispatch.
;;
;;   ** DQ_LEANING First-party discoverability
;;      :PROPERTIES:
;;      :SEVERITY: low
;;      :RECOMMENDATION: Named convenience methods
;;      :END:
;;      Named convenience methods delegating to the generic API.
;;
;;   ** DQ_SETTLED Stale data invalidation
;;      :PROPERTIES:
;;      :SEVERITY: medium
;;      :END:
;;      - State "DQ_SETTLED" from "DQ_LEANING" [2026-03-25 Tue]
;;      Feature-owned invalidation via BeforeLocateHands.

;;; Code:

(use-package org
  :custom
  (org-todo-keywords
   '((sequence "TODO" "IN_PROGRESS" "|" "DONE" "CANCELLED")
     (sequence "DQ_OPEN" "DQ_LEANING" "|" "DQ_SETTLED(!)" "DQ_DROPPED(!)"))))

(provide 'rb-org-todos)
;;; rb-org-todos.el ends here

;;; rb-prose.el --- Prose prettification for org and markdown  -*- lexical-binding: t; -*-

;; Applies mixed variable-pitch/fixed-pitch fonts, olivetti centering,
;; org-modern glyphs, and scaled headings to org-mode and markdown buffers.
;;
;; Activated via `rb-prose-mode', hooked onto both modes automatically.
;;
;; Requires Source Serif Pro font (brew install --cask font-source-serif-4).

;;; Code:

(declare-function mixed-pitch-mode "mixed-pitch")
(declare-function olivetti-mode "olivetti")
(declare-function org-appear-mode "org-appear")
(declare-function org-appear-manual-start "org-appear")
(declare-function org-appear-manual-stop "org-appear")

;; ── Variable-pitch face ──────────────────────────────────────────────────────

;; mixed-pitch-mode only copies :family from variable-pitch, not :height.
;; We set the family here and remap the height separately in rb-prose--enable.
(set-face-attribute 'variable-pitch nil
                    :family "Source Serif 4")

(defvar rb-prose-height 170
  "Height for prose body text in 1/10pt (e.g. 185 = 18.5pt).
Applied as a buffer-local face remap since mixed-pitch ignores
the variable-pitch :height attribute.")

;; ── rb-prose-mode ────────────────────────────────────────────────────────────

(defvar-local rb-prose--height-cookie nil
  "Cookie for the prose height face remap.")

(defvar-local rb-prose--fixed-cookies nil
  "Cookies for pinning code faces back to the original height.")

(defun rb-prose--enable ()
  "Enable prose prettification modes."
  (let ((mono-height (face-attribute 'default :height)))
    (mixed-pitch-mode 1)
    (setq rb-prose--height-cookie
          (face-remap-add-relative 'default :height rb-prose-height))
    ;; Pin all fixed-pitch faces (org-block, org-table, org-code, etc.)
    ;; plus block delimiter faces back to the original monospace height.
    (setq rb-prose--fixed-cookies
          (mapcar (lambda (face)
                    (face-remap-add-relative face :height mono-height))
                  (append mixed-pitch-fixed-pitch-faces
                          '(org-block-begin-line org-block-end-line)))))
  (olivetti-mode 1)
  (visual-line-mode 1)
  (display-line-numbers-mode -1))

(defun rb-prose--disable ()
  "Disable prose prettification modes."
  (when rb-prose--height-cookie
    (face-remap-remove-relative rb-prose--height-cookie)
    (setq rb-prose--height-cookie nil))
  (dolist (cookie rb-prose--fixed-cookies)
    (face-remap-remove-relative cookie))
  (setq rb-prose--fixed-cookies nil)
  (mixed-pitch-mode -1)
  (olivetti-mode -1)
  (display-line-numbers-mode 1))

(define-minor-mode rb-prose-mode
  "Minor mode for prose buffer prettification.
Enables mixed-pitch fonts (Source Serif body, FiraMono code),
olivetti centering at 90 columns, visual line wrapping, and
disables line number display."
  :lighter nil
  (if rb-prose-mode
      (rb-prose--enable)
    (rb-prose--disable)))

;; ── Org configuration ────────────────────────────────────────────────────────

(use-package org
  :custom
  (org-hide-emphasis-markers t)
  (org-link-descriptive t)
  (org-pretty-entities t)
  :hook
  (org-mode . rb-prose-mode)
  (org-mode . org-indent-mode))

(with-eval-after-load 'org
  (dolist (spec '((org-level-1 . 1.3)
                  (org-level-2 . 1.2)
                  (org-level-3 . 1.1)
                  (org-level-4 . 1.0)))
    (set-face-attribute (car spec) nil
                        :height (cdr spec)
                        :weight 'semi-bold)))

;; ── org-modern ───────────────────────────────────────────────────────────────

(use-package org-modern
  :ensure t
  :after org
  :custom
  (org-modern-star '("◉" "○" "◈" "◇" "✦"))
  (org-modern-checkbox '((?X . "☑") (?- . "◐") (?\s . "☐")))
  (org-modern-priority t)
  (org-modern-tag t)
  (org-modern-timestamp t)
  (org-modern-table t)
  (org-modern-todo t)
  (org-modern-keyword t)
  ;; Show full #+begin_src / #+end_src so they're directly editable
  (org-modern-block-name nil)
  ;; Disabled: conflicts with org-indent-mode
  (org-modern-block-fringe nil)
  :hook
  (org-mode . org-modern-mode))

;; ── org-appear ───────────────────────────────────────────────────────────────

(use-package org-appear
  :ensure t
  :after org
  :custom
  (org-appear-autoemphasis t)
  (org-appear-autolinks t)
  (org-appear-autosubmarkers t)
  (org-appear-trigger 'manual)
  :hook
  (org-mode . org-appear-mode)
  (org-mode . (lambda ()
                (add-hook 'evil-insert-state-entry-hook
                          #'org-appear-manual-start nil t)
                (add-hook 'evil-insert-state-exit-hook
                          #'org-appear-manual-stop nil t))))

;; ── mixed-pitch ──────────────────────────────────────────────────────────────

(use-package mixed-pitch
  :ensure t
  :config
  (dolist (face '(org-modern-label
                  org-modern-tag
                  org-modern-todo
                  org-modern-done
                  org-modern-priority
                  org-modern-date-active
                  org-modern-date-inactive
                  org-modern-time-active
                  org-modern-time-inactive
                  org-modern-statistics
                  org-modern-horizontal-rule))
    (add-to-list 'mixed-pitch-fixed-pitch-faces face)))

;; ── olivetti ─────────────────────────────────────────────────────────────────

(use-package olivetti
  :ensure t
  :custom
  (olivetti-body-width 90))

;; ── Markdown configuration ───────────────────────────────────────────────────

;; Remove line-numbers hook added in post-init.el; rb-prose-mode handles this.
(remove-hook 'markdown-mode-hook #'display-line-numbers-mode)

(with-eval-after-load 'markdown-mode
  (add-hook 'markdown-mode-hook #'rb-prose-mode)

  (setq markdown-header-scaling t
        markdown-header-scaling-values '(1.3 1.2 1.1 1.0 1.0 1.0))

  (set-face-attribute 'markdown-header-face nil :weight 'semi-bold)
  (set-face-attribute 'markdown-header-face-1 nil :weight 'bold)

  (setq markdown-list-item-bullets '("•" "◦" "▸")))

(provide 'rb-prose)
;;; rb-prose.el ends here

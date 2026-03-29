;;; rb-buffers.el --- MRU buffer list side panel  -*- lexical-binding: t; -*-

;; Displays a live-updating list of open buffers above treemacs.
;; Toggle with SPC t t (via rb-toggle-navigator).

;;; Code:

(require 'nerd-icons)

(declare-function treemacs-current-visibility "treemacs-scope")
(declare-function treemacs-get-local-window "treemacs-scope")
(declare-function treemacs "treemacs")
(declare-function evil-set-initial-state "evil-core")
(declare-function evil-define-key "evil-core")

;; ── Constants ─────────────────────────────────────────────────────────────────

(defconst rb-buffers--buffer-name "*rb-buffers*"
  "Name of the MRU buffer list panel buffer.")

(defconst rb-buffers--side-slot -2
  "Side window slot.  Treemacs uses -1/0; -2 sits above it.")

(defconst rb-buffers--window-height 0.20
  "Height of the buffer panel as a fraction of frame height.")

(defvar rb-buffers--refresh-timer nil
  "Idle timer for debounced refresh.")

;; ── Buffer filtering ──────────────────────────────────────────────────────────

(defun rb-buffers--useful-special-p (buf)
  "Return non-nil if BUF is a named special buffer worth showing."
  (with-current-buffer buf
    (or (derived-mode-p 'eat-mode
                        'inferior-emacs-lisp-mode
                        'shell-mode
                        'term-mode
                        'vterm-mode
                        'eshell-mode
                        'comint-mode)
        (member (buffer-name buf) '("*scratch*" "*Messages*" "*ielm*")))))

(defun rb-buffers--include-p (buf)
  "Return non-nil if BUF should appear in the panel."
  (let ((name (buffer-name buf)))
    (and
     (not (string-prefix-p " " name))
     (not (string= name rb-buffers--buffer-name))
     (not (string-prefix-p "Treemacs" name))
     (not (string-prefix-p "*Treemacs" name))
     (not (minibufferp buf))
     (or (buffer-file-name buf)
         (rb-buffers--useful-special-p buf)))))

;; ── Display names ─────────────────────────────────────────────────────────────

(defun rb-buffers--display-name (buf all-bufs)
  "Return the display name for BUF, disambiguating against ALL-BUFS.
File buffers show their basename; when two share the same basename,
append <parent-dir> to each."
  (let* ((file (buffer-file-name buf))
         (basename (if file
                       (file-name-nondirectory file)
                     (buffer-name buf))))
    (if (and file
             (cl-some (lambda (other)
                        (and (not (eq other buf))
                             (buffer-file-name other)
                             (string= basename
                                      (file-name-nondirectory
                                       (buffer-file-name other)))))
                      all-bufs))
        (let ((parent (file-name-nondirectory
                       (directory-file-name
                        (file-name-directory file)))))
          (format "%s<%s>" basename parent))
      basename)))

;; ── Rendering ─────────────────────────────────────────────────────────────────

(defun rb-buffers--main-window ()
  "Return the most recently used non-side editing window."
  (get-mru-window nil nil t
                  (lambda (w)
                    (not (window-parameter w 'window-side)))))

(defun rb-buffers--visit-buffer (buf &optional _event)
  "Switch to BUF in the main editing window."
  (when (buffer-live-p buf)
    (let ((win (or (rb-buffers--main-window) (next-window))))
      (select-window win)
      (switch-to-buffer buf))))

(defun rb-buffers--insert-entry (buf all-bufs)
  "Insert one line for BUF into the current buffer."
  (let* ((file (buffer-file-name buf))
         (name (rb-buffers--display-name buf all-bufs))
         (modified (and (buffer-modified-p buf)
                        (not (buffer-base-buffer buf))))
         (icon (if file
                   (nerd-icons-icon-for-file (file-name-nondirectory file))
                 (with-current-buffer buf
                   (nerd-icons-icon-for-mode major-mode))))
         (mod-indicator (if modified
                            (propertize "\u25cf" 'face '(:foreground "#e06c75"))
                          " "))
         (target-buf buf)
         (line-map (let ((m (make-sparse-keymap)))
                     (define-key m [mouse-1]
                       (lambda (_event)
                         (interactive "e")
                         (rb-buffers--visit-buffer target-buf)))
                     m)))
    (insert (propertize
             (concat " " (or icon " ") " " mod-indicator " " name)
             'mouse-face 'highlight
             'rb-buffers-target buf
             'keymap line-map
             'help-echo (or file (buffer-name buf)))
            "\n")))

(defun rb-buffers--render ()
  "Render the buffer list into the panel buffer."
  (let ((panel-buf (get-buffer rb-buffers--buffer-name)))
    (when (buffer-live-p panel-buf)
      (with-current-buffer panel-buf
        (let ((inhibit-read-only t)
              (pos (point))
              (all-bufs (cl-remove-if-not #'rb-buffers--include-p
                                          (buffer-list))))
          (erase-buffer)
          (dolist (buf all-bufs)
            (rb-buffers--insert-entry buf all-bufs))
          ;; remove trailing newline
          (when (> (point-max) (point-min))
            (goto-char (point-max))
            (delete-char -1))
          ;; restore cursor position
          (goto-char (min pos (point-max))))))))

;; ── Major mode ────────────────────────────────────────────────────────────────

(defvar rb-buffers-mode-map
  (let ((m (make-sparse-keymap)))
    (define-key m (kbd "RET")
      (lambda ()
        (interactive)
        (when-let* ((buf (get-text-property (point) 'rb-buffers-target)))
          (rb-buffers--visit-buffer buf))))
    (define-key m (kbd "j") #'next-line)
    (define-key m (kbd "k") #'previous-line)
    m)
  "Keymap for `rb-buffers-mode'.")

(define-derived-mode rb-buffers-mode special-mode "RbBuffers"
  "Major mode for the MRU buffer list side panel."
  (setq-local buffer-read-only t
              truncate-lines t
              cursor-type nil
              mode-line-format nil
              header-line-format
              (propertize " Buffers" 'face 'bold)))

(with-eval-after-load 'evil
  (evil-set-initial-state 'rb-buffers-mode 'motion)
  (evil-define-key 'motion rb-buffers-mode-map
    (kbd "j")   #'next-line
    (kbd "k")   #'previous-line
    (kbd "RET") (lambda ()
                  (interactive)
                  (when-let* ((buf (get-text-property (point) 'rb-buffers-target)))
                    (rb-buffers--visit-buffer buf)))
    (kbd "q")   #'rb-toggle-navigator))

;; ── Window management ─────────────────────────────────────────────────────────

(defun rb-buffers--get-or-create-buffer ()
  "Return the panel buffer, creating it if necessary."
  (or (get-buffer rb-buffers--buffer-name)
      (with-current-buffer (get-buffer-create rb-buffers--buffer-name)
        (rb-buffers-mode)
        (current-buffer))))

(defun rb-buffers--show ()
  "Display the buffer panel in the left side column above treemacs."
  (let ((buf (rb-buffers--get-or-create-buffer)))
    (rb-buffers--render)
    (display-buffer
     buf
     `(display-buffer-in-side-window
       . ((side          . left)
          (slot          . ,rb-buffers--side-slot)
          (window-height . ,rb-buffers--window-height)
          (dedicated     . t)
          (preserve-size . (t . nil)))))))

(defun rb-buffers--hide ()
  "Remove the buffer panel window if visible."
  (when-let* ((win (get-buffer-window rb-buffers--buffer-name)))
    (delete-window win)))

(defun rb-buffers--visible-p ()
  "Return non-nil if the buffer panel is currently displayed."
  (get-buffer-window rb-buffers--buffer-name))

;; ── Auto-refresh ──────────────────────────────────────────────────────────────

(defun rb-buffers--schedule-refresh ()
  "Schedule a debounced refresh of the buffer panel."
  (when (rb-buffers--visible-p)
    (when (timerp rb-buffers--refresh-timer)
      (cancel-timer rb-buffers--refresh-timer))
    (setq rb-buffers--refresh-timer
          (run-with-idle-timer 0.05 nil #'rb-buffers--render))))

(defun rb-buffers--setup-hooks ()
  "Install hooks for auto-refresh."
  (add-hook 'buffer-list-update-hook #'rb-buffers--schedule-refresh))

(defun rb-buffers--teardown-hooks ()
  "Remove auto-refresh hooks."
  (remove-hook 'buffer-list-update-hook #'rb-buffers--schedule-refresh)
  (when (timerp rb-buffers--refresh-timer)
    (cancel-timer rb-buffers--refresh-timer)
    (setq rb-buffers--refresh-timer nil)))

;; ── Toggle command ────────────────────────────────────────────────────────────

(defun rb-toggle-navigator ()
  "Toggle the treemacs + MRU buffer panel navigator."
  (interactive)
  (require 'treemacs)
  (pcase (treemacs-current-visibility)
    ('visible
     (rb-buffers--hide)
     (rb-buffers--teardown-hooks)
     (delete-window (treemacs-get-local-window)))
    (_
     (treemacs)
     (rb-buffers--show)
     (rb-buffers--setup-hooks))))

;; ── Leader key ────────────────────────────────────────────────────────────────

(with-eval-after-load 'evil-leader
  (evil-leader/set-key "t t" #'rb-toggle-navigator))

(provide 'rb-buffers)
;;; rb-buffers.el ends here

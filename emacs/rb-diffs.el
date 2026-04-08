;;; rb-diffs.el --- Git diff navigator panel  -*- lexical-binding: t; -*-

;; Displays changed files across all repos under the treemacs project root.
;; Organized by repo, then staged/unstaged/untracked.
;; Toggle with SPC t t (via rb-toggle-navigator in rb-buffers.el).

;;; Code:

(require 'nerd-icons)
(require 'xdg)
(require 'pfuture)

(declare-function diff-hl-next-hunk "diff-hl")
(declare-function diff-hl-update "diff-hl")
(declare-function evil-set-initial-state "evil-core")
(declare-function evil-define-key "evil-core")
(declare-function rb-toggle-navigator "rb-buffers")
(declare-function rb-workspace-root "rb-setup")

;; ── Constants & customization ────────────────────────────────────────────────

(defconst rb-diffs--buffer-name "*rb-diffs*"
  "Name of the diff navigator panel buffer.")

(defconst rb-diffs--side-slot -2
  "Side window slot.  Treemacs uses -1/0; -2 sits between buffers and treemacs.")

(defconst rb-diffs--max-height 0.40
  "Maximum height of the diff panel as a fraction of frame height.")

(defconst rb-diffs--min-height 3
  "Minimum window height in lines.")

(defcustom rb-diffs-exclude-repos nil
  "List of directory basenames to exclude from repo discovery."
  :type '(repeat string)
  :group 'rb-diffs)

(defvar rb-diffs--refresh-timer nil
  "Idle timer for debounced refresh.")

(defconst rb-diffs--script-path
  (expand-file-name "rb-diffs-status.py"
                    (expand-file-name "rybalt/emacs" (xdg-config-home)))
  "Absolute path to the rb-diffs-status.py helper script.")

(defvar rb-diffs--pending-process nil
  "In-flight pfuture process for async refresh, or nil.")

;; ── Repo discovery ───────────────────────────────────────────────────────────

(defun rb-diffs--discover-repos ()
  "Return alist of (LABEL . TOPLEVEL) for git repos under project root.
LABEL is the directory basename; TOPLEVEL is the resolved git root.
Repos whose basename appears in `rb-diffs-exclude-repos' are omitted.
Uses `rb-workspace-root' (function) as the project root."
  (when-let* ((root (rb-workspace-root)))
    (let ((seen (make-hash-table :test 'equal))
          result)
      ;; Check if the project root itself is a repo
      (when-let* ((toplevel (rb-diffs--git-toplevel root)))
        (puthash toplevel t seen)
        (push (cons (file-name-nondirectory (directory-file-name root))
                    toplevel)
              result))
      ;; Check top-level subdirectories
      (dolist (entry (directory-files root t "^[^.]" t))
        (when (file-directory-p entry)
          (let ((label (file-name-nondirectory entry)))
            (unless (member label rb-diffs-exclude-repos)
              (when-let* ((toplevel (rb-diffs--git-toplevel entry)))
                (unless (gethash toplevel seen)
                  (puthash toplevel t seen)
                  (push (cons label toplevel) result)))))))
      (nreverse result))))

(defun rb-diffs--git-toplevel (dir)
  "Return the git toplevel for DIR, or nil if not in a repo."
  (let ((default-directory (file-name-as-directory dir)))
    (with-temp-buffer
      (when (zerop (call-process "git" nil t nil
                                 "rev-parse" "--show-toplevel"))
        (string-trim (buffer-string))))))

;; ── Async status collection ──────────────────────────────────────────────────

(defun rb-diffs--cancel-pending ()
  "Kill any in-flight async refresh process."
  (when (process-live-p rb-diffs--pending-process)
    (delete-process rb-diffs--pending-process))
  (setq rb-diffs--pending-process nil))

(defun rb-diffs--candidate-dirs ()
  "Return list of candidate directory paths for the status script.
Includes the workspace root and each non-excluded top-level subdirectory."
  (when-let* ((root (rb-workspace-root)))
    (let ((candidates (list root)))
      (dolist (entry (directory-files root t "^[^.]" t))
        (when (and (file-directory-p entry)
                   (not (member (file-name-nondirectory entry)
                                rb-diffs-exclude-repos)))
          (push entry candidates)))
      (nreverse candidates))))

(defun rb-diffs--refresh-async ()
  "Asynchronously refresh the diff panel via the status script."
  (when-let* ((candidates (rb-diffs--candidate-dirs)))
    (rb-diffs--cancel-pending)
    (let ((buf-name rb-diffs--buffer-name))
      (setq rb-diffs--pending-process
            (pfuture-callback `("python3" ,rb-diffs--script-path ,@candidates)
              :directory (rb-workspace-root)
              :on-success
              (when (buffer-live-p (get-buffer buf-name))
                (condition-case err
                    (let ((data (read (pfuture-callback-output))))
                      (rb-diffs--render-from-data data)
                      (rb-diffs--fit-window))
                  (error (message "rb-diffs: parse error: %s" err))))
              :on-error
              (message "rb-diffs: status script failed (exit %s)"
                       (process-exit-status process)))))))

;; ── Rendering ────────────────────────────────────────────────────────────────

(defun rb-diffs--main-window ()
  "Return the most recently used non-side editing window."
  (get-mru-window nil nil t
                  (lambda (w)
                    (not (window-parameter w 'window-side)))))

(defun rb-diffs--visit-file-at-point ()
  "Open the file at point in the main window, jumping to first hunk if tracked."
  (interactive)
  (when-let* ((file (get-text-property (point) 'rb-diffs-file))
              (status (get-text-property (point) 'rb-diffs-status)))
    (let ((win (or (rb-diffs--main-window) (next-window))))
      (select-window win)
      (find-file file)
      (when (memq status '(staged unstaged))
        (goto-char (point-min))
        (ignore-errors (diff-hl-next-hunk))))))

(defun rb-diffs--insert-section (label files toplevel status)
  "Insert a section with LABEL for FILES from TOPLEVEL with STATUS symbol."
  (when files
    (insert (propertize (concat "  " label) 'face 'font-lock-comment-face) "\n")
    (dolist (file files)
      (let* ((abs-path (expand-file-name file toplevel))
             (icon (nerd-icons-icon-for-file (file-name-nondirectory file)))
             (line-map (let ((m (make-sparse-keymap))
                             (f abs-path))
                         (define-key m [mouse-1]
                           (lambda (_event)
                             (interactive "e")
                             (let ((win (or (rb-diffs--main-window)
                                            (next-window))))
                               (select-window win)
                               (find-file f))))
                         m)))
        (insert (propertize
                 (concat " " (or icon " ") " "
                         (file-name-nondirectory file))
                   'mouse-face 'highlight
                   'rb-diffs-file abs-path
                   'rb-diffs-repo toplevel
                   'rb-diffs-status status
                 'keymap line-map
                 'help-echo file)
                "\n")))))

(defun rb-diffs--render-from-data (data)
  "Render diff panel from DATA returned by the status script.
DATA is a list of (LABEL TOPLEVEL PLIST) elements."
  (let ((panel-buf (get-buffer rb-diffs--buffer-name)))
    (when (buffer-live-p panel-buf)
      (with-current-buffer panel-buf
        (let ((inhibit-read-only t)
              (pos (point)))
          (erase-buffer)
          (dolist (entry data)
            (let* ((label     (nth 0 entry))
                   (toplevel  (nth 1 entry))
                   (plist     (nth 2 entry))
                   (staged    (plist-get plist :staged))
                   (unstaged  (plist-get plist :unstaged))
                   (untracked (plist-get plist :untracked)))
              (when (or staged unstaged untracked)
                (insert (propertize (concat " " label)
                                   'face 'bold)
                        "\n")
                (rb-diffs--insert-section "Staged" staged toplevel 'staged)
                (rb-diffs--insert-section "Unstaged" unstaged toplevel 'unstaged)
                (rb-diffs--insert-section "Untracked" untracked toplevel 'untracked))))
          (when (> (point-max) (point-min))
            (goto-char (point-max))
            (delete-char -1))
          (goto-char (min pos (point-max))))))))

;; ── Stage / unstage ──────────────────────────────────────────────────────────

(defun rb-diffs--stage-file ()
  "Stage the file at point."
  (interactive)
  (when-let* ((file (get-text-property (point) 'rb-diffs-file))
              (repo (get-text-property (point) 'rb-diffs-repo)))
    (let ((rel (file-relative-name file repo)))
      (call-process "git" nil nil nil "-C" repo "add" "--" rel))
    (rb-diffs--refresh-and-update file)))

(defun rb-diffs--unstage-file ()
  "Unstage the file at point."
  (interactive)
  (when-let* ((file (get-text-property (point) 'rb-diffs-file))
              (repo (get-text-property (point) 'rb-diffs-repo)))
    (let ((rel (file-relative-name file repo)))
      (call-process "git" nil nil nil "-C" repo "reset" "HEAD" "--" rel))
    (rb-diffs--refresh-and-update file)))

(defun rb-diffs--refresh-and-update (file)
  "Re-render the diff panel and update diff-hl for FILE if it's in a buffer."
  (rb-diffs--refresh-async)
  (when-let* ((buf (find-buffer-visiting file)))
    (with-current-buffer buf
      (ignore-errors (diff-hl-update)))))

;; ── Major mode ───────────────────────────────────────────────────────────────

(defvar rb-diffs-mode-map
  (let ((m (make-sparse-keymap)))
    (define-key m (kbd "RET") #'rb-diffs--visit-file-at-point)
    (define-key m (kbd "j") #'next-line)
    (define-key m (kbd "k") #'previous-line)
    (define-key m (kbd "s") #'rb-diffs--stage-file)
    (define-key m (kbd "u") #'rb-diffs--unstage-file)
    m)
  "Keymap for `rb-diffs-mode'.")

(define-derived-mode rb-diffs-mode special-mode "RbDiffs"
  "Major mode for the git diff navigator panel."
  (setq-local buffer-read-only t
              truncate-lines t
              cursor-type nil
              mode-line-format nil
              header-line-format
              (propertize " Diffs" 'face 'bold)))

(with-eval-after-load 'evil
  (evil-set-initial-state 'rb-diffs-mode 'motion)
  (evil-define-key 'motion rb-diffs-mode-map
    (kbd "j")   #'next-line
    (kbd "k")   #'previous-line
    (kbd "RET") #'rb-diffs--visit-file-at-point
    (kbd "s")   #'rb-diffs--stage-file
    (kbd "u")   #'rb-diffs--unstage-file
    (kbd "gr")  #'rb-diffs-refresh
    (kbd "q")   #'rb-toggle-navigator))

;; ── Window management ────────────────────────────────────────────────────────

(defun rb-diffs--get-or-create-buffer ()
  "Return the diff panel buffer, creating it if necessary."
  (or (get-buffer rb-diffs--buffer-name)
      (with-current-buffer (get-buffer-create rb-diffs--buffer-name)
        (rb-diffs-mode)
        (current-buffer))))

(defun rb-diffs--content-height ()
  "Return the desired window height in lines based on content."
  (let ((buf (get-buffer rb-diffs--buffer-name)))
    (if (and buf (buffer-live-p buf))
        (max rb-diffs--min-height
             (+ 1 (with-current-buffer buf
                     (count-lines (point-min) (point-max)))))
      rb-diffs--min-height)))

(defun rb-diffs--fit-window ()
  "Adjust the diff panel window height to fit content."
  (when-let* ((win (get-buffer-window rb-diffs--buffer-name)))
    (let* ((lines (rb-diffs--content-height))
           (max-lines (floor (* (frame-height) rb-diffs--max-height)))
           (target (min lines max-lines)))
      (with-selected-window win
        (let ((delta (- target (window-height))))
          (unless (zerop delta)
            (window-resize win delta)))))))

(defun rb-diffs--show ()
  "Display the diff panel in the left side column below treemacs."
  (let ((buf (rb-diffs--get-or-create-buffer)))
    (display-buffer
     buf
     `(display-buffer-in-side-window
       . ((side          . left)
          (slot          . ,rb-diffs--side-slot)
          (window-height . ,rb-diffs--min-height)
          (dedicated     . t))))
    (rb-diffs--refresh-async)))

(defun rb-diffs--hide ()
  "Remove the diff panel window if visible."
  (when-let* ((win (get-buffer-window rb-diffs--buffer-name)))
    (delete-window win)))

(defun rb-diffs--visible-p ()
  "Return non-nil if the diff panel is currently displayed."
  (get-buffer-window rb-diffs--buffer-name))

;; ── Auto-refresh ─────────────────────────────────────────────────────────────

(defun rb-diffs--schedule-refresh ()
  "Schedule a debounced refresh of the diff panel."
  (when (rb-diffs--visible-p)
    (when (timerp rb-diffs--refresh-timer)
      (cancel-timer rb-diffs--refresh-timer))
    (setq rb-diffs--refresh-timer
          (run-with-idle-timer 0.5 nil #'rb-diffs--refresh-async))))

(defun rb-diffs--setup-hooks ()
  "Install hooks for auto-refresh on file save."
  (add-hook 'after-save-hook #'rb-diffs--schedule-refresh))

(defun rb-diffs--teardown-hooks ()
  "Remove auto-refresh hooks."
  (remove-hook 'after-save-hook #'rb-diffs--schedule-refresh)
  (when (timerp rb-diffs--refresh-timer)
    (cancel-timer rb-diffs--refresh-timer)
    (setq rb-diffs--refresh-timer nil)))

(defun rb-diffs-refresh ()
  "Manually refresh the diff panel."
  (interactive)
  (rb-diffs--refresh-async))

(provide 'rb-diffs)
;;; rb-diffs.el ends here

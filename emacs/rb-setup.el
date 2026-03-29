;;; rb-setup.el --- Rybalt Emacs integration  -*- lexical-binding: t; -*-

;; Workspace root for cross-project file finding.
;; Defaults to the directory where emacsclient was launched.
(defvar rb-workspace-root default-directory
  "Active workspace root for file finding and ripgrep.")

(defun rb-set-workspace-root (dir)
  "Set the active workspace root for file/grep commands."
  (interactive "DWorkspace root: ")
  (setq rb-workspace-root (file-name-as-directory dir))
  (message "Workspace root: %s" rb-workspace-root))

(defun rb-find-file-workspace ()
  "Fuzzy-find any file in the active workspace."
  (interactive)
  (consult-fd rb-workspace-root))

(defun rb-grep-workspace ()
  "Search file contents across the active workspace."
  (interactive)
  (consult-ripgrep rb-workspace-root))

;; Leader keybindings (requires evil-leader)
(with-eval-after-load 'evil-leader
  ;; Workspace-wide commands (SPC w prefix)
  (evil-leader/set-key
    "w f" #'rb-find-file-workspace
    "w g" #'rb-grep-workspace
    "w w" #'rb-set-workspace-root)
  ;; Repo-scoped commands (SPC r prefix)
  (evil-leader/set-key
    "r f" #'project-find-file
    "r g" #'project-find-regexp
    "r p" #'project-switch-project)
  ;; Buffer/line commands
  (evil-leader/set-key
    "b" #'consult-buffer
    "l" #'consult-line)
  (evil-leader/set-key
    "g g" #'magit-status
    "g d" #'rb-changed-files
    "g l" #'magit-log-current)
  (evil-leader/set-key
    "c c" (lambda () (interactive)
          (call-interactively (key-binding (kbd "C-c C-c"))))))

;;; Changed files browser

(defun rb--git-numstat (&rest args)
  "Return alist of (FILE ADDED REMOVED) from git diff --numstat with ARGS."
  (let (result)
    (dolist (line (apply #'magit-git-lines "diff" "--numstat" args))
      (when (string-match "^\\([0-9-]+\\)\t\\([0-9-]+\\)\t\\(.+\\)$" line)
        (push (list (match-string 3 line)
                    (match-string 1 line)
                    (match-string 2 line))
              result)))
    result))

(defun rb--filter-meta (files)
  "Remove Unity .meta files from FILES list."
  (cl-remove-if (lambda (f) (string-suffix-p ".meta" (if (consp f) (car f) f)))
                files))

(defun rb--changed-files-make-source (name narrow numstat-args file-fn)
  "Build a consult--multi source plist.
NAME is the group name, NARROW is the narrowing character,
NUMSTAT-ARGS are extra args for git diff --numstat,
FILE-FN is a function returning a list of relative file paths."
  (let ((stats nil))
    `(:name     ,name
      :narrow   ,narrow
      :category file
      :face     consult-file
      :state    ,#'consult--file-state
      :action   ,#'consult--file-action
      :annotate ,(lambda (cand)
                   (when-let* ((entry (assoc cand stats)))
                     (format "  +%s -%s" (nth 1 entry) (nth 2 entry))))
      :items    ,(lambda ()
                   (magit-with-toplevel
                     (setq stats (apply #'rb--git-numstat numstat-args))
                     (let ((root (magit-toplevel)))
                       (rb--filter-meta
                        (mapcar (lambda (f) (cons f (expand-file-name f root)))
                                (funcall file-fn)))))))))

(defun rb-changed-files ()
  "Browse all git changes in the working tree and staging area."
  (interactive)
  (require 'magit)
  (consult--multi
   (list (rb--changed-files-make-source
          "Staged" ?s '("--cached") #'magit-staged-files)
         (rb--changed-files-make-source
          "Unstaged" ?u '() #'magit-unstaged-files)
         (rb--changed-files-make-source
          "Untracked" ?n '() #'magit-untracked-files))
   :prompt "Changed files: "
   :require-match t
   :sort nil))

(provide 'rb-setup)
;;; rb-setup.el ends here

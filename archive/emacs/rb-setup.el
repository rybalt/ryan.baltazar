;;; rb-setup.el --- Rybalt Emacs integration  -*- lexical-binding: t; -*-

;; Workspace root detection via projectile (.projectile marker files).
;; Repo root detection via nearest .git, falling back to workspace root.

(declare-function projectile-project-root "projectile")
(declare-function projectile-add-known-project "projectile")
(declare-function projectile-switch-project-by-name "projectile")

(defvar consult-fd-args)  ; forward-declare for let-binding in rb-find-file-workspace

(defun rb-workspace-root ()
  "Return the workspace root via projectile, falling back to `default-directory'."
  (if (fboundp 'projectile-project-root)
      (or (projectile-project-root) default-directory)
    default-directory))

(defun rb-repo-root ()
  "Return the nearest git repo root, or the workspace root."
  (or (locate-dominating-file default-directory ".git")
      (rb-workspace-root)))

(defun rb-find-file-workspace ()
  "Fuzzy-find any file in the active workspace.
Ignores VCS ignore files so files in gitignored paths (e.g. NativePlugin~) are found."
  (interactive)
  (let ((consult-fd-args (cons "fd" '("--full-path" "--color=never" "--no-ignore-vcs"))))
    (consult-fd (rb-workspace-root))))

(defun rb-grep-workspace ()
  "Search file contents across the active workspace."
  (interactive)
  (consult-ripgrep (rb-workspace-root)))

(defun rb-find-file-repo ()
  "Fuzzy-find a file in the nearest git repo."
  (interactive)
  (consult-fd (rb-repo-root)))

(defun rb-grep-repo ()
  "Search file contents in the nearest git repo."
  (interactive)
  (consult-ripgrep (rb-repo-root)))

(defun rb-init-workspace (dir)
  "Initialize DIR as a projectile umbrella workspace.
Creates a .projectile marker file, registers the project, and switches to it."
  (interactive "DWorkspace root: ")
  (let* ((dir (file-name-as-directory (expand-file-name dir)))
         (marker (expand-file-name ".projectile" dir)))
    (unless (file-exists-p marker)
      (write-region "" nil marker nil 'silent))
    (projectile-add-known-project dir)
    (projectile-switch-project-by-name dir)
    (message "Workspace: %s" dir)))

;; Leader keybindings (requires evil-leader)
(with-eval-after-load 'evil-leader
  ;; Workspace-wide commands (SPC w prefix)
  (evil-leader/set-key
    "w f" #'rb-find-file-workspace
    "w g" #'rb-grep-workspace
    "w w" #'rb-init-workspace)
  ;; Repo-scoped commands (SPC r prefix)
  (evil-leader/set-key
    "r f" #'rb-find-file-repo
    "r g" #'rb-grep-repo
    "r p" #'project-switch-project)
  ;; Buffer/line commands
  (evil-leader/set-key
    "b" #'consult-buffer
    "l" #'consult-line)
  (evil-leader/set-key
    "g g" #'rb-magit-status
    "g d" #'rb-changed-files
    "g l" #'magit-log-current
    "g y" #'rb-github-link)
  (evil-leader/set-key
    "c c" (lambda () (interactive)
          (call-interactively (key-binding (kbd "C-c C-c"))))))

;;; Repo-aware magit

(defvar rb--repo-mru nil
  "MRU-ordered list of repo labels for the magit repo picker.")

(declare-function rb-diffs--discover-repos "rb-diffs")

(defun rb-magit-status ()
  "Pick a repo under the workspace root and open magit-status.
Repos are sorted by most recently selected."
  (interactive)
  (require 'magit)
  (let* ((repos (rb-diffs--discover-repos))
         (labels (mapcar #'car repos))
         (sorted (append
                  (cl-remove-if-not (lambda (l) (member l labels)) rb--repo-mru)
                  (cl-remove-if (lambda (l) (member l rb--repo-mru)) labels)))
         (choice (completing-read "Repo: " sorted nil t))
         (toplevel (cdr (assoc choice repos))))
    (when toplevel
      (setq rb--repo-mru (cons choice (remove choice rb--repo-mru)))
      (magit-status toplevel))))

;;; GitHub link generation

(defun rb-github--git-string (toplevel &rest args)
  "Run git in TOPLEVEL with ARGS, return trimmed stdout or nil on failure."
  (let ((default-directory (file-name-as-directory toplevel)))
    (with-temp-buffer
      (when (zerop (apply #'call-process "git" nil t nil args))
        (let ((out (string-trim (buffer-string))))
          (unless (string-empty-p out) out))))))

(defun rb-github--detect-remote-url (toplevel)
  "Return the remote URL for the repo at TOPLEVEL.
Prefers the tracking remote of the current branch, falls back to origin."
  (let* ((upstream (rb-github--git-string toplevel
                     "rev-parse" "--abbrev-ref" "@{upstream}"))
         (remote (when (and upstream (string-match "^\\([^/]+\\)/" upstream))
                   (match-string 1 upstream))))
    (or (when remote (rb-github--git-string toplevel "remote" "get-url" remote))
        (rb-github--git-string toplevel "remote" "get-url" "origin"))))

(defun rb-github--parse-remote-url (url)
  "Parse URL into (HOST ORG REPO) or nil.
Handles SSH (git@host:org/repo) and HTTPS (https://host/org/repo) forms."
  (cond
   ((string-match "^git@\\([^:]+\\):\\([^/]+\\)/\\([^/]+?\\)\\(?:\\.git\\)?$" url)
    (list (match-string 1 url) (match-string 2 url) (match-string 3 url)))
   ((string-match "^https?://\\([^/]+\\)/\\([^/]+\\)/\\([^/]+?\\)\\(?:\\.git\\)?/?$" url)
    (list (match-string 1 url) (match-string 2 url) (match-string 3 url)))))

(defun rb-github--default-branch (toplevel)
  "Return the default branch name for TOPLEVEL, or \"main\"."
  (or (when-let* ((ref (rb-github--git-string
                        toplevel "symbolic-ref" "refs/remotes/origin/HEAD")))
        (when (string-match "/\\([^/]+\\)$" ref)
          (match-string 1 ref)))
      "main"))

(defun rb-github--commit-on-remote-p (toplevel sha)
  "Return non-nil if SHA exists on any remote branch in TOPLEVEL."
  (rb-github--git-string toplevel "branch" "-r" "--contains" sha))

(defun rb-github-link ()
  "Copy a GitHub URL for the current file to the kill ring.
With a visual selection, generates a permalink with line range.
If the current commit is not on any remote, falls back to the default branch."
  (interactive)
  (unless (buffer-file-name)
    (user-error "Buffer has no file"))
  (let* ((file (buffer-file-name))
         (toplevel (or (locate-dominating-file file ".git")
                       (user-error "Not in a git repo")))
         (toplevel (expand-file-name toplevel))
         (rel-path (file-relative-name file toplevel))
         (remote-url (or (rb-github--detect-remote-url toplevel)
                         (user-error "No git remote found")))
         (parsed (or (rb-github--parse-remote-url remote-url)
                     (user-error "Cannot parse remote: %s" remote-url)))
         (default-branch (rb-github--default-branch toplevel))
         (visual (use-region-p))
         (line-beg (when visual (line-number-at-pos (region-beginning))))
         (line-end (when visual
                     (save-excursion
                       (goto-char (region-end))
                       (if (and (bolp) (> (point) (region-beginning)))
                           (1- (line-number-at-pos))
                         (line-number-at-pos)))))
         (sha (when visual
                (rb-github--git-string toplevel "rev-parse" "HEAD")))
         (pushed (when sha
                   (rb-github--commit-on-remote-p toplevel sha)))
         (ref (if (and visual pushed) sha default-branch))
         (fragment (cond
                    ((not (and visual pushed)) "")
                    ((and line-end (> line-end line-beg))
                     (format "#L%d-L%d" line-beg line-end))
                    (line-beg (format "#L%d" line-beg))
                    (t "")))
         (url (format "https://%s/%s/%s/blob/%s/%s%s"
                      (nth 0 parsed) (nth 1 parsed) (nth 2 parsed)
                      ref rel-path fragment)))
    (kill-new url)
    (if (and visual (not pushed))
        (message "HEAD not on remote, link points to %s (copied)" default-branch)
      (message "%s" url))))

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

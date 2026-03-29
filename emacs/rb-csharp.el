;;; rb-csharp.el --- C# development support  -*- lexical-binding: t; -*-

;; Isolated C# module: comment out the load line in post-init.el to disable.

;;; Code:

(require 'project)

;; ── Tree-sitter grammar ───────────────────────────────────────────────────────

(when (and (treesit-available-p)
           (not (treesit-language-available-p 'c-sharp)))
  (setq treesit-language-source-alist
        (append treesit-language-source-alist
                '((c-sharp "https://github.com/tree-sitter/tree-sitter-c-sharp"))))
  (treesit-install-language-grammar 'c-sharp))

(when (treesit-language-available-p 'c-sharp)
  (add-to-list 'major-mode-remap-alist '(csharp-mode . csharp-ts-mode)))

;; ── Solution path variable ────────────────────────────────────────────────────

(defvar-local rb-csharp-solution nil
  "Path to the .sln file for csharp-ls, relative to the umbrella root.
Set via .dir-locals.el at the umbrella root or interactively with
`rb-set-csharp-solution'.  When non-nil, this variable also drives
project root detection so that all C# files under the umbrella share
a single eglot/csharp-ls instance.")

(put 'rb-csharp-solution 'safe-local-variable
     (lambda (v) (or (null v) (stringp v))))

;; ── Project root override (C# only) ──────────────────────────────────────────

(defun rb--csharp-project-find (dir)
  "Return the umbrella project root for C# buffers.
Walks up from DIR until `rb-csharp-solution' resolves to an existing
file.  Returns a transient project instance or nil."
  (when (and (bound-and-true-p rb-csharp-solution)
             (derived-mode-p 'csharp-mode 'csharp-ts-mode))
    (when-let* ((root (locate-dominating-file
                       dir
                       (lambda (d)
                         (file-exists-p
                          (expand-file-name rb-csharp-solution d))))))
      (cons 'transient (file-name-as-directory root)))))

(add-hook 'project-find-functions #'rb--csharp-project-find)

;; ── csharp-ls contact function ────────────────────────────────────────────────

(defun rb--csharp-ls-contact (_interactive project)
  "Return the csharp-ls command for eglot.
When `rb-csharp-solution' is set, appends --solution with an absolute
path resolved against the project root."
  (let ((sln rb-csharp-solution))
    (if (null sln)
        '("csharp-ls")
      (let* ((root (project-root project))
             (resolved (expand-file-name sln root)))
        (if (file-exists-p resolved)
            (list "csharp-ls" "--solution" resolved)
          (message "rb-csharp: .sln not found at %s; starting without --solution"
                   resolved)
          '("csharp-ls"))))))

;; ── Eglot registration ────────────────────────────────────────────────────────

(with-eval-after-load 'eglot
  (add-to-list 'eglot-server-programs
               '((csharp-mode csharp-ts-mode) . rb--csharp-ls-contact)))

(add-hook 'csharp-mode-hook #'eglot-ensure)
(add-hook 'csharp-ts-mode-hook #'eglot-ensure)

;; ── Interactive solution override ─────────────────────────────────────────────

(defun rb-set-csharp-solution (path)
  "Set the csharp-ls solution path for the current buffer.
PATH may be absolute or relative to the project root.  This is a
session-only override; use .dir-locals.el for persistence.
Run \\[eglot-reconnect] afterward to apply."
  (interactive
   (list (read-file-name
          "Solution (.sln): "
          (when-let* ((proj (project-current))
                      (root (project-root proj)))
            root)
          nil nil nil
          (lambda (f) (or (file-directory-p f)
                          (string-suffix-p ".sln" f))))))
  (setq-local rb-csharp-solution path)
  (message "rb-csharp: solution set to %s (M-x eglot-reconnect to apply)" path))

(provide 'rb-csharp)
;;; rb-csharp.el ends here

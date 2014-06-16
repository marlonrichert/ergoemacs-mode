;;; ergoemacs-advices.el --- advices for ErgoEmacs

;; Copyright (C) 2013, 2014  Free Software Foundation, Inc.

;; Maintainer: Matthew L. Fidler
;; Keywords: convenience

;; ErgoEmacs is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published
;; by the Free Software Foundation, either version 3 of the License,
;; or (at your option) any later version.

;; ErgoEmacs is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with ErgoEmacs.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; 

;; Todo:

;; 

;;; Code:
(defvar ergoemacs-advices '()
  "List of advices to enable and disable when ergoemacs is running.")

(defvar ergoemacs-dir
  (file-name-directory
   (or
    load-file-name
    (buffer-file-name)))
  "Ergoemacs directory.")
(add-to-list 'load-path ergoemacs-dir)
(require 'ergoemacs-shortcuts)
(require 'ergoemacs-unbind)


(defmacro ergoemacs-define-overrides (&rest body)
  "Force the define-keys to work"
  `(let ((ergoemacs-run-mode-hooks t))
     ,@body))

(defadvice add-hook (around ergoemacs-add-hook-advice (hook function &optional append  local) activate)
  "Advice to allow `this-command' to be set correctly before running `pre-command-hook'
If `pre-command-hook' is used and `ergoemacs-mode' is enabled add to `ergoemacs-pre-command-hook' instead."
  (cond
   ((and (boundp 'ergoemacs-mode)
         ergoemacs-mode (eq hook 'pre-command-hook)
         (boundp 'ergoemacs-hook-functions)
         (memq hook ergoemacs-hook-functions))
    (add-hook 'ergoemacs-pre-command-hook function append local))
   (t
    ad-do-it)))

(defadvice remove-hook (around ergoemacs-remove-hook-advice (hook function &optional local) activate)
  "Advice to allow `this-command' to be set correctly before running `pre-command-hook'.
If `pre-command-hook' is used and `ergoemacs-mode' is remove from `ergoemacs-pre-command-hook' instead."
  (cond
   ((and (boundp 'ergoemacs-mode)
         ergoemacs-mode (eq hook 'pre-command-hook)
         (boundp 'ergoemacs-hook-functions)
         (memq hook ergoemacs-hook-functions))
    (remove-hook 'ergoemacs-pre-command-hook function local))
   (t
    ad-do-it)))

(defadvice define-key (around ergoemacs-define-key-advice (keymap key def) activate)
  "This does the right thing when modifying `ergoemacs-keymap'.
Also adds keymap-flag for user-defined keys run with `run-mode-hooks'."
  (let ((is-global-p (equal keymap (current-global-map))))
    (if (and (boundp 'ergoemacs-run-mode-hooks) ergoemacs-run-mode-hooks
             (not (equal keymap (current-global-map)))
             (not (equal keymap ergoemacs-keymap)))
        (let ((ergoemacs-run-mode-hooks nil)
              (new-key (read-kbd-macro
                        (format "<ergoemacs-user> %s"
                                (key-description key)))))
          (define-key keymap new-key def)))
    ad-do-it
    (when is-global-p
      (let ((vk key))
        (ergoemacs-global-set-key-after key)
        (unless (vectorp vk) ;; Do vector def too.
          (setq vk (read-kbd-macro (key-description key) t))
          (ergoemacs-global-set-key-after vk))))))

(defvar ergoemacs-global-override-rm-keys '())
;;; Advices enabled or disabled with ergoemacs-mode
(defvar ergoemacs-ignore-advice nil)
(defun ergoemacs-global-set-key-after (key)
  
  (if ergoemacs-ignore-advice nil
    (let ((kd (key-description key)))
      (unless (or (and (vectorp key)
                       (memq (elt key 0) '(menu-bar 27 remap)))
                  (and (not (vectorp key))
                       (string= "ESC" kd)))
        ;; Let `ergoemacs-mode' know these keys have changed.
        (pushnew kd ergoemacs-global-changed-cache :test 'equal)
        (setq ergoemacs-global-not-changed-cache (delete kd ergoemacs-global-not-changed-cache))
        ;; Remove the key from `ergoemacs-mode' bindings
        (ergoemacs-theme-component--ignore-globally-defined-key key t)))))

(add-to-list 'ergoemacs-advices 'ergoemacs-local-unset-key-advice)

(eval-after-load "helm"
  '(progn
     (defadvice helm-M-x (around ergoemacs-helm-M-x-keys activate)
       "Make ``helm-M-x' work correctly with `ergoemacs-mode' pretty keys"
       (let ((ergoemacs-use-M-x-p t))
         ad-do-it))))


(defadvice cua-mode (around ergoemacs-activate-only-selection-mode (arg) activate)
  "When `ergoemacs-mode' is enabled, enable `cua-selection-mode' instead of plain `cua-mode'."
  (when (and (boundp 'ergoemacs-mode) ergoemacs-mode)
    (setq-default cua-enable-cua-keys nil))
  ad-do-it
  (when (and (boundp 'ergoemacs-mode) ergoemacs-mode)
    (customize-mark-as-set 'cua-enable-cua-keys)))

(defadvice icicle-mode (around ergoemacs-icicle-play (arg) activate)
  "Allow `ergoemacs-mode' to play nicely with `icicle-mode'."
  (let ((oee (and (boundp 'ergoemacs-mode) ergoemacs-mode)))
    (when oee ;; Remove key bindings
      (ergoemacs-mode -1))
    ad-do-it
    (when oee ;; Add them back.  Now icy-mode should play nice.
      (ergoemacs-mode 1))))

(defcustom ergoemacs-helm-expand-user-dirs 't
  "Expand user directories under helm.
This makes helm behave more like `ido-find-file'"
  :group 'ergoemacs-mode
  :type 'boolean)

(eval-after-load "helm-files"
  '(progn
     (defadvice helm-ff-auto-expand-to-home-or-root (around ergoemacs-helm-ido-user-dirs activate)
      "Allow `helm-find-files' to expand user directories.
For example ~ergoemacs/ would expand to /usr/ergoemacs or
whatever that points to...

This require `ergoemacs-mode' to be enabled as well as
`ergoemacs-helm-expand-user-dirs' to be true.
"
      (cond
       ((and ergoemacs-helm-expand-user-dirs
             (boundp 'ergoemacs-mode)
             ergoemacs-mode
             (helm-file-completion-source-p)
             (string-match "/\\(~[^/]*/\\)$" helm-pattern)
             (with-current-buffer (window-buffer (minibuffer-window)) (eolp))
             (not (string-match helm-ff-url-regexp helm-pattern)))
        (let ((input (match-string 1 helm-pattern)))
          (if (file-directory-p input)
              (setq helm-ff-default-directory
                    (setq input (file-name-as-directory input)))
            (setq helm-ff-default-directory (file-name-as-directory
                                             (file-name-directory input))))
          (with-helm-window
            (helm-set-pattern input)
            (helm-check-minibuffer-input))))
       (t
        ad-do-it)))))


(defadvice run-mode-hooks (around ergoemacs-run-hooks activate)
  "`ergoemacs-mode' run-hooks advice helps user define keys properly.
This assumes any key defined while running a hook is a user-defined hook."
  (let ((ergoemacs-run-mode-hooks t))
    ad-do-it))

(defadvice turn-on-undo-tree-mode (around ergoemacs-undo-tree-mode activate)
  "Make `ergoemacs-mode' and undo-tree compatible."
  (ergoemacs-with-global
   ad-do-it))

(defun ergoemacs-substitute-command (string &optional map)
  "Substitutes command STRING
will add MAP to substitution."
  (save-match-data
    (let* (ret
           (test (ergoemacs-with-global
                  (ergoemacs-real-substitute-command-keys
                   (or (and map (concat map string)) string))))
           (test-vect (read-kbd-macro test t))
           (test-hash (gethash test-vect ergoemacs-original-keys-to-shortcut-keys)))
      (if test-hash
          (progn
            (setq test (key-description (nth 0 test-hash)))
            (ergoemacs-pretty-key test))
        (let (ergoemacs-modal ergoemacs-repeat-keys ergoemacs-read-input-keys
                              ergoemacs-shortcut-keys)
          (ergoemacs-pretty-key
           (ergoemacs-real-substitute-command-keys
            (or (and map (concat map string)) string))))))))

(defun ergoemacs-substitute-map--1 (string)
  (substring
   (replace-regexp-in-string
    "`\\(binding\\|Prefix Command\\|-------\\)'" "\\1"
    (replace-regexp-in-string
     "---|\n|-" "---|"
     (replace-regexp-in-string
      "^|'[ \t]*|$" "|-"
      (replace-regexp-in-string
       "' |\n.*(that binding is.*\n|'" "' (shadowed)"
       (replace-regexp-in-string
        "^" "|"
        (replace-regexp-in-string
         "$" "' |"
         (replace-regexp-in-string
          "\\([ \t]\\{2,\\}\\|\t\\)" "\\1 | `"
          string))))))) 0 -2))

(defun ergoemacs-substitute-map (string &optional function)
  (save-match-data
    (let* (ret
           ergoemacs-use-unicode-brackets
           (max1 0) (max2 0)
           (function (or function 'ergoemacs-real-substitute-command-keys))
           (test (ergoemacs-with-global
                  (funcall function string)))
           (shortcut-list '()))
      (while (string-match (format "^%s.*$"ergoemacs-original-keys-to-shortcut-keys-regexp) test)
        (push (match-string 0 test) shortcut-list)
        (setq test
              (replace-match "" nil nil test)))
      (let (ergoemacs-modal ergoemacs-repeat-keys ergoemacs-read-input-keys
                            ergoemacs-shortcut-keys)
        (setq test (funcall function string))
        (when (string-match ".*\n.*\n" test)
          (setq ret (ergoemacs-substitute-map--1
                     (concat (match-string 0 test)
                             (mapconcat (lambda(x) x) shortcut-list "\n")
                             (replace-match "" nil nil test))))))
      (with-temp-buffer
        (insert ret)
        (goto-char (point-min))
        (while (re-search-forward ".*\\(ergoemacs-shortcut\\|Prefix Command\\).*" nil t)
          (delete-region (point-at-bol) (point-at-eol))
          (when (looking-at "\n+")
            (replace-match "")))
        (while (search-forward "`??'" nil t)
          (replace-match (concat " " (ergoemacs-unicode-char "λ" "?") "  ") t t))
        (goto-char (point-min))
        (forward-line 2)
        (while (re-search-forward "^|\\(.*?\\)[ \t]+|" nil t)
          (setq test (ergoemacs-pretty-key (match-string 1)))
          (replace-match (format "| %s |" test) t t)
          (setq max1 (max max1 (length test))
                max2 (max max2 (length (buffer-substring (point) (point-at-eol))))))
        (setq test (concat "|"
                           (make-string (+ max1 2) ?-)
                           "+"
                           (make-string (max 0 (- max2 1)) ?-)
                           "|"))
        (goto-char (point-min))
        (insert test "\n")
        (goto-char (point-max))
        (insert "\n" test "\n\n")
        (goto-char (point-min))
        (while (re-search-forward "|-.*\\(\n|-.*\\)*" nil t)
          (replace-match test t t))
        (goto-char (point-min))
        (while (re-search-forward "^| *\\(.*?[^ ]\\) +| *\\(.*?[^ ]\\) +|$" nil t)
          (replace-match (format "| \\1%s | \\2%s |"
                                 (make-string (max 0 (- max1 (length (match-string 1)))) ? )
                                 (make-string (max 0 (- max2 (+ 3 (length (match-string 2))))) ? )) t))
        (setq ret (buffer-string)))
      ret)))



(defun ergoemacs-substitute-command-keys (string)
  "`ergoemacs-mode' replacement for substitute-command-keys.
Actual substitute-command-keys is always in `ergoemacs-real-substitute-command-keys'"
  (if (not string) nil
    (let (ret str mapvar)
      (if (not ergoemacs-mode)
          (setq ret (ergoemacs-real-substitute-command-keys string))
        (with-temp-buffer
          (insert string)
          (goto-char (point-min))
          (while (re-search-forward "\\(\\(?:\\\\=\\)?\\)\\\\\\(\\[\\|<\\|{\\)\\(.*?\\)\\(\\]\\|>\\|}\\)" nil t)
            (cond
             ((string-match-p "\\\\=" (match-string 1))
              (replace-match "\\\\\\2\\3\\4" t nil))
             ((and (string-match-p "<" (match-string 2))
                   (string-match-p ">" (match-string 4)))
              (setq mapvar (concat "\\<" (match-string 3) ">"))
              (replace-match ""))
             ((and (string-match-p "{" (match-string 2))
                   (string-match-p "}" (match-string 4)))
              (replace-match (ergoemacs-substitute-map (match-string 0)) t t))
             ((and (string-match-p "\\[" (match-string 2))
                   (string-match-p "\\]" (match-string 4)))
              (replace-match (ergoemacs-substitute-command (match-string 0) mapvar) t t))))
          (goto-char (point-min))
          (while (re-search-forward "\\\\=" nil t)
            (replace-match "" t t)
            (re-search-forward "\\=\\\\=" nil t))
          (goto-char (point-min))
          (while (re-search-forward "\\(\\<M-x\\|<execute>\\) " nil t)
            (replace-match (ergoemacs-substitute-command "\\[execute-extended-command] " "\\<global-map>") t t))
          (setq ret (buffer-string))))
      ret)))

;;; Unfortunately, the advice route doesn't seem to work :(

(fset 'ergoemacs-real-substitute-command-keys (symbol-function 'substitute-command-keys))

(fset 'ergoemacs-real-completing-read (symbol-function 'completing-read))
(defun ergoemacs-completing-read (prompt collection &optional
                                         predicate require-match
                                         initial-input hist def inherit-input-method)
  "Ergoemacs replacement of `completing-read'.
Allows `execute-extended-command' to show the proper keys.
The real command is always `ergoemacs-real-completing-read'.
"
  (ergoemacs-real-completing-read
   (substitute-command-keys
    (replace-regexp-in-string "\\<M-x " "\\[execute-extended-command] " prompt t t))
   collection predicate require-match
   initial-input hist def inherit-input-method))
(provide 'ergoemacs-advices)
;;;;;;;;;;;;;;;;;;;;;;;;`';;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; ergoemacs-advices.el ends here
;; Local Variables:
;; coding: utf-8-emacs
;; End:

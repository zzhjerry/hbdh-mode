;;; hbdh.el --- Highlighting by dehighliting  -*- lexical-binding:t -*-

;; Copyright (C) 2024 Free Software Foundation, Inc.

;; Author: Zhang Zhaoheng <zzh699@gmail.com>
;; Maintainer: Zhang Zhaoheng <zzh699@gmail.com>
;; Version: 0.1
;; Keywords: hbdh, region
;; URL: https://github.com/zzhjerry/hbdh
;; Package-Requires: ((emacs "29.1"))
;;
;; This file is part of GNU Emacs.
;;
;; GNU Emacs is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; `hdbh-mode' is a minor mode that highlights current active region
;; by dimming text outside of it. When this minor mode is on, there
;; are two ways to activate this behavior.
;;
;; One way is to call `hbdh-activate-on-region' command when a
;; region is active. To deactivate it, invoke `hbdh-deactivate' or
;; `keyboard-quit' command (bound to `C-g' by default).
;;
;; Another option is to specify a value for
;; `hbdh-activation-commands', which is a list of commands that
;; triggers `hbdh-activate-on-region' automatically. These commands
;; should generate or change the range of a region. In this case,
;; invoking any other commands that are not in the list will
;; automatically invoke `hbdh-deactivate'.
;;
;; For example:
;;
;; (setq hbdh-activation-commands '(mark-defun))
;;
;; In this case, when you call `mark-defun' (bound by "C-M-h"), the
;; text outside of current highlighted function will be dimmed out (if
;; you set `hbdh-dim-color' correctly)

;;; Code:

(require 'face-remap)

(defgroup hbdh nil
  "Group for hbdh (Highlighting by Dehighlighting)")

(defvar hbdh--prior-region-overlay
  (make-overlay (point-min) (point-min))
  "The overlay put before the current active region.")

(defvar hbdh--after-region-overlay
  (make-overlay (point-max) (point-max))
  "The overlay put after the current active region.")

(defvar hbdh--region-face-cookie nil
  "Face remapping cookie generated by `face-remap-add-relative'")

(defcustom hbdh-activation-commands nil
  "A command list that triggers hbdh region.

The command list should either create or change an active region.
If the command fails to do so, the hbdh overlay will be removed.
Any other commands that are invoked outside this command list will also remove hbdh overlays"
  :group 'hbdh)

(defcustom hbdh-dim-color "dark grey"
  "The foreground color used for dimmed text.

This color will override the foreground color of `shadow' face. This
value could either be a color, a function or a face name.
If the value is a face, the face's foreground color will be used.
If the value is a function, the return value of the function will be
used, which is useful when using both light and dark backgrounds.
If the value is a stirng, it will be treated as a color name or a
color value in hex format."
  :type '(choice (color :tag "Color")
		 (function :tag "Function that return color")
		 (face :tag "Face Name"))
  :group 'hbdh)

(defun hbdh--get-dim-color ()
  (cond ((facep hbdh-dim-color) (face-foreground hbdh-dim-color))
	((functionp hbdh-dim-color) (funcall hbdh-dim-color))
	((stringp hbdh-dim-color) hbdh-dim-color)
	(t (progn (message "`hbdh-dim-color' is not specified") 'unspecified))))

(defun hbdh--activation-command-captured-p (&optional cmd)
  "Test whether CMD is a member of `hbdh-activation-commands', using THIS-COMMAND by default."
  (let ((cmd (or cmd this-command)))
    (memq cmd hbdh-activation-commands)))

(defun hbdh--activate-overlay (beg end)
  "Activate and move overlay delimited by `region''s BEG and END"
  (when (and beg end)
    (move-overlay hbdh--prior-region-overlay
		  (point-min) beg (current-buffer))
    (move-overlay hbdh--after-region-overlay
		  end (point-max) (current-buffer))
    (overlay-put hbdh--prior-region-overlay
		 'face (list :foreground (hbdh--get-dim-color) 'shadow))
    (overlay-put hbdh--after-region-overlay
		 'face (list :foreground (hbdh--get-dim-color) 'shadow))))

;;;###autoload
(defun hbdh-activate-on-region ()
  "Activate hbdh, dim texts outside of current active region"
  (interactive)
  (when-let ((active-p (region-active-p))
	     (beg (region-beginning))
	     (end (region-end)))
    (hbdh--activate-overlay beg end)
    (hbdh--rewrite-region-face)))

;;;###autoload
(defun hbdh-deactivate ()
  "Deactivate hbdh, restore dimmed text."
  (interactive)
  (move-overlay hbdh--prior-region-overlay (point-min) (point-min))
  (move-overlay hbdh--after-region-overlay (point-max) (point-max))
  (overlay-put hbdh--prior-region-overlay 'face nil)
  (overlay-put hbdh--after-region-overlay 'face nil)
  (hbdh--restore-region-face))

(defun hbdh--rewrite-region-face ()
  "Temporarily remove `region''s background."
  (unless hbdh--region-face-cookie
    (face-remap-set-base 'region nil)
    (setq hbdh--region-face-cookie
	  (face-remap-add-relative 'region '(:background unspecified)))))

(defun hbdh--restore-region-face ()
  "Restore `region''s background."
  (face-remap-reset-base 'region)
  (face-remap-remove-relative hbdh--region-face-cookie)
  (setq hbdh--region-face-cookie nil))

(defun hbdh--activate-maybe ()
  "A post command hook function that activate hbdh by condition"
  (when (hbdh--activation-command-captured-p)
    (hbdh-activate-on-region)))

(defun hbdh--deactivate-maybe ()
  "A post command hook function that deactivate hbdh by condition."
  (when (or (equal this-command 'keyboard-quit)
	    (and (not (hbdh--activation-command-captured-p))
		 (hbdh--activation-command-captured-p last-command)))
    (hbdh-deactivate)))

;; TODO: how to enable this keymap even if `hbdh-mode' is not enabled.
(defvar hbdh-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "M-s a") 'hbdh-activate-on-region)
    map))

;;;###autoload
(define-minor-mode hbdh-mode nil
  :global t
  :keymap hbdh-mode-map
  :require 'hbdh
  (if hbdh-mode
      (hbdh--add-post-command-hook)
    (hbdh--remove-post-command-hook)))

(defun hbdh--add-post-command-hook ()
  "Hook into `post-command-hook' for commands that activates hbdh"
  (add-hook 'post-command-hook #'hbdh--activate-maybe)
  (add-hook 'post-command-hook #'hbdh--deactivate-maybe))

(defun hbdh--remove-post-command-hook ()
  (remove-hook 'post-command-hook #'hbdh--activate-maybe)
  (remove-hook 'post-command-hook #'hbdh--deactivate-maybe)
  (hbdh-deactivate)
  (setq face-remapping-alist nil))

(provide 'hbdh)

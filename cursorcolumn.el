;;; cursorcolumn.el --- Column highlighting (vertical line displaying) mode -*- lexical-binding: t -*-
;;
;; Maintainer: James cherti
;; URL: https://github.com/jamescherti/cursorcolumn.el
;;
;; Keywords: faces, editing, emulating
;; Package-Requires: ((emacs "24.3"))
;; Original Author: Taiki SUGAWARA <buzz.taiki@gmail.com>
;;
;; Copyright (C) 2024 by James Cherti | https://www.jamescherti.com/
;; Copyright (C) 2002, 2008-2021 by Taiki SUGAWARA <buzz.taiki@gmail.com>
;;
;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.
;;
;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Commentary:

;; `cursorcolumn-mode' is a minor mode for highlighting column at cursor
;; position.  To enable it in a buffer, type M-x cursorcolumn-mode.

;;; Code:

(require 'hl-line)

(defvar cursorcolumn-overlay-table-size 200)
(defvar cursorcolumn-overlay-table (make-vector cursorcolumn-overlay-table-size nil))
(defvar cursorcolumn-line-char ?|)
(defvar cursorcolumn-multiwidth-space-list
  (list
   ?\t
   (decode-char 'ucs #x3000)    ; japanese fullwidth space
   ))
(defvar cursorcolumn-timer nil)

(defcustom cursorcolumn-style 'face
  "This variable holds vertical line display style.
Available values are followings:
`face'      : use face.
`compose'   : use composit char.
`mixed'      : use face and composit char."
  :type '(radio
          (const face)
          (const compose)
          (const mixed))
  :group 'cursorcolumn)

(defface cursorcolumn
  '((t :inherit hl-line :extend t))
  "A default face for vertical line highlighting."
  :group 'cursorcolumn)

(defface cursorcolumn-visual
  '((t (:background "gray90")))
  "A default face for vertical line highlighting in visual lines."
  :group 'cursorcolumn)

(defcustom cursorcolumn-face 'cursorcolumn
  "A face for vertical line highlighting."
  :type 'face
  :group 'cursorcolumn)

(defcustom cursorcolumn-visual-face 'cursorcolumn-visual
  "A face for vertical line highlighting in visual lines."
  :type 'face
  :group 'cursorcolumn)

(defcustom cursorcolumn-current-window-only nil
  "If non-nil then highlight column in current window only.
If the buffer is shown in several windows then highlight column only
in the currently selected window."
  :type 'boolean
  :group 'cursorcolumn)

(defcustom cursorcolumn-visual t
  "If non-nil then highlight column in visual lines.
If you specified `force' then use force visual line highlighting even
if `truncate-lines' is non-nil."
  :type '(radio
          (const nil)
          (const t)
          (const force))
  :group 'cursorcolumn)

(defcustom cursorcolumn-use-timer t
  "If non-nil, use idle timer instead of (post|after)-command-hook."
  :type 'boolean
  :group 'cursorcolumn)

(defcustom cursorcolumn-idle-time 0.02
  "Idle time for highlighting column."
  :type 'number
  :group 'cursorcolumn)

;;;###autoload
(define-minor-mode cursorcolumn-mode
  "Display vertical line mode."
  :global nil
  :lighter " VL"
  :group 'cursorcolumn
  (if cursorcolumn-mode
      (progn
        (add-hook 'pre-command-hook 'cursorcolumn-pre-command-hook nil t)
        (if cursorcolumn-use-timer
            (cursorcolumn-set-timer)
          (progn
            (add-hook 'after-change-functions 'cursorcolumn-after-change-functions nil t)
            (add-hook 'post-command-hook 'cursorcolumn-post-command-hook nil t))))
    (progn
      (cursorcolumn-cancel-timer)
      (cursorcolumn-clear)
      (remove-hook 'after-change-functions 'cursorcolumn-after-change-functions)
      (remove-hook 'pre-command-hook 'cursorcolumn-pre-command-hook t)
      (remove-hook 'post-command-hook 'cursorcolumn-post-command-hook t))))

;;;###autoload
(define-global-minor-mode cursorcolumn-global-mode
  cursorcolumn-mode
  (lambda ()
    (unless (minibufferp)
      (cursorcolumn-mode 1)))
  :group 'cursorcolumn)

(defun cursorcolumn-pre-command-hook ()
  (when (and cursorcolumn-mode (not (minibufferp)))
    (cursorcolumn-clear)))

(defun cursorcolumn-post-command-hook ()
  (when (and cursorcolumn-mode (not (minibufferp)))
    (cursorcolumn-show)))

(defun cursorcolumn-after-change-functions (beg end len)
  (cursorcolumn-post-command-hook))

(defun cursorcolumn-set-timer ()
  (setq cursorcolumn-timer
        (run-with-idle-timer
         cursorcolumn-idle-time t 'cursorcolumn-timer-callback)))

(defun cursorcolumn-cancel-timer ()
  (when (timerp cursorcolumn-timer)
    (cancel-timer cursorcolumn-timer)))

(defun cursorcolumn-timer-callback ()
  (when (and cursorcolumn-mode (not (minibufferp)))
    (cursorcolumn-show)))

(defun cursorcolumn-clear ()
  (mapcar (lambda (ovr)
            (and ovr (delete-overlay ovr)))
          cursorcolumn-overlay-table))

(defsubst cursorcolumn-into-fringe-p ()
  (eq (nth 1 (posn-at-point)) 'right-fringe))

(defsubst cursorcolumn-visual-p ()
  (or (eq cursorcolumn-visual 'force)
      (and (not truncate-lines)
           cursorcolumn-visual)))

(defsubst cursorcolumn-current-column ()
  (if (or (not (cursorcolumn-visual-p))
          ;; margin for full-width char
          (< (1+ (current-column)) (window-width)))
      (current-column)
    ;; hmm.. posn-at-point is not consider tab width.
    (- (current-column)
       (save-excursion
         (vertical-motion 0)
         (current-column)))))

(defsubst cursorcolumn-move-to-column (col &optional bol-p)
  (if (or (not (cursorcolumn-visual-p))
          ;; margin for full-width char
          (< (1+ (current-column)) (window-width)))
      (move-to-column col)
    (unless bol-p
      (vertical-motion 0))
    (let ((bol-col (current-column)))
      (- (move-to-column (+ bol-col col))
         bol-col))))

(defsubst cursorcolumn-invisible-p (pos)
  (let ((inv (get-char-property pos 'invisible)))
    (and inv
         (or (eq buffer-invisibility-spec t)
             (memq inv buffer-invisibility-spec)
             (assq inv buffer-invisibility-spec)))))

(defsubst cursorcolumn-forward (n)
  (unless (memq n '(-1 0 1))
    (error "n(%s) must be 0 or 1" n))
  (if (not (cursorcolumn-visual-p))
      (progn
        (forward-line n)
        ;; take care of org-mode, outline-mode
        (when (and (not (bobp))
                   (cursorcolumn-invisible-p (1- (point))))
          (goto-char (1- (point))))
        (when (cursorcolumn-invisible-p (point))
          (if (< n 0)
              (while (and (not (bobp)) (cursorcolumn-invisible-p (point)))
                (goto-char (previous-char-property-change (point))))
            (while (and (not (bobp)) (cursorcolumn-invisible-p (point)))
              (goto-char (next-char-property-change (point))))
            (forward-line 1))))
    (vertical-motion n)))

(defun cursorcolumn-face (visual-p)
  (if visual-p
      cursorcolumn-visual-face
    cursorcolumn-face))

(defun cursorcolumn--calculate-window-visible-lines ()
  "A more accurate alternative to (window-height) is one that calculates the number of
lines in the current window, taking into consideration other changes in the window, such
as text scaling."
  (let ((beginning-line (line-number-at-pos (window-start)))
        (end-line (line-number-at-pos (window-end))))
    (+ 1 (- end-line beginning-line))))

(defun cursorcolumn-show (&optional point)
  (cursorcolumn-clear)
    (save-excursion
      (if point
          (goto-char point)
        (setq point (point)))
      (let* ((column (cursorcolumn-current-column))
             (lcolumn (current-column))
             (i 0)
             (compose-p (memq cursorcolumn-style '(compose mixed)))
             (face-p (memq cursorcolumn-style '(face mixed)))
             (line-char (if compose-p cursorcolumn-line-char ?\ ))
             (line-str (make-string 1 line-char))
             (visual-line-str line-str)
             (window-height (cursorcolumn--calculate-window-visible-lines))
             (in-fringe-p (cursorcolumn-into-fringe-p)))
        (when face-p
          (setq line-str (propertize line-str 'face (cursorcolumn-face nil)))
          (setq visual-line-str (propertize visual-line-str 'face (cursorcolumn-face t))))
        (goto-char (window-end nil t))
        (cursorcolumn-forward 0)
        (while (and (not in-fringe-p)
                    (< i window-height)
                    (< i (length cursorcolumn-overlay-table))
                    (not (bobp)))
          (let ((cur-column (cursorcolumn-move-to-column column t)))
            ;; non-cursor line only (workaround of eol probrem.
            (unless (= (point) point)
              ;; if column over the cursor's column (when tab or wide char is appered.
              (when (> cur-column column)
                (let ((lcol (current-column)))
                  (backward-char)
                  (setq cur-column (- cur-column (- lcol (current-column))))))
              (let* ((ovr (aref cursorcolumn-overlay-table i))
                     (visual-p (or (< lcolumn (current-column))
                                   (> lcolumn (+ (current-column)
                                                 (- column cur-column)))))
                     ;; consider a newline, tab and wide char.
                     (str (concat (make-string (- column cur-column) ?\ )
                                  (if visual-p visual-line-str line-str)))
                     (char (char-after)))
                ;; create overlay if not found.
                (unless ovr
                  (setq ovr (make-overlay 0 0))
                  (overlay-put ovr 'rear-nonsticky t)
                  (aset cursorcolumn-overlay-table i ovr))

                ;; initialize overlay.
                (overlay-put ovr 'face nil)
                (overlay-put ovr 'before-string nil)
                (overlay-put ovr 'after-string nil)
                (overlay-put ovr 'invisible nil)
                (overlay-put ovr 'window
                             (if cursorcolumn-current-window-only
                                 (selected-window)
                               nil))

                (cond
                 ;; multiwidth space
                 ((memq char cursorcolumn-multiwidth-space-list)
                  (setq str
                        (concat str
                                (make-string (- (save-excursion (forward-char)
                                                                (current-column))
                                                (current-column)
                                                (string-width str))
                                             ?\ )))
                  (move-overlay ovr (point) (1+ (point)))
                  (overlay-put ovr 'invisible t)
                  (overlay-put ovr 'after-string str))
                 ;; eol
                 ((eolp)
                  (move-overlay ovr (point) (point))
                  (overlay-put ovr 'after-string str)
                  ;; don't expand eol more than window width
                  (when (and (not truncate-lines)
                             (>= (1+ column) (window-width))
                             (>= column (cursorcolumn-current-column))
                             (not (cursorcolumn-into-fringe-p)))
                    (delete-overlay ovr)))
                 (t
                  (cond
                   (compose-p
                    (let (str)
                      (when char
                        (setq str (compose-chars
                                   char
                                   (cond ((= (char-width char) 1)
                                          '(tc . tc))
                                         ((= cur-column column)
                                          '(tc . tr))
                                         (t
                                          '(tc . tl)))
                                   line-char))
                        (when face-p
                          (setq str (propertize str 'face (cursorcolumn-face visual-p))))
                        (move-overlay ovr (point) (1+ (point)))
                        (overlay-put ovr 'invisible t)
                        (overlay-put ovr 'after-string str))))
                   (face-p
                    (move-overlay ovr (point) (1+ (point)))
                    (overlay-put ovr 'face (cursorcolumn-face visual-p))))))))
            (setq i (1+ i))
            (cursorcolumn-forward -1))))))

(provide 'cursorcolumn)
;;; cursorcolumn.el ends here

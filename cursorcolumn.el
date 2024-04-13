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
;; Copyright (C) 2002-2021 by Taiki SUGAWARA <buzz.taiki@gmail.com>
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

(defvar cursorcolumn-overlay-table-size 400)
(defvar cursorcolumn-overlay-table (make-vector cursorcolumn-overlay-table-size nil))
(defvar cursorcolumn-line-char ?|)

;; Example cursorcolumn-multiwidth-space-list of Japanese fullwidth space:
;;   (list ?\t (decode-char 'ucs #x3000)))
;; (defvar cursorcolumn-multiwidth-space-list (list ?\t (decode-char 'ucs #x3000)))
(defvar cursorcolumn-multiwidth-space-list '())

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

(defcustom cursorcolumn-overlay-priority -50
  "Priority used on the overlay used by cursorcolumn."
  :type 'integer
  :group 'cursorcolumn)

;;;###autoload
(define-minor-mode cursorcolumn-mode
  "Display vertical line mode."
  :global nil
  :lighter " VL"
  :group 'cursorcolumn
  (if cursorcolumn-mode
      (progn
        ;; (add-hook 'pre-command-hook 'cursorcolumn-pre-command-hook nil t)
        (if cursorcolumn-use-timer
            (cursorcolumn-set-timer)
          (progn
            (add-hook 'after-change-functions 'cursorcolumn-after-change-functions nil t)
            (add-hook 'post-command-hook 'cursorcolumn-post-command-hook nil t))))
    (cursorcolumn-cancel-timer)
    (cursorcolumn-clear)
    (remove-hook 'after-change-functions 'cursorcolumn-after-change-functions)
    ;; (remove-hook 'pre-command-hook 'cursorcolumn-pre-command-hook t)
    (remove-hook 'post-command-hook 'cursorcolumn-post-command-hook t)))

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
  (let ((point (point)))
    (when (or (not (boundp 'cursorcolumn-previous-cursor-position))
              (and (boundp 'cursorcolumn-previous-cursor-position)
                   (not (= cursorcolumn-previous-cursor-position point))))
      (setq-local cursorcolumn-previous-cursor-position point)
      (when (and cursorcolumn-mode (not (minibufferp)))
        (cursorcolumn-clear)
        (cursorcolumn-show cursorcolumn-previous-cursor-position)))))

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
  ;; FIXME: Slow
  (mapcar (lambda (ovr)
            (and ovr (delete-overlay ovr)))
          cursorcolumn-overlay-table))

(defsubst cursorcolumn-into-fringe-p ()
  ;; Disabled. Slow. TODO: How important is it?
  ;; (eq (nth 1 (posn-at-point)) 'right-fringe)
  nil
  )

(defsubst cursorcolumn-visual-p ()
  (or (eq cursorcolumn-visual 'force)
      (and (not truncate-lines)
           cursorcolumn-visual)))

(defsubst cursorcolumn-current-column ()
  (if (or (not (cursorcolumn-visual-p))
          ;; Margin for full-width char
          (< (1+ (current-column)) (window-width)))
      (current-column)
    ;; When in visual mode and at the edge, adjust the column calculation.
    (- (current-column)
       (save-excursion
         ;; (vertical-motion 0)
         (beginning-of-line)
         (current-column)))))

(defsubst cursorcolumn-move-to-column (target-col &optional at-line-beginning)
  "Move the cursor to the specified column TARGET-COL.
If AT-LINE-BEGINNING is non-nil, the movement is adjusted from the beginning of the line."
  ;; Checks if visual-line-mode is not active
  (if (or (not (cursorcolumn-visual-p))
          ;; margin for full-width char
          (< (1+ (current-column)) (window-width)))
      ;; Move directly if conditions are met
      (move-to-column target-col)
    (unless at-line-beginning
      ;; If not adjusting from the line's beginning, move vertically to align
      ;; with the current line start
      ;; (vertical-motion 0)
      (beginning-of-line))
    (let ((bol-col (current-column)))
      ;; Calculate the effective column after movement and adjust for any
      ;; discrepancies
      (- (move-to-column (+ bol-col target-col))
         ;; Return the adjustment difference
         bol-col))))

(defsubst cursorcolumn-invisible-p (pos)
  "Check if the character at position POS is invisible. This function examines
   the invisible property of the character at the specified position and
   determines if it is considered invisible according to the current buffer's
   invisibility specifications."
  (let ((inv (get-char-property pos 'invisible)))
    (and inv
         (or (eq buffer-invisibility-spec t)
             (memq inv buffer-invisibility-spec)
             (assq inv buffer-invisibility-spec)))))

(defsubst cursorcolumn-forward (n)
  ;; Validate the input immediately.
  (unless (memq n '(-1 0 1))
    (error "n(%s) must be 0 or 1" n))

  ;; Choose behavior based on visual state.
  (if (not (cursorcolumn-visual-p))
      (progn
        ;; Move cursor in specified direction.
        (forward-line n)

        ;; Handling for invisible text.
        ;; (org-mode, outline-mode...)
        ;; FIXME Optimize this part
        ;; (when (and (not (bobp))
        ;;            (cursorcolumn-invisible-p (1- (point))))
        ;;   ;; (goto-char (1- (point)))  ;; FIXME Replaced with backward-char.
        ;;   (backward-char))

        ;; (when (cursorcolumn-invisible-p (point))
        ;;   (if (< n 0)
        ;;       (while (and (not (bobp))
        ;;                   (cursorcolumn-invisible-p (point)))
        ;;         (goto-char (previous-char-property-change (point))))
        ;;     (progn
        ;;       (while (and (not (bobp))
        ;;                   (cursorcolumn-invisible-p (point)))
        ;;         (goto-char (next-char-property-change (point))))
        ;;       (forward-line 1))))

        )
    ;; Default action if cursorcolumn-visual-p returns true.
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

;; FIXME: slow
(defun cursorcolumn--set-overlay-properties (cur-column column i
                                                        compose-p face-p line-char
                                                        point visual-p line-str visual-line-str)
  (interactive)
  (let ((ovr (aref cursorcolumn-overlay-table i))
        (str (concat (make-string (- column cur-column) ?\ )
                     (if visual-p visual-line-str line-str)))
        (char (char-after)))
    ;; Create an overlay if not found
    (unless ovr
      (setq ovr (make-overlay 0 0))
      (overlay-put ovr 'priority cursorcolumn-overlay-priority)
      (overlay-put ovr 'rear-nonsticky t)
      (aset cursorcolumn-overlay-table i ovr))

    ;; Initialize or update the overlay properties
    (overlay-put ovr 'face nil)
    (overlay-put ovr 'before-string nil)
    (overlay-put ovr 'after-string nil)
    (overlay-put ovr 'invisible nil)
    (overlay-put ovr 'window (and cursorcolumn-current-window-only
                                  (selected-window)))

    ;; Handle special cases for character display at overlay position
    ;; (multiwidth space)
    (cond
     ;; Handle end of line
     ((eolp)
      (move-overlay ovr (point) (point))
      (overlay-put ovr 'after-string str)
      ;; Don't expand eol more than window width
      (when (and (not truncate-lines)
                 (>= (1+ column) (window-width))
                 (>= column (cursorcolumn-current-column))
                 (not (cursorcolumn-into-fringe-p)))
        (delete-overlay ovr)))

     ;; Handle fullwidth spaces
     ((and (not (null cursorcolumn-multiwidth-space-list))
           (memq char cursorcolumn-multiwidth-space-list))
      (setq str (concat str (make-string (- (save-excursion (forward-char)
                                                            (current-column))
                                            (current-column)
                                            (string-width str))
                                         ?\ )))
      (move-overlay ovr (point) (1+ (point)))
      (overlay-put ovr 'invisible t)
      (overlay-put ovr 'after-string str))

     ;; Check if composition should be used
     (compose-p (let (str)
                  (when char
                    (setq str (compose-chars
                               char
                               (cond ((= (char-width char) 1)
                                      '(tc . tc))

                                     ((= cur-column column)
                                      '(tc . tr))

                                     (t '(tc . tl)))
                               line-char))
                    (when face-p
                      (setq str (propertize str 'face (cursorcolumn-face visual-p))))
                    (move-overlay ovr (point) (1+ (point)))
                    (overlay-put ovr 'invisible t)
                    (overlay-put ovr 'after-string str))))

     ;; Check if faces should be used
     (face-p (move-overlay ovr (point) (1+ (point)))
             (overlay-put ovr 'face (cursorcolumn-face visual-p))))))

;; FIXME: Very slow
(defun cursorcolumn--update-overlay (cur-column column lcolumn i compose-p
                                                face-p line-char line-str
                                                visual-line-str
                                                point)
  ;; Adjust for characters that extend beyond the intended column
  ;; if column over the cursor's column (when tab or wide char appears).
  ;; (when (> cur-column column)
  ;;   (let ((lcol (current-column)))
  ;;     (backward-char)
  ;;     (setq cur-column (- cur-column (- lcol (current-column))))))
  (when (> cur-column column)
    (move-to-column column)
    (setq cur-column column)
    ;; FIXME The following was replaced because (move-to-column) can replace it
    ;; (let ((lcol (current-column)))
    ;;   (backward-char)
    ;;   (setq cur-column (- cur-column (- lcol (current-column)))))
    )

  ;; Setup overlay and strings for visual representation
  ;; FIXME: let slow
  (let* ((current-col (current-column))
         (visual-p (or (< lcolumn current-col)
                       (> lcolumn (+ current-col
                                     (- column cur-column)))))
         ;; Create string considering newline, tab, and wide characters.
         )

    (cursorcolumn--set-overlay-properties cur-column column i
                                          compose-p face-p line-char
                                          point visual-p line-str
                                          visual-line-str)))

(defun cursorcolumn-show (&optional point)
  ;; Clear existing column highlighting
  ;; (cursorcolumn-clear)

  ;; Preserve cursor position and execute the body
  (save-excursion
    ;; If a specific point is provided, move to it; otherwise, use the current point
    ;; This go to char is slow, according to the CPU and memory profiler:
    ;; 44% goto-char -> window-end -> jit-lock-function -> jit-lock-fontify-now -> jit-lock--run-functions
    (let ((current-point (point)))
      (if (and point (not (eq point current-point)))
          (goto-char point)
        (setq point current-point)))

    ;; Initialize variables for the operation
    (let* ((column (cursorcolumn-current-column))  ;; Calculate the current column of the cursor
           (lcolumn (current-column))              ;; Store the current column position
           (i 0)                                   ;; Initialize counter for overlay array
           (compose-p (memq cursorcolumn-style '(compose mixed)))  ;; Check if composition should be used
           (face-p (memq cursorcolumn-style '(face mixed)))        ;; Check if faces should be used
           (line-char (if compose-p cursorcolumn-line-char ?\ ))   ;; Decide on the character for the line
           (line-str (make-string 1 line-char))                    ;; Create a string with the line character
           (visual-line-str line-str)                              ;; Duplicate line string for visual lines
           (window-height (cursorcolumn--calculate-window-visible-lines))  ;; Calculate visible lines in window
           (length-overlay-table (length cursorcolumn-overlay-table))
           (in-fringe-p (cursorcolumn-into-fringe-p)))             ;; Check if the cursor is in the fringe area

      ;; If using faces, apply the designated face to the line string
      (when face-p
        (setq line-str (propertize line-str 'face (cursorcolumn-face nil)))
        (setq visual-line-str (propertize visual-line-str 'face (cursorcolumn-face t))))

      ;; Move to the end of the window
      (goto-char (window-end nil t))
      ;; Adjust position for showing the column line
      (cursorcolumn-forward 0)

      ;; Loop until all visible lines are processed or overlay table capacity is
      ;; reached
      (catch 'break
        (while (and (not in-fringe-p)
                    (< i window-height)
                    (< i length-overlay-table))
          (let ((cur-column (cursorcolumn-move-to-column column t)))
            (unless (= (point) point)
              ;; Only proceed if not on the original cursor line to prevent cluttering
              ;; non-cursor line only (workaround of eol probrem).
              (cursorcolumn--update-overlay cur-column column lcolumn i
                                            compose-p face-p line-char line-str
                                            visual-line-str point))

            (setq i (1+ i))
            (when (bobp)
              (throw 'break nil))
            (cursorcolumn-forward -1)))))))

(provide 'cursorcolumn)
;;; cursorcolumn.el ends here

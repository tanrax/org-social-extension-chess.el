;;; chess-org-social.el --- Play chess over Org Social  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Free Software Foundation, Inc.

;; Author: Andros Fenollosa <hi@andros.dev>
;; Version: 1.0.0
;; Package-Requires: ((emacs "25.1") (chess "2.0"))
;; Keywords: games, chess, network
;; URL: https://github.com/tanrax/org-social-extension-chess.el

;; This is free software; you can redistribute it and/or modify it under
;; the terms of the GNU General Public License as published by the Free
;; Software Foundation; either version 3, or (at your option) any later
;; version.
;;
;; This is distributed in the hope that it will be useful, but WITHOUT
;; ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
;; FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
;; for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; This module lets two Emacs Chess users play against each other using
;; Org Social posts as the transport layer.  Each chess move is published
;; as a post with `:BOT: chess <message>' in the player's social.org file.
;; Moves from the opponent are retrieved by polling their public feed.
;;
;; Requires the org-social.el client to be installed and configured.
;;
;; Quick start:
;;
;;   M-x chess-org-social
;;
;; You will be prompted to choose an opponent from your Org Social follows.
;; Once you accept or are challenged, moves are published automatically to
;; your social.org and the opponent's feed is polled for replies.
;;
;; Configuration:
;;   `chess-org-social-poll-interval' -- seconds between feed polls (default 30)
;;
;; The following org-social.el variables must be set:
;;   `org-social-file'          -- path to your local social.org
;;   `org-social-my-public-url' -- public URL of your social.org

;;; Code:

(require 'chess-network)
(require 'url)

(declare-function org-social-parser--get-my-profile "org-social-parser")
(declare-function org-social-file--new-bot-post "org-social-file")
(declare-function org-social-file--save "org-social-file")
(declare-function org-social-file--is-vfile-p "org-social-file")
(declare-function org-social-file--get-local-file-path "org-social-file")
(defvar org-social-file)
(defvar org-social-my-public-url)

(defgroup chess-org-social nil
  "Use Org Social posts for sending/receiving chess moves."
  :group 'chess-engine)

(defcustom chess-org-social-poll-interval 30
  "Seconds between polls of the opponent's Org Social feed."
  :type 'integer
  :group 'chess-org-social)

(chess-message-catalog 'english
  '((org-social-select-opponent . "Opponent (from your follows): ")
    (org-social-no-follows      . "No follows found in your social.org — add #+FOLLOW: lines first")
    (org-social-waiting         . "Waiting for opponent move via Org Social (polling every %ds)...")
    (org-social-published       . "Move published to social.org")
    (org-social-resuming        . "Resuming existing game via Org Social...")))

(defvar chess-org-social-opponent-url nil)
(defvar chess-org-social-opponent-last-id nil)
(defvar chess-org-social-my-last-id nil)
(defvar chess-org-social-poll-timer nil)
(defvar chess-org-social-game-active nil)

(make-variable-buffer-local 'chess-org-social-opponent-url)
(make-variable-buffer-local 'chess-org-social-opponent-last-id)
(make-variable-buffer-local 'chess-org-social-my-last-id)
(make-variable-buffer-local 'chess-org-social-poll-timer)
(make-variable-buffer-local 'chess-org-social-game-active)

(defvar chess-org-social-regexp-alist chess-network-regexp-alist
  "Regexp alist for chess-org-social, reusing the chess-network protocol.")

(defun chess-org-social--require-client ()
  "Signal an error if org-social.el is not available."
  (unless (require 'org-social-file nil t)
    (user-error "Org-social.el is required — install it from https://github.com/tanrax/org-social.el"))
  (unless (require 'org-social-parser nil t)
    (user-error "Org-social-parser not found — please update org-social.el")))

(defun chess-org-social--select-opponent ()
  "Prompt the user to pick an opponent from their Org Social follows.
Returns the feed URL of the chosen follow."
  (chess-org-social--require-client)
  (let* ((profile (org-social-parser--get-my-profile))
         (follows (alist-get 'follow profile)))
    (unless follows
      (user-error "%s" (chess-string 'org-social-no-follows)))
    (let* ((candidates (mapcar (lambda (f)
                                 (let* ((url  (alist-get 'url f))
                                        (nick (and url
                                                   (string-match
                                                    "/\\([^/]+\\)/social\\.org\\'" url)
                                                   (match-string 1 url))))
                                   (cons (or nick url) url)))
                               follows))
           (choice (completing-read (chess-string 'org-social-select-opponent)
                                    (mapcar #'car candidates)
                                    nil t)))
      (cdr (assoc choice candidates)))))

(defun chess-org-social--local-file ()
  "Return the local path of the social.org file.
Resolves vfile URLs to their local cache path."
  (if (and (fboundp 'org-social-file--is-vfile-p)
           (org-social-file--is-vfile-p org-social-file))
      (org-social-file--get-local-file-path org-social-file)
    org-social-file))

(defun chess-org-social--last-inserted-id ()
  "Return the ID (heading timestamp) of the most recently inserted post."
  (with-current-buffer (find-file-noselect (chess-org-social--local-file))
    (save-excursion
      (goto-char (point-max))
      (when (re-search-backward
             "^\\*\\* \\([0-9]\\{4\\}-[0-9][0-9]-[0-9][0-9]T[^\n]+\\)" nil t)
        (match-string-no-properties 1)))))

(defun chess-org-social--publish (bot-params body)
  "Publish a chess BOT post with BOT-PARAMS and human-readable BODY.
Sets REPLY_TO to the opponent's last post when available.
Returns the new post ID."
  (chess-org-social--require-client)
  (let ((reply-url (when chess-org-social-opponent-last-id
                     chess-org-social-opponent-url))
        (reply-id chess-org-social-opponent-last-id))
    (save-window-excursion
      (org-social-file--new-bot-post "chess" bot-params reply-url reply-id)
      (when body
        (with-current-buffer (find-file-noselect (chess-org-social--local-file))
          (insert body "\n")))
      (with-current-buffer (find-file-noselect (chess-org-social--local-file))
        (org-social-file--save)))
    (chess-message 'org-social-published)
    (chess-org-social--last-inserted-id)))

(defun chess-org-social--parse-chess-posts (content)
  "Parse Org Social CONTENT and return chess BOT posts as a list of alists.
Each alist has keys `id' and `params'."
  (let (posts)
    (with-temp-buffer
      (insert content)
      (goto-char (point-min))
      (while (re-search-forward
              "^\\*\\* \\([0-9]\\{4\\}-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9][^\n]*\\)"
              nil t)
        (let ((id (match-string-no-properties 1))
              (section-end (save-excursion
                             (or (re-search-forward "^\\*\\* " nil t)
                                 (point-max)))))
          (save-excursion
            (when (re-search-forward ":BOT: chess \\([^\n]+\\)" section-end t)
              (push `((id . ,id)
                      (params . ,(string-trim (match-string-no-properties 1))))
                    posts))))))
    (nreverse posts)))

(defun chess-org-social--fetch-sync (url)
  "Fetch URL synchronously with cache-busting; return body string or nil on error."
  (condition-case err
      (let ((buf (url-retrieve-synchronously
                  (concat url "?t=" (number-to-string (truncate (float-time))))
                  t nil 10)))
        (when (buffer-live-p buf)
          (with-current-buffer buf
            (goto-char (point-min))
            (prog1
                (when (re-search-forward "\r?\n\r?\n" nil t)
                  (buffer-substring-no-properties (point) (point-max)))
              (kill-buffer buf)))))
    (error
     (message "chess-org-social: fetch failed for %s: %s"
              url (error-message-string err))
     nil)))

(defun chess-org-social--game-active-p (my-posts opp-posts)
  "Return t if there is an ongoing game in MY-POSTS and OPP-POSTS combined."
  (let* ((all (sort (append (copy-sequence my-posts) (copy-sequence opp-posts))
                    (lambda (a b) (string< (alist-get 'id a) (alist-get 'id b)))))
         (in-game nil)
         (accepted nil))
    (dolist (post all)
      (let ((params (alist-get 'params post)))
        (cond
         ((string-prefix-p "match " params)
          (setq in-game t accepted nil))
         ((string-prefix-p "accept" params)
          (when in-game (setq accepted t)))
         ((member params '("resign" "draw" "abort"))
          (setq in-game nil accepted nil)))))
    (and in-game accepted)))

(defun chess-org-social--restore-state (opponent-url)
  "Set transport state by reading OPPONENT-URL and local feed synchronously.
Sets `chess-org-social-opponent-last-id' and `chess-org-social-game-active'.
Returns t if a game is in progress."
  (let* ((local-content
          (condition-case nil
              (with-current-buffer
                  (find-file-noselect (chess-org-social--local-file))
                (buffer-string))
            (error nil)))
         (opp-content (chess-org-social--fetch-sync opponent-url))
         (my-posts  (when local-content
                      (chess-org-social--parse-chess-posts local-content)))
         (opp-posts (when opp-content
                      (chess-org-social--parse-chess-posts opp-content)))
         (last-opp  (car (last opp-posts)))
         (active    (chess-org-social--game-active-p my-posts opp-posts)))
    (setq chess-org-social-opponent-last-id
          (when last-opp (alist-get 'id last-opp)))
    (setq chess-org-social-game-active active)
    active))

(defun chess-org-social--poll (engine-buf)
  "Fetch the opponent's feed and submit any new chess move to ENGINE-BUF."
  (when (buffer-live-p engine-buf)
    (let ((url  (with-current-buffer engine-buf chess-org-social-opponent-url))
          (last (with-current-buffer engine-buf chess-org-social-opponent-last-id)))
      (when url
        (url-retrieve
         (concat url "?t=" (number-to-string (truncate (float-time))))
         (lambda (_status buf last-id)
           (when (buffer-live-p buf)
             (goto-char (point-min))
             (re-search-forward "\r?\n\r?\n" nil t)
             (let ((body (buffer-substring-no-properties (point) (point-max))))
               (dolist (post (chess-org-social--parse-chess-posts body))
                 (let ((post-id (alist-get 'id post))
                       (params  (alist-get 'params post)))
                   (when (and post-id params
                              (or (null last-id) (string> post-id last-id)))
                     (with-current-buffer buf
                       (setq chess-org-social-opponent-last-id post-id)
                       ;; When receiving "match <url>", auto-set opponent URL
                       ;; so the challenger's feed is polled for subsequent moves.
                       (when (string-prefix-p "match " params)
                         (let ((feed-url (cadr (split-string params))))
                           (when (and feed-url (string-prefix-p "http" feed-url))
                             (setq chess-org-social-opponent-url feed-url))))
                       ;; Reconstruct "chess match ..." for chess-network regexp matching
                       (let ((msg (if (string-prefix-p "match " params)
                                      (concat "chess " params "\n")
                                    (concat params "\n")))
                             (game chess-module-game))
                         (chess-engine-submit nil msg)
                         ;; Opponent's move caused checkmate: publish resign to mark end
                         (when (and game
                                    (not (string-prefix-p "resign" params))
                                    (not (string-prefix-p "draw" params))
                                    (not (string-prefix-p "abort" params))
                                    (not (string-prefix-p "match " params))
                                    (not (string-prefix-p "accept" params))
                                    (chess-game-over-p game))
                           (chess-org-social--publish "resign" nil))))))))))
         (list engine-buf last)
         t t)))))

(defun chess-org-social-handler (game event &rest args)
  "Handle chess engine EVENT for GAME over Org Social."
  (cond
   ;; 'send must run even when chess-engine-handling-event is t, because
   ;; chess-engine-command sets that flag before dispatching any event,
   ;; including the 'send triggered by chess-network-handler inside 'match.
   ((eq event 'send)
    ;; Strip the leading "chess " prefix that chess-network adds to match/setup
    ;; messages so the BOT property stays clean: ":BOT: chess match URL"
    ;; instead of ":BOT: chess chess match URL".
    ;; For match, replace the player name with the public feed URL so
    ;; the recipient knows which feed to poll for subsequent moves.
    (let* ((raw (string-trim-right (car args) "\n"))
           (params (if (string-prefix-p "chess " raw)
                       (substring raw 6)
                     raw))
           (params (if (and org-social-my-public-url
                            (string-prefix-p "match " params))
                       (concat "match " org-social-my-public-url)
                     params))
           (new-id (chess-org-social--publish params nil)))
      (when new-id
        (setq chess-org-social-my-last-id new-id))
      ;; Our move caused checkmate: publish resign to mark the game as ended
      (when (and (not (member params '("resign" "draw" "abort")))
                 (not (string-prefix-p "match " params))
                 (not (string-prefix-p "accept" params))
                 (chess-game-over-p game))
        (chess-org-social--publish "resign" nil))))

   (chess-engine-handling-event nil)

   ((eq event 'initialize)
    (chess-org-social--require-client)
    (set (make-local-variable 'chess-org-social-opponent-url)
         (chess-org-social--select-opponent))
    (set (make-local-variable 'chess-org-social-opponent-last-id) nil)
    (set (make-local-variable 'chess-org-social-my-last-id) nil)
    (set (make-local-variable 'chess-org-social-game-active) nil)
    (chess-org-social--restore-state chess-org-social-opponent-url)
    (when chess-org-social-game-active
      (chess-message 'org-social-resuming))
    (let ((buf (current-buffer)))
      (set (make-local-variable 'chess-org-social-poll-timer)
           (run-at-time chess-org-social-poll-interval
                        chess-org-social-poll-interval
                        #'chess-org-social--poll buf)))
    (chess-message 'org-social-waiting chess-org-social-poll-interval)
    t)

   ((eq event 'ready)
    (chess-game-run-hooks game 'announce-autosave)
    (unless chess-org-social-game-active
      (chess-network-handler game 'match))
    t)

   ((eq event 'match)
    (chess-network-handler game 'match))

   ((eq event 'destroy)
    (when (timerp chess-org-social-poll-timer)
      (cancel-timer chess-org-social-poll-timer)))

   (t
    (apply #'chess-network-handler game event args))))

;;;###autoload
(defun chess-org-social ()
  "Start a chess game over Org Social.
Presents your Org Social follows list so you can pick an opponent.
Moves are published as `:BOT: chess' posts in your social.org and
the opponent's feed is polled every `chess-org-social-poll-interval' seconds."
  (interactive)
  (chess 'chess-org-social))

(provide 'chess-org-social)

;;; chess-org-social.el ends here

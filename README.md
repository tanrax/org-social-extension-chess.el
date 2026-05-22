# chess-org-social.el

Play chess over [Org Social](https://github.com/tanrax/org-social.el) posts. End-to-end tested with two real accounts on a live host.

Each move is published as a `:BOT: chess` entry in your `social.org` file. Your opponent's feed is polled automatically for replies. No server, no IRC, no extra infrastructure: just two `social.org` files and HTTP.

## Requirements

- Emacs 25.1 or later
- [emacs-chess](https://github.com/jwiegley/emacs-chess)
- [org-social.el](https://github.com/tanrax/org-social.el) configured with `org-social-file` and `org-social-my-public-url`
- At least one `#+FOLLOW:` entry pointing to your opponent in your `social.org`

## Installation

### From MELPA (once available)

Both dependencies are available on MELPA. Install them first:

```
M-x package-install RET chess RET
M-x package-install RET org-social RET
```

Then clone or copy `chess-org-social.el` into your `load-path` and add:

```elisp
(require 'chess-org-social)
```

### From a local clone (use-package)

Clone the repository and point `use-package` at it with `:load-path`. The `:after` clause ensures both dependencies are loaded first:

```elisp
(use-package chess-org-social
  :load-path "~/path/to/org-social-extension-chess.el"
  :after (chess org-social))
```

### Configuration

Set these two variables to match your Org Social setup before playing:

```elisp
(setq org-social-file "/path/to/your/social.org")
(setq org-social-my-public-url "https://yourhost.example.com/you/social.org")
```

Optionally adjust the poll interval (default: 30 seconds):

```elisp
(setq chess-org-social-poll-interval 30)
```

## How to play

### Starting a game

Both players run:

```
M-x chess-org-social
```

Each player picks the other from their follows list. The first player to run the command publishes a match challenge automatically. The second player selects the first as opponent: the challenge is detected on the next poll and accepted automatically.

After that, moves alternate: each move is published to your `social.org` and the opponent's feed is polled every `chess-org-social-poll-interval` seconds until their reply arrives.

### Resuming a game

If you close Emacs mid-game, just run `M-x chess-org-social` again and pick the same opponent. Both feeds are scanned on startup to restore the game state: no moves are replayed and no duplicate challenge is sent.

### Ending a game

- **Resign:** use the standard chess resign command in Emacs Chess.
- **Draw:** offer a draw through the Emacs Chess interface.
- **Checkmate:** detected automatically; a `resign` marker is published so future sessions know the game is over.

## How it works

- Each move is published as a `:BOT: chess` post in the player's `social.org` via `org-social-file--new-bot-post`
- The opponent is selected from the user's existing Org Social follows list: the nick is extracted from the follow URL, no URLs to type manually
- The match challenge is sent automatically when the engine starts: no manual step needed
- Opponent moves are received by polling their public feed via `url-retrieve` every `chess-org-social-poll-interval` seconds; poll URLs include a timestamp query parameter to bypass CDN caches
- On startup, both feeds are fetched synchronously to detect a game in progress and set the last-seen post ID, so reopening Emacs mid-game works correctly
- Saving and uploading is handled entirely by `org-social-file--save`: no extra configuration needed
- `match` posts carry the player's public feed URL (`org-social-my-public-url`) so the recipient knows which feed to poll for subsequent moves

## How a game looks in social.org

Real output from a live test between two accounts:

**chess-player-a** (initiator):

```org
** 2026-05-21T13:44:22+0200
:PROPERTIES:
:CLIENT: org-social.el
:BOT: chess match https://host.org-social.org/chess-player-a/social.org
:END:

** 2026-05-21T13:44:45+0200
:PROPERTIES:
:CLIENT: org-social.el
:REPLY_TO: https://host.org-social.org/chess-player-b/social.org#2026-05-21T13:40:38+0200
:BOT: chess accept https://host.org-social.org/chess-player-b/social.org
:END:

** 2026-05-21T13:44:58+0200
:PROPERTIES:
:CLIENT: org-social.el
:REPLY_TO: https://host.org-social.org/chess-player-b/social.org#2026-05-21T13:40:38+0200
:BOT: chess e3
:END:

** 2026-05-21T13:46:26+0200
:PROPERTIES:
:CLIENT: org-social.el
:REPLY_TO: https://host.org-social.org/chess-player-b/social.org#2026-05-21T13:46:12+0200
:BOT: chess Nf3
:END:
```

**chess-player-b** (responder):

```org
** 2026-05-21T13:45:44+0200
:PROPERTIES:
:CLIENT: org-social.el
:BOT: chess match https://host.org-social.org/chess-player-b/social.org
:END:

** 2026-05-21T13:45:57+0200
:PROPERTIES:
:CLIENT: org-social.el
:REPLY_TO: https://host.org-social.org/chess-player-a/social.org#2026-05-21T13:44:22+0200
:BOT: chess accept https://host.org-social.org/chess-player-a/social.org
:END:

** 2026-05-21T13:46:12+0200
:PROPERTIES:
:CLIENT: org-social.el
:REPLY_TO: https://host.org-social.org/chess-player-a/social.org#2026-05-21T13:45:50+0200
:BOT: chess d6
:END:
```

Each post is one protocol message, chained via `:REPLY_TO:` to the previous post. Clients that do not recognise `:BOT: chess` display them as regular posts.

## Protocol

The module reuses the `chess-network` text protocol over Org Social posts:

| Post `:BOT: chess ...` | Meaning |
|---|---|
| `match <feed-url>` | Challenge: my feed URL for polling |
| `accept <feed-url>` | Accept challenge |
| `e4`, `Nf3`, ... | Move in SAN notation |
| `resign` | Resign or end-of-game marker |
| `draw` | Offer / accept draw |

## License

GPL-3.0-or-later

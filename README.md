# chess-org-social.el

Play chess over [Org Social](https://github.com/tanrax/org-social.el) posts. End-to-end tested with two real accounts on a live host.

Each move is published as a `:BOT: chess` entry in your `social.org` file. Your opponent's feed is polled automatically for replies. No server, no IRC, no extra infrastructure — just two `social.org` files and HTTP.

## How it works

- Each move is published as a `:BOT: chess` post in the player's `social.org` via `org-social-file--new-bot-post`
- The opponent is selected from the user's existing Org Social follows list — no URLs to type manually; the nick is extracted from the follow URL
- The match challenge is sent automatically when the engine starts — no manual step needed
- Opponent moves are received by polling their public feed via `url-retrieve` every `chess-org-social-poll-interval` seconds (default 30); poll URLs include a timestamp query parameter to bypass CDN caches
- Saving and uploading is handled entirely by `org-social-file--save` — no extra configuration needed
- `match` posts carry the player's public feed URL (`org-social-my-public-url`) so the recipient knows which feed to poll for subsequent moves

## Requirements

- [emacs-chess](https://github.com/jwiegley/emacs-chess)
- [org-social.el](https://github.com/tanrax/org-social.el) configured with `org-social-file` and `org-social-my-public-url`
- At least one `#+FOLLOW:` entry pointing to your opponent in your `social.org`

## Installation

Clone or copy `chess-org-social.el` somewhere in your `load-path`, then:

```elisp
(require 'chess-org-social)
```

## Usage

```
M-x chess-org-social
```

You will be prompted to choose an opponent from your follows list. The match challenge is published immediately and the opponent's feed is polled for replies. Your opponent runs the same command, selects you, and accepts the challenge when prompted.

## Configuration

```elisp
(setq chess-org-social-poll-interval 30) ; seconds between feed polls
```

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
| `resign` | Resign |
| `draw` | Offer / accept draw |

## License

GPL-3.0-or-later

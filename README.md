# chess-org-social.el

Play chess over [Org Social](https://github.com/tanrax/org-social.el) posts.

Each move is published as a `:BOT: chess` entry in your `social.org` file. Your opponent's feed is polled automatically for replies. No server, no IRC, no extra infrastructure — just two `social.org` files and HTTP.

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

You will be prompted to pick an opponent from your Org Social follows list. The match challenge is published immediately and your opponent's feed is polled every `chess-org-social-poll-interval` seconds (default: 30).

Your opponent runs the same command, selects you as opponent, and accepts the challenge when prompted.

## Configuration

```elisp
(setq chess-org-social-poll-interval 30) ; seconds between feed polls
```

## How it looks in social.org

**Player A:**

```org
** 2026-05-21T13:44:22+0200
:PROPERTIES:
:CLIENT: org-social.el
:BOT: chess match https://host.example.org/player-a/social.org
:END:

** 2026-05-21T13:44:58+0200
:PROPERTIES:
:CLIENT: org-social.el
:REPLY_TO: https://host.example.org/player-b/social.org#2026-05-21T13:40:38+0200
:BOT: chess e3
:END:

** 2026-05-21T13:46:26+0200
:PROPERTIES:
:CLIENT: org-social.el
:REPLY_TO: https://host.example.org/player-b/social.org#2026-05-21T13:46:12+0200
:BOT: chess Nf3
:END:
```

**Player B:**

```org
** 2026-05-21T13:45:57+0200
:PROPERTIES:
:CLIENT: org-social.el
:REPLY_TO: https://host.example.org/player-a/social.org#2026-05-21T13:44:22+0200
:BOT: chess accept https://host.example.org/player-a/social.org
:END:

** 2026-05-21T13:46:12+0200
:PROPERTIES:
:CLIENT: org-social.el
:REPLY_TO: https://host.example.org/player-a/social.org#2026-05-21T13:45:50+0200
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

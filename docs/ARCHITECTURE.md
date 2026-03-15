# Architecture Overview

Bookmoves is a Phoenix LiveView app built around a small set of domain modules and LiveViews. The
core model is a tree of chess positions where each move is represented as a position node.

## High-Level Structure

- `Bookmoves.Repertoire` is the main context. It owns queries, scheduling logic, and persistence for
  positions.
- `Bookmoves.Repertoire.Position` is the Ecto schema for each node in the opening tree.
- `Bookmoves.Repertoire.PgnImport` parses PGN server-side and converts it into canonical move attrs.
- `Bookmoves.ReviewBatch` builds review/practice batches (including due step chains with board
  context).
- `BookmovesWeb.RepertoireLive.*` contains the LiveViews for review, add, show, and PGN import
  flows.

## Data Model

Each position is a node in a repertoire tree.

- `fen` is the board state after the move.
- `parent_fen` links to the previous position in the tree.
- `san` is the move played from `parent_fen`.
- Move identity is branch-aware and deduped by `(parent_fen, san, fen)` per user+repertoire.
- `color_side` is the repertoire side (white/black).
- `move_color` is the side to move for the position.
- `next_review_at`, `last_reviewed_at`, `interval_days`, `ease_factor`, and `repetitions` power
  scheduling.

Deletion behavior:

- Deleting a position removes its full descendant subtree in the same user+repertoire scope, so
  branches are not orphaned.

## Review Flow

The review experience focuses on due positions for the current side and batches them to keep
sessions focused.

1. `Bookmoves.ReviewBatch.build_due_step_chains_batch/4` selects due positions and builds step
   chains with explicit `board_position` context and configurable chain limit.
2. `BookmovesWeb.RepertoireLive.Review` consumes these step chains, presenting one due step at a
   time.
3. When the current chain finishes, the LiveView advances to the next chain. When all chains are
   done, it shows the batch-complete prompt and counts remaining due positions.

Practice flow:

- `Bookmoves.ReviewBatch.build_practice_chains_batch/4` builds practice batches without updating
  spaced repetition scheduling.

Configuration:

- `:review_batch_size` controls the number of due moves per batch (default: 20).
- `:review_chain_limit` controls the maximum length of a linear chain (default: 3).
- `:pgn_parse_timeout_ms` controls PGN parse timeout for server-side imports (default: 1500).

## LiveView Responsibilities

- `RepertoireLive.Review` handles the review session, scoring, and batch progression.
- `RepertoireLive.Add` supports move input via the chessboard.
- `RepertoireLive.ImportPgn` handles PGN upload and import feedback.
- `RepertoireLive.Show` displays repertoire stats and navigation.

## Notable Design Choices

- Review batching is built once per batch to avoid repeated database reads while the user is
  answering moves.
- Non-due but correct moves are acknowledged without penalty.
- PGN import is fully server-validated (lexer/parser + legal move replay) before persistence.
- Openings material sharding details and tuning notes are documented in
  `docs/OPENINGS_MATERIAL_SHARDING.md`.

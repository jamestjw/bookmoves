# Architecture Overview

Bookmoves is a Phoenix LiveView app built around a small set of domain modules and LiveViews. The
core model is a tree of chess positions where each move is represented as a position node.

## High-Level Structure

- `Bookmoves.Repertoire` is the main context. It owns queries, scheduling logic, and persistence for
  positions.
- `Bookmoves.Repertoire.Position` is the Ecto schema for each node in the opening tree.
- `Bookmoves.ReviewBatch` builds linear chains of due positions for review batches.
- `BookmovesWeb.RepertoireLive.*` contains the LiveViews for review, add, and show flows.

## Data Model

Each position is a node in a repertoire tree.

- `fen` is the board state and primary identifier.
- `parent_fen` links to the previous position in the tree.
- `color_side` is the repertoire side (white/black).
- `move_color` is the side to move for the position.
- `next_review_at`, `last_reviewed_at`, `interval_days`, `ease_factor`, and `repetitions` power
  scheduling.

## Review Flow

The review experience focuses on due positions for the current side and batches them to keep
sessions focused.

1. `Bookmoves.ReviewBatch.build_due_chains_batch/2` selects due positions and builds linear chains
   with a configurable chain limit.
2. `BookmovesWeb.RepertoireLive.Review` consumes these chains, presenting one due position at a
   time.
3. When the current chain finishes, the LiveView advances to the next chain. When all chains are
   done, it shows the batch-complete prompt and counts remaining due positions.

Configuration:

- `:review_batch_size` controls the number of due moves per batch (default: 20).
- `:review_chain_limit` controls the maximum length of a linear chain (default: 3).

## LiveView Responsibilities

- `RepertoireLive.Review` handles the review session, scoring, and batch progression.
- `RepertoireLive.Add` supports move input via the chessboard.
- `RepertoireLive.Show` displays repertoire stats and navigation.

## Notable Design Choices

- Review batching is built once per batch to avoid repeated database reads while the user is
  answering moves.
- Non-due but correct moves are acknowledged without penalty.

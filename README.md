# Bookmoves

Bookmoves is a Phoenix LiveView app for spaced repetition training of chess opening repertoires.

## Features

- **Repertoire Management**: Create multiple named repertoires per side (White/Black)
- **Board-Based Input**: Add moves by dragging pieces on an interactive chessboard
- **Tree Visualization**: See your full repertoire as a tree with saved and pending moves
- **Spaced Repetition**: Automatic scheduling using simplified SM-2 algorithm
- **Batch Review**: Review due moves in batches with short linear chains
- **Practice Mode**: Review random moves without affecting spaced repetition
- **PGN Import**: Import full PGN lines (including nested variations) server-side
- **Branch-Aware Trees**: Store move identity as parent FEN + SAN + FEN to preserve transpositions
- **User Accounts**: Register and log in to access your own repertoires

## Future features

- Add preset opening repertoires that users can import
- Allow disabling training for a specific branch in a repertoire
- Practice mode for a specific subtree in a repertoire

## Getting Started

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`
* Visit [`localhost:4000`](http://localhost:4000) from your browser

## Usage

1. Sign in and open the Repertoires page
2. Create a repertoire by choosing a name and side (White/Black)
3. Open the repertoire and click "View/Add Moves"
4. Optionally use "Import PGN" to import lines from a PGN file
5. Drag pieces on the board to add moves and navigate by clicking saved moves
6. Start "Review" for due moves or "Practice" for random moves in that repertoire

## Architecture

See `docs/ARCHITECTURE.md` for a short walkthrough of the core modules and review flow.

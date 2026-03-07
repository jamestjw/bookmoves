# Bookmoves

Bookmoves is a Phoenix LiveView app for spaced repetition training of chess opening repertoires.

## Features

- **Repertoire Management**: Build opening trees for White and Black sides
- **Board-Based Input**: Add moves by dragging pieces on an interactive chessboard
- **Tree Visualization**: See your full repertoire as a tree with saved and pending moves
- **Spaced Repetition**: Automatic scheduling using simplified SM-2 algorithm
- **Batch Review**: Review due moves in batches with short linear chains
- **Practice Mode**: Review random moves without affecting spaced repetition
- **Transposition Handling**: Same positions are merged automatically

## Future features

- Support multiple users
- Users can have multiple repertoires for each colour
- Add preset opening repertoires that users can import
- Allow users to add moves via PGN
- Practice mode for a specific subtree in the repertoire

## Getting Started

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`
* Visit [`localhost:4000`](http://localhost:4000) from your browser

## Usage

1. Select your side (White or Black) from the home page
2. Click "Add Moves" to build your repertoire
3. Drag pieces on the board to add moves
4. Navigate the tree by clicking on moves
5. Click "Save All" to persist your changes
6. Return to your repertoire and click "Review" to practice

## Architecture

See `docs/ARCHITECTURE.md` for a short walkthrough of the core modules and review flow.

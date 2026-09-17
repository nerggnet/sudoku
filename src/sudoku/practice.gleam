//// Puzzles kept to be practised on, one to a technique.
////
//// The help explains each way of working a digit out and draws a small
//// board showing it happening. What it could not do was hand you one to
//// try, and a technique read about and never met is a technique nobody
//// learns: an X-wing turns up in about one dealt Expert puzzle in fifteen,
//// so waiting for one to come round is not a plan.
////
//// Each grid here was carved until the reasoning needed its technique and
//// needed nothing harder, and then given back every clue it could take
//// while that stayed true. So they are the gentlest grids that still force
//// their lesson: the X-wing one has fifty-seven clues and asks for its
//// X-wing on the second step, rather than being a seventeen-clue monster
//// that happens to contain one somewhere.
////
//// They are the same puzzle every time, which is the point — a lesson you
//// can go back to, and compare notes on with somebody else. Nothing is
//// timed and no record is kept of them.

import gleam/list
import gleam/result
import sudoku/board
import sudoku/generator.{type Puzzle}
import sudoku/logic.{type Technique}

/// The grid kept for each technique, as the 81 characters any of them can be
/// written in. Every one of them has exactly one answer, can be reasoned out
/// without a guess, and is rated at the technique it is filed under — which
/// is a test rather than a promise, since none of that is visible by eye.
pub const grids = [
  #(
    logic.NakedSingle,
    ".12.3..4..78..1.6..4.26.8..18....2.65967.24384.3....91..4.56.2..6.9..38..5..2.67.",
  ),
  #(
    logic.HiddenSingle,
    "837.1.2....43..5...5...63..6..5..87....6.9....73..2..5..12...5...6..47....5.9.683",
  ),
  #(
    logic.LockedCandidates,
    "537981..4.61..59..49..671..7436198..615872439.2...3..1.7..24.18..41...9.1..79.34.",
  ),
  #(
    logic.NakedPair,
    "745198632.9.4768158612534..1..769543..9.4.7..4...8.9..91.63425...48271.....9153.4",
  ),
  #(
    logic.HiddenPair,
    "93521..64...4.9.53.745.312941.3.65.2.6.9..3413..1.46.82..69143..9384521..4.73298.",
  ),
  #(
    logic.NakedTriple,
    "3.8..6...69.8.....12..9.8632.31.96...8634217.41.6.53.27.2.6..188.....256.6.2.873.",
  ),
  #(
    logic.XWing,
    "4239651871.83276...76148.2..1478..622.7.168.968...271..6285.4717.16.42.884.271..6",
  ),
  #(
    logic.XYWing,
    "6..718.29271459.6.98.3627..3569471828.76..9...9.8...765..1.6..7..82.36.5.695.423.",
  ),
  #(
    logic.Swordfish,
    "486217593913..54275279436812947.1.56378596214651.2.....451.2...162.79..5.39.5.1.2",
  ),
]

/// The number the menu offers practice under: the one after the puzzles
/// there are to deal, whatever those turn out to be.
pub fn choice() -> Int {
  list.length(generator.origins()) + 1
}

/// The techniques there is a puzzle for, easiest first — which is every one
/// of them, in the order the help pages them.
pub fn techniques() -> List(Technique) {
  list.map(grids, fn(kept) { kept.0 })
}

/// The puzzle kept for practising this technique.
///
/// Solved on the way out, the same as a puzzle typed in by hand, rather than
/// having its answer written down beside it here. The answer is not the
/// interesting part of a grid and would be eighty-one more characters to get
/// wrong by hand.
pub fn puzzle(technique: Technique) -> Result(Puzzle, Nil) {
  use clues <- result.try(list.key_find(grids, technique))
  use grid <- result.try(board.parse(clues))

  generator.made_of(grid, generator.Practising(technique))
  |> result.replace_error(Nil)
}

/// How many clues the grid for a technique is dealt with, for the screen
/// offering them to say how much of a puzzle each one is.
pub fn clue_count(technique: Technique) -> Int {
  case list.key_find(grids, technique) |> result.try(board.parse) {
    Error(_) -> 0
    Ok(grid) -> board.cell_count - board.empty_count(board.from_grid(grid))
  }
}

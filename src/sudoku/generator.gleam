//// Puzzle generation.
////
//// Fill a grid at random, then keep carving clues out of it for as long as
//// the puzzle still has exactly one solution. Cells are removed in
//// rotationally symmetric pairs, which is what hand-made puzzles look like;
//// if that alone does not reach the target clue count, a second pass removes
//// single cells.

import gleam/dict
import gleam/list
import sudoku/board.{type Board, type Grid, type Peers}
import sudoku/random
import sudoku/solver

pub type Difficulty {
  Easy
  Medium
  Hard
  Expert
}

/// Where a puzzle came from: carved out of a random grid at one of the
/// difficulties, or typed in by hand from a newspaper.
pub type Origin {
  Dealt(Difficulty)
  Handwritten
}

pub type Puzzle {
  Puzzle(board: Board, solution: Grid, origin: Origin)
}

/// The difficulties a puzzle can be dealt at, in menu order. A handwritten
/// puzzle is not among them: its clues are typed in rather than carved out,
/// so how hard it is was settled by whoever wrote it.
pub const difficulties = [Easy, Medium, Hard, Expert]

pub fn label(difficulty: Difficulty) -> String {
  case difficulty {
    Easy -> "Easy"
    Medium -> "Medium"
    Hard -> "Hard"
    Expert -> "Expert"
  }
}

/// How a puzzle is named on screen.
pub fn origin_label(origin: Origin) -> String {
  case origin {
    Dealt(difficulty) -> label(difficulty)
    Handwritten -> "Custom"
  }
}

/// Roughly how many clues to leave behind. Fewer clues means more searching,
/// so this is also what makes generation slower at the hard end.
pub fn target_clues(difficulty: Difficulty) -> Int {
  case difficulty {
    Easy -> 45
    Medium -> 36
    Hard -> 30
    Expert -> 26
  }
}

pub fn generate(difficulty: Difficulty) -> Puzzle {
  let peers = board.peers_table()
  let assert Ok(solution) = solver.search(peers, board.empty_grid(), True)
    as "an empty grid always has a solution"

  let target = target_clues(difficulty)

  let grid =
    solution
    |> carve(peers, symmetric_groups(), target, _)
    |> carve(peers, single_groups(), target, _)

  Puzzle(
    board: board.from_grid(grid),
    solution: solution,
    origin: Dealt(difficulty),
  )
}

// ---------------------------------------------------------------------------
// Puzzles typed in by hand
// ---------------------------------------------------------------------------

/// Why a hand-entered grid cannot be played.
pub type Rejection {
  /// Two of the same digit share a row, column or box.
  Clashes
  /// The clues obey the rules but cannot all be true at once.
  Unsolvable
  /// The clues can be finished in more than one way.
  Ambiguous
}

/// Turn a grid of hand-entered clues into a playable puzzle.
///
/// Play needs the answer as well as the clues, since checking and hints have
/// nothing to work from without it, so the grid has to have exactly one. That
/// also catches the usual slips in copying a puzzle out of a newspaper: a
/// mistyped digit leaves the grid unsolvable, and a missed one leaves it with
/// several answers.
pub fn from_clues(clues: Grid) -> Result(Puzzle, Rejection) {
  case board.is_consistent(clues) {
    False -> Error(Clashes)
    True -> {
      let peers = board.peers_table()
      // Counting stops at two, which is all it takes to know the answer is
      // not unique.
      case solver.count(peers, clues, 2) {
        0 -> Error(Unsolvable)
        1 ->
          case solver.search(peers, clues, False) {
            Ok(solution) ->
              Ok(Puzzle(
                board: board.from_grid(clues),
                solution: solution,
                origin: Handwritten,
              ))
            Error(_) -> Error(Unsolvable)
          }
        _ -> Error(Ambiguous)
      }
    }
  }
}

/// Cells paired with their 180-degree rotation, centre cell on its own.
fn symmetric_groups() -> List(List(Int)) {
  board.span(0, board.cell_count / 2 - 1)
  |> list.map(fn(index) { [index, board.cell_count - 1 - index] })
  |> list.prepend([board.cell_count / 2])
  |> random.shuffle
}

fn single_groups() -> List(List(Int)) {
  board.indices() |> list.map(fn(index) { [index] }) |> random.shuffle
}

fn carve(
  peers: Peers,
  groups: List(List(Int)),
  target: Int,
  grid: Grid,
) -> Grid {
  use grid, group <- list.fold(groups, grid)

  case clue_count(grid) <= target {
    True -> grid
    False -> {
      let stripped =
        list.fold(group, grid, fn(grid, index) { dict.insert(grid, index, 0) })
      case solver.count(peers, stripped, 2) == 1 {
        True -> stripped
        False -> grid
      }
    }
  }
}

fn clue_count(grid: Grid) -> Int {
  grid |> dict.values |> list.count(fn(digit) { digit != 0 })
}

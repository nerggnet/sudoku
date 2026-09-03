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

pub type Puzzle {
  Puzzle(board: Board, solution: Grid, difficulty: Difficulty)
}

pub const difficulties = [Easy, Medium, Hard, Expert]

pub fn label(difficulty: Difficulty) -> String {
  case difficulty {
    Easy -> "Easy"
    Medium -> "Medium"
    Hard -> "Hard"
    Expert -> "Expert"
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

  Puzzle(board: board.from_grid(grid), solution: solution, difficulty:)
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

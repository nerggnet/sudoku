//// A backtracking solver.
////
//// At every step it expands the empty cell with the fewest candidates left
//// ("minimum remaining values"), which keeps the search tree small enough
//// that plain recursion is fast on a 9x9 grid.

import gleam/dict
import gleam/list
import gleam/option.{type Option, None, Some}
import sudoku/board.{type Grid, type Peers}
import sudoku/random

/// Solve a grid, preferring low digits. Deterministic for a given input.
pub fn solve(grid: Grid) -> Result(Grid, Nil) {
  case board.is_consistent(grid) {
    False -> Error(Nil)
    True -> search(board.peers_table(), grid, False)
  }
}

/// Solve a grid, trying candidates in random order. Solving the empty grid
/// this way is how puzzles get generated.
pub fn solve_random(grid: Grid) -> Result(Grid, Nil) {
  case board.is_consistent(grid) {
    False -> Error(Nil)
    True -> search(board.peers_table(), grid, True)
  }
}

/// Count solutions, giving up once `limit` have been found. Used to check
/// that a puzzle has exactly one answer.
pub fn count_solutions(grid: Grid, limit: Int) -> Int {
  case board.is_consistent(grid) {
    False -> 0
    True -> count(board.peers_table(), grid, limit)
  }
}

/// The search itself. It only ever looks at empty cells, so the caller is
/// responsible for having checked that the digits already placed do not
/// clash; feeding it a contradictory grid means an exhaustive hunt for a
/// solution that cannot exist.
pub fn search(peers: Peers, grid: Grid, shuffled: Bool) -> Result(Grid, Nil) {
  case most_constrained(board.indices(), peers, grid, None) {
    None -> Ok(grid)
    Some(#(_, [], _)) -> Error(Nil)
    Some(#(index, candidates, _)) -> {
      let candidates = case shuffled {
        True -> random.shuffle(candidates)
        False -> candidates
      }
      try_candidates(peers, grid, index, candidates, shuffled)
    }
  }
}

fn try_candidates(
  peers: Peers,
  grid: Grid,
  index: Int,
  candidates: List(Int),
  shuffled: Bool,
) -> Result(Grid, Nil) {
  case candidates {
    [] -> Error(Nil)
    [digit, ..rest] ->
      case search(peers, dict.insert(grid, index, digit), shuffled) {
        Ok(solved) -> Ok(solved)
        Error(_) -> try_candidates(peers, grid, index, rest, shuffled)
      }
  }
}

/// Like `search`, this assumes the grid it is handed is consistent.
pub fn count(peers: Peers, grid: Grid, limit: Int) -> Int {
  case most_constrained(board.indices(), peers, grid, None) {
    None -> 1
    Some(#(_, [], _)) -> 0
    Some(#(index, candidates, _)) ->
      count_candidates(peers, grid, index, candidates, limit, 0)
  }
}

fn count_candidates(
  peers: Peers,
  grid: Grid,
  index: Int,
  candidates: List(Int),
  limit: Int,
  found: Int,
) -> Int {
  case candidates, found >= limit {
    _, True -> found
    [], _ -> found
    [digit, ..rest], _ -> {
      let found =
        found + count(peers, dict.insert(grid, index, digit), limit - found)
      count_candidates(peers, grid, index, rest, limit, found)
    }
  }
}

/// The empty cell with the fewest candidates, along with those candidates and
/// how many there are. `None` means the grid is full.
///
/// Bails out early on a cell with no candidates (the grid is unsolvable) or
/// one with a single candidate (nothing can beat it).
fn most_constrained(
  remaining: List(Int),
  peers: Peers,
  grid: Grid,
  best: Option(#(Int, List(Int), Int)),
) -> Option(#(Int, List(Int), Int)) {
  case remaining {
    [] -> best
    [index, ..rest] ->
      case dict.get(grid, index) {
        Ok(0) -> {
          let candidates = board.candidates(grid, peers, index)
          let count = list.length(candidates)
          let found = #(index, candidates, count)
          case count, best {
            0, _ -> Some(found)
            1, _ -> Some(found)
            _, Some(#(_, _, best_count)) if best_count <= count ->
              most_constrained(rest, peers, grid, best)
            _, _ -> most_constrained(rest, peers, grid, Some(found))
          }
        }
        _ -> most_constrained(rest, peers, grid, best)
      }
  }
}

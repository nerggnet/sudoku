//// The 9x9 grid and the rules that govern it.
////
//// Cells are addressed by a single index in the range 0..80, counting left
//// to right and then top to bottom. A digit of `0` stands for an empty cell.

import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/set.{type Set}
import gleam/string

/// The length of one side of the grid.
pub const side = 9

/// How many cells the grid holds.
pub const cell_count = 81

/// A grid of digits, keyed by cell index. `0` means the cell is empty.
pub type Grid =
  Dict(Int, Int)

/// For each cell, the 20 other cells that share a row, column or box with it.
pub type Peers =
  Dict(Int, Set(Int))

/// A puzzle being played: the digits currently on the grid, plus the cells
/// that were dealt as clues and so cannot be edited.
pub type Board {
  Board(values: Grid, givens: Set(Int))
}

/// The integers from `start` to `stop` inclusive, ascending. The standard
/// library only offers `int.range`, which folds rather than building a list.
pub fn span(start: Int, stop: Int) -> List(Int) {
  int.range(from: stop, to: start - 1, with: [], run: list.prepend)
}

/// Every cell index, in reading order.
pub fn indices() -> List(Int) {
  span(0, cell_count - 1)
}

pub fn empty_grid() -> Grid {
  indices()
  |> list.map(fn(index) { #(index, 0) })
  |> dict.from_list
}

pub fn row_of(index: Int) -> Int {
  index / side
}

pub fn col_of(index: Int) -> Int {
  index % side
}

pub fn box_of(index: Int) -> Int {
  row_of(index) / 3 * 3 + col_of(index) / 3
}

pub fn at(row: Int, col: Int) -> Int {
  row * side + col
}

/// The 27 groups of nine cells that must each hold the digits 1-9 exactly
/// once: nine rows, nine columns and nine boxes.
pub fn units() -> List(List(Int)) {
  let digits = span(0, side - 1)

  let rows =
    list.map(digits, fn(row) { list.map(digits, fn(col) { at(row, col) }) })

  let cols =
    list.map(digits, fn(col) { list.map(digits, fn(row) { at(row, col) }) })

  let boxes =
    list.map(digits, fn(box) {
      let top = box / 3 * 3
      let left = box % 3 * 3
      list.flat_map(span(0, 2), fn(row) {
        list.map(span(0, 2), fn(col) { at(top + row, left + col) })
      })
    })

  list.flatten([rows, cols, boxes])
}

/// Build the peer lookup table. This is mildly expensive, so solvers take it
/// as an argument and reuse a single table across a whole search.
pub fn peers_table() -> Peers {
  use table, unit <- list.fold(units(), dict.new())
  use table, index <- list.fold(unit, table)

  let others =
    unit |> list.filter(fn(other) { other != index }) |> set.from_list
  use existing <- dict.upsert(table, index)
  case existing {
    Some(peers) -> set.union(peers, others)
    None -> others
  }
}

/// The digits that could legally go in an empty cell, ignoring any deeper
/// reasoning about the rest of the grid.
pub fn candidates(grid: Grid, peers: Peers, index: Int) -> List(Int) {
  let taken = case dict.get(peers, index) {
    Ok(cells) ->
      set.fold(cells, set.new(), fn(taken, peer) {
        case dict.get(grid, peer) {
          Ok(0) | Error(_) -> taken
          Ok(digit) -> set.insert(taken, digit)
        }
      })
    Error(_) -> set.new()
  }

  span(1, side) |> list.filter(fn(digit) { !set.contains(taken, digit) })
}

/// Read a grid from 81 digits, where `.`, `_` and `0` all mean "empty".
/// Anything else, including whitespace and newlines, is ignored, so grids can
/// be written out over several lines.
pub fn parse(text: String) -> Result(Grid, Nil) {
  let digits = {
    use character <- list.filter_map(string.to_graphemes(text))
    case character {
      "." | "_" | "0" -> Ok(0)
      _ -> int.parse(character)
    }
  }

  case list.length(digits) == cell_count {
    False -> Error(Nil)
    True ->
      Ok(
        digits
        |> list.index_map(fn(digit, index) { #(index, digit) })
        |> dict.from_list,
      )
  }
}

/// The inverse of `parse`: 81 characters on one line.
pub fn to_string(grid: Grid) -> String {
  indices()
  |> list.map(fn(index) {
    case dict.get(grid, index) {
      Ok(0) | Error(_) -> "."
      Ok(digit) -> int.to_string(digit)
    }
  })
  |> string.concat
}

/// Turn a grid of clues into a playable board. Every non-empty cell becomes
/// a given.
pub fn from_grid(grid: Grid) -> Board {
  let givens =
    grid
    |> dict.to_list
    |> list.filter(fn(entry) { entry.1 != 0 })
    |> list.map(fn(entry) { entry.0 })
    |> set.from_list

  Board(values: grid, givens: givens)
}

pub fn value(board: Board, index: Int) -> Int {
  case dict.get(board.values, index) {
    Ok(digit) -> digit
    Error(_) -> 0
  }
}

pub fn is_given(board: Board, index: Int) -> Bool {
  set.contains(board.givens, index)
}

/// Write a digit into a cell. Givens are left untouched.
pub fn place(board: Board, index: Int, digit: Int) -> Board {
  case is_given(board, index) {
    True -> board
    False -> Board(..board, values: dict.insert(board.values, index, digit))
  }
}

pub fn erase(board: Board, index: Int) -> Board {
  place(board, index, 0)
}

pub fn empty_count(board: Board) -> Int {
  board.values |> dict.values |> list.count(fn(digit) { digit == 0 })
}

/// Every cell holding a digit that appears twice in one of its units.
pub fn conflicts(board: Board) -> Set(Int) {
  grid_conflicts(board.values)
}

pub fn grid_conflicts(grid: Grid) -> Set(Int) {
  use clashes, unit <- list.fold(units(), set.new())

  let by_digit = {
    use grouped, index <- list.fold(unit, dict.new())
    case dict.get(grid, index) {
      Ok(0) | Error(_) -> grouped
      Ok(digit) -> {
        use existing <- dict.upsert(grouped, digit)
        case existing {
          Some(cells) -> [index, ..cells]
          None -> [index]
        }
      }
    }
  }

  use clashes, _digit, cells <- dict.fold(by_digit, clashes)
  case cells {
    [_, _, ..] -> list.fold(cells, clashes, set.insert)
    _ -> clashes
  }
}

/// Whether the digits already on a grid obey the rules. Says nothing about
/// whether the grid can be finished.
pub fn is_consistent(grid: Grid) -> Bool {
  set.is_empty(grid_conflicts(grid))
}

pub fn is_solved(board: Board) -> Bool {
  empty_count(board) == 0 && set.is_empty(conflicts(board))
}

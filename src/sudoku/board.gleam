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

/// A puzzle being played: the digits currently on the grid, the cells that
/// were dealt as clues and so cannot be edited, and the player's pencil marks.
///
/// Marks live here rather than alongside the board so that undo, which
/// snapshots the board, captures them without any extra bookkeeping.
pub type Board {
  Board(values: Grid, givens: Set(Int), marks: Dict(Int, Set(Int)))
}

/// The integers from `start` to `stop` inclusive, ascending. The standard
/// library only offers `int.range`, which folds rather than building a list.
pub fn span(start: Int, stop: Int) -> List(Int) {
  int.range(from: stop, to: start - 1, with: [], run: list.prepend)
}

/// Remember the answer to a question that always has the same answer.
///
/// The shape of the grid is a fact about Sudoku rather than about any one
/// puzzle: which cells make up a row, and which cells a given cell can see,
/// are the same on an empty grid as on a finished one. So they are worked
/// out once and kept, and every call after the first is a lookup.
///
/// Worth keeping because the reasoning asks constantly and asks in the
/// middle of everything else. Carving one Expert puzzle used to build the
/// nine rows forty-five thousand times over, and the peer table nine
/// hundred and eighty-five times, and got the same answer back every time.
@external(erlang, "sudoku_ffi", "remembered")
fn remembered(question: String, answer: fn() -> a) -> a

/// Every cell index, in reading order.
pub fn indices() -> List(Int) {
  use <- remembered("indices")
  span(0, cell_count - 1)
}

pub fn empty_grid() -> Grid {
  indices()
  |> list.map(fn(index) { #(index, 0) })
  |> dict.from_list
}

/// The letters the rows are labelled with, top to bottom. Columns are
/// numbered, so a cell is named like `C4`.
pub const row_labels = ["A", "B", "C", "D", "E", "F", "G", "H", "I"]

/// A cell's name as the player sees it, such as `C4`.
pub fn name(index: Int) -> String {
  row_letter(row_of(index)) <> int.to_string(col_of(index) + 1)
}

/// The letter a row is labelled with.
pub fn row_letter(row: Int) -> String {
  case list.drop(row_labels, row) {
    [letter, ..] -> letter
    [] -> "?"
  }
}

pub fn row_name(index: Int) -> String {
  "row " <> row_letter(row_of(index))
}

pub fn column_name(index: Int) -> String {
  "column " <> int.to_string(col_of(index) + 1)
}

/// A box named by where it sits rather than by a number nobody can picture:
/// `the top-left box`, `the middle box`.
pub fn box_name(index: Int) -> String {
  let down = case row_of(index) / 3 {
    0 -> "top"
    1 -> "middle"
    _ -> "bottom"
  }
  let across = case col_of(index) / 3 {
    0 -> "left"
    1 -> "centre"
    _ -> "right"
  }

  case down, across {
    "middle", "centre" -> "the middle box"
    _, _ -> "the " <> down <> "-" <> across <> " box"
  }
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

/// The nine rows, top to bottom.
pub fn rows() -> List(List(Int)) {
  use <- remembered("rows")
  let digits = span(0, side - 1)
  list.map(digits, fn(row) { list.map(digits, fn(col) { at(row, col) }) })
}

/// The nine columns, left to right.
pub fn columns() -> List(List(Int)) {
  use <- remembered("columns")
  let digits = span(0, side - 1)
  list.map(digits, fn(col) { list.map(digits, fn(row) { at(row, col) }) })
}

/// The nine boxes, in reading order.
pub fn boxes() -> List(List(Int)) {
  use <- remembered("boxes")
  use box <- list.map(span(0, side - 1))
  let top = box / 3 * 3
  let left = box % 3 * 3
  list.flat_map(span(0, 2), fn(row) {
    list.map(span(0, 2), fn(col) { at(top + row, left + col) })
  })
}

/// The 27 groups of nine cells that must each hold the digits 1-9 exactly
/// once: nine rows, nine columns and nine boxes.
pub fn units() -> List(List(Int)) {
  use <- remembered("units")
  list.flatten([rows(), columns(), boxes()])
}

/// The 20 cells that share a row, column or box with this one.
pub fn peers_of(index: Int) -> List(Int) {
  case dict.get(peer_lists(), index) {
    Ok(cells) -> cells
    // No cell, so nothing can see it. Only reachable with an index off the
    // grid, which is not a cell that has peers so much as not a cell.
    Error(_) -> []
  }
}

/// Every cell's peers, worked out once.
fn peer_lists() -> Dict(Int, List(Int)) {
  use <- remembered("peer_lists")
  indices()
  |> list.map(fn(index) { #(index, peers_around(index)) })
  |> dict.from_list
}

/// Which cells those are, for one cell, from first principles.
fn peers_around(index: Int) -> List(Int) {
  let row = row_of(index)
  let col = col_of(index)
  let top = row / 3 * 3
  let left = col / 3 * 3

  list.flatten([
    list.map(span(0, side - 1), fn(other) { at(row, other) }),
    list.map(span(0, side - 1), fn(other) { at(other, col) }),
    list.flat_map(span(0, 2), fn(down) {
      list.map(span(0, 2), fn(across) { at(top + down, left + across) })
    }),
  ])
  |> list.filter(fn(other) { other != index })
  |> list.unique
}

/// The same again as sets, for the solver, which asks whether a cell is a
/// peer rather than which cells are.
///
/// Solvers still take this as an argument and pass it down a whole search.
/// That is no longer about what it costs to build — it is built once and
/// kept, like everything else here — but about being handed the thing you
/// are reading rather than going and asking for it again at every level of
/// the recursion.
pub fn peers_table() -> Peers {
  use <- remembered("peers_table")
  indices()
  |> list.map(fn(index) { #(index, set.from_list(peers_of(index))) })
  |> dict.from_list
}

/// The digits that could legally go in an empty cell, ignoring any deeper
/// reasoning about the rest of the grid.
/// The empty cells a digit could still go in: the ones whose row, column and
/// box do not hold one already.
///
/// Read off the grid and nothing else. What a player has pencilled in is
/// their reasoning, and reasoning can be wrong; where a digit can go is a
/// fact, and this should stay one.
pub fn could_take(current: Board, digit: Int) -> List(Int) {
  let peers = peers_table()

  use index <- list.filter(indices())
  value(current, index) == 0
  && list.contains(candidates(current.values, peers, index), digit)
}

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

  Board(values: grid, givens: givens, marks: dict.new())
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
///
/// Settling on a digit also tidies up the marks around it: the cell's own
/// marks go, and so does that digit's mark in every cell that can see it,
/// since those readings are now ruled out.
pub fn place(board: Board, index: Int, digit: Int) -> Board {
  case is_given(board, index) {
    True -> board
    False ->
      Board(
        ..board,
        values: dict.insert(board.values, index, digit),
        marks: board.marks
          |> dict.delete(index)
          |> retract(peers_of(index), digit),
      )
  }
}

fn retract(
  marks: Dict(Int, Set(Int)),
  cells: List(Int),
  digit: Int,
) -> Dict(Int, Set(Int)) {
  use marks, cell <- list.fold(cells, marks)
  case dict.get(marks, cell) {
    Error(_) -> marks
    Ok(existing) -> write_marks(marks, cell, set.delete(existing, digit))
  }
}

/// Write a digit into a cell and leave every mark alone, on it and around
/// it. Givens are left untouched.
///
/// This is for a digit that is not to be believed: `place` tidies marks away
/// on the strength of the digit being right, which is no favour when it is
/// not.
pub fn write(board: Board, index: Int, digit: Int) -> Board {
  case is_given(board, index) {
    True -> board
    False -> Board(..board, values: dict.insert(board.values, index, digit))
  }
}

/// Clear a cell's digit. Any marks on it are left alone, so a wrong guess can
/// be taken back without losing the reasoning that led to it.
/// Rub a digit out, and give it back to the marks it was taken from.
///
/// Writing a digit retracts it from the marks around it. That is the game's
/// own bookkeeping rather than the player's reasoning, so taking the digit
/// back has to undo it too — otherwise every digit written and thought
/// better of leaves a hole in the marks that nothing will ever fill, since
/// `f` passes over any cell that has marks at all. Holes like that collect
/// until the marks say things that cannot be true.
///
/// Only cells that already carry marks get it back, and only where the digit
/// is really free again. A cell with no marks is one nobody has pencilled
/// yet, and a single mark appearing in it out of nowhere would read as a
/// naked single.
pub fn erase(board: Board, index: Int) -> Board {
  let digit = value(board, index)
  let cleared = write(board, index, 0)

  case digit {
    0 -> cleared
    _ -> Board(..cleared, marks: restore(cleared, peers_of(index), digit))
  }
}

fn restore(board: Board, cells: List(Int), digit: Int) -> Dict(Int, Set(Int)) {
  use marks, cell <- list.fold(cells, board.marks)
  case dict.get(marks, cell) {
    Error(_) -> marks
    Ok(existing) ->
      case value(board, cell) == 0 && free_at(board, cell, digit) {
        True -> write_marks(marks, cell, set.insert(existing, digit))
        False -> marks
      }
  }
}

/// Whether a digit can still go in a cell, read off the board alone.
fn free_at(board: Board, cell: Int, digit: Int) -> Bool {
  use peer <- list.all(peers_of(cell))
  value(board, peer) != digit
}

// ---------------------------------------------------------------------------
// Pencil marks
// ---------------------------------------------------------------------------

/// The digits pencilled into a cell, if any.
pub fn marks_at(board: Board, index: Int) -> Set(Int) {
  case dict.get(board.marks, index) {
    Ok(marks) -> marks
    Error(_) -> set.new()
  }
}

/// Add a pencil mark to a cell, or take it away if it is already there.
/// Givens are left untouched.
pub fn toggle_mark(board: Board, index: Int, digit: Int) -> Board {
  case is_given(board, index) {
    True -> board
    False -> {
      let marks = marks_at(board, index)
      let next = case set.contains(marks, digit) {
        True -> set.delete(marks, digit)
        False -> set.insert(marks, digit)
      }
      Board(..board, marks: write_marks(board.marks, index, next))
    }
  }
}

/// Rub one pencil mark out, if it is there at all.
pub fn erase_mark(board: Board, index: Int, digit: Int) -> Board {
  case dict.get(board.marks, index) {
    Error(_) -> board
    Ok(marks) ->
      Board(
        ..board,
        marks: write_marks(board.marks, index, set.delete(marks, digit)),
      )
  }
}

pub fn clear_marks(board: Board, index: Int) -> Board {
  Board(..board, marks: dict.delete(board.marks, index))
}

/// Marks in ascending order, which is how they are always shown.
pub fn sorted_marks(board: Board, index: Int) -> List(Int) {
  board |> marks_at(index) |> set.to_list |> list.sort(int.compare)
}

/// Store a cell's marks, dropping the entry entirely when nothing is left so
/// that an unmarked cell is always an absent key rather than an empty set.
fn write_marks(
  marks: Dict(Int, Set(Int)),
  index: Int,
  next: Set(Int),
) -> Dict(Int, Set(Int)) {
  case set.is_empty(next) {
    True -> dict.delete(marks, index)
    False -> dict.insert(marks, index, next)
  }
}

pub fn empty_count(board: Board) -> Int {
  board.values |> dict.values |> list.count(fn(digit) { digit == 0 })
}

/// How many of a digit are still to be placed: nine less the ones already
/// on the board, clues and answers counted alike.
///
/// A tally anybody can take by eye, which is why the game will take it for
/// you: counting the sevens is the commonest thing a player does that is
/// not thinking, and doing it wrong sends them hunting for a seven that is
/// already there. Never less than nothing — a digit written ten times over
/// is a clash, and the clash counter says so.
pub fn left_to_place(board: Board, digit: Int) -> Int {
  let placed =
    board.values |> dict.values |> list.count(fn(other) { other == digit })

  int.max(side - placed, 0)
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

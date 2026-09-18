//// Drawing a nine by nine grid, and the rules that band it into boxes.
////
//// Shared by the board, the grid of marks beside it, the puzzle being typed
//// in, and the small boards the help draws to show a technique at work. That
//// last one is the reason this is a module of its own: a diagram of a
//// technique is worth nothing if it does not look like the board the player
//// is looking at, and the surest way to make two things look alike is to
//// draw them with the same code.

import gleam/int
import gleam/list
import gleam/string
import sudoku/board
import sudoku/palette
import sudoku/term

/// Lay nine cells out as `│abc │def │ghi │`, with every cell two columns wide
/// so that a highlight reads as a solid block. The column ruler is built with
/// the same helper, which is what keeps it aligned with the cells.
pub fn banded(cells: List(String), separator: String) -> String {
  chunked(cells, 3, separator)
}

/// The same in bands of whatever size, which is what lets a diagram of one
/// digit's whereabouts drop the box rules it has no use for.
pub fn chunked(cells: List(String), size: Int, separator: String) -> String {
  cells
  |> list.sized_chunk(size)
  |> list.map(fn(band) { string.concat(band) <> " " })
  |> string.join(separator)
  |> fn(bands) { separator <> bands <> separator }
}

pub fn rule(left: String, join: String, right: String) -> String {
  banded_rule(left, join, right, 3, "  ")
}

/// A rule across however many bands of however many cells, with the same
/// margin as the rows it belongs to.
pub fn banded_rule(
  left: String,
  join: String,
  right: String,
  size: Int,
  margin: String,
) -> String {
  let bars =
    list.repeat(string.repeat("\u{2500}", size * 2 + 1), 9 / size)
    |> string.join(join)

  margin <> term.styled(palette.dim(), left <> bars <> right)
}

/// One grid, from its column ruler down to its bottom rule. What goes in each
/// cell is left to the caller, which is how the board and the marks beside it
/// come out exactly the same shape.
pub fn grid(cell: fn(Int) -> String) -> List(String) {
  let ruler =
    board.span(1, board.side)
    |> list.map(fn(column) { " " <> int.to_string(column) })
    |> banded(" ")

  let bands =
    board.row_labels
    |> list.index_map(fn(label, row) { row_line(cell, row, label) })
    |> list.sized_chunk(3)
    |> list.intersperse([rule("\u{251c}", "\u{253c}", "\u{2524}")])
    |> list.flatten

  list.flatten([
    [term.styled(palette.dim(), "  " <> ruler)],
    [rule("\u{250c}", "\u{252c}", "\u{2510}")],
    bands,
    [rule("\u{2514}", "\u{2534}", "\u{2518}")],
  ])
}

pub fn row_line(cell: fn(Int) -> String, row: Int, label: String) -> String {
  let cells =
    board.span(0, board.side - 1)
    |> list.map(fn(column) { cell(board.at(row, column)) })

  term.styled(palette.dim(), label)
  <> " "
  <> banded(cells, term.styled(palette.dim(), "\u{2502}"))
}

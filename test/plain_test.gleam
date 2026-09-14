//// Playing without colour.
////
//// A terminal that will not show colour, or a player who would rather it
//// did not, should still be able to read the board. What survives is shape:
//// bold, dim, underline, reverse and strikethrough, plus the one character a
//// hint points with when it has nothing to shade its cells in.

import gleam/list
import gleam/option
import gleam/string
import helper
import sudoku/board
import sudoku/game
import sudoku/logic
import sudoku/palette
import sudoku/render
import sudoku/term

/// Draw something with the colour switched off, and switch it back.
///
/// Nothing is asserted in here on purpose: an assertion that failed would
/// take the restoring with it and leave every test after this one drawing in
/// plain, which is a confusing way to find out about one broken thing.
fn without_colour(draw: fn() -> a) -> a {
  term.plainly(True)
  let drawn = draw()
  term.plainly(False)
  drawn
}

pub fn colours_go_and_shapes_stay_test() {
  // A clashing digit is bold, struck through and red; the red is the part
  // that goes.
  assert term.uncoloured(palette.conflict) == "1;9"

  // Cyan on its own leaves nothing behind, and so writes nothing at all.
  assert term.uncoloured(palette.entered) == ""
  assert term.uncoloured("") == ""

  // The cursor is reverse video, which is not a colour and does not need one.
  assert term.uncoloured(palette.cursor) == palette.cursor

  // A wrong digit keeps its underline.
  assert term.uncoloured(palette.wrong) == "1;4"
}

pub fn a_colour_with_arguments_is_swallowed_whole_test() {
  // 48;5;22 is three codes making one colour. Dropping only the 48 would
  // leave 5 and 22 behind to be read as blink and something in the 20s.
  assert term.uncoloured(palette.hint_wash) == ""
  assert term.uncoloured(palette.hint_wash <> ";" <> palette.given) == "1"
  assert term.uncoloured("38;2;10;20;30;4") == "4"
  assert term.uncoloured("4;" <> palette.peer_wash <> ";1") == "4;1"
}

pub fn styled_writes_no_escape_where_nothing_is_left_test() {
  let #(bare, struck) =
    without_colour(fn() {
      #(term.styled(palette.entered, "5"), term.styled(palette.conflict, "5"))
    })

  assert bare == "5"
  assert struck == term.esc <> "[1;9m5" <> term.reset
}

pub fn a_plain_board_is_drawn_without_colour_test() {
  let frame = without_colour(fn() { render.frame(helper.fixture()) })

  assert !string.contains(frame, helper.hint_wash)
  assert !string.contains(frame, "[96m")
  assert !string.contains(frame, "[90m")

  // Not simply stripped of everything: the cursor is still where it was.
  assert string.contains(frame, "[7m")
}

pub fn a_hint_points_at_its_cells_without_colour_test() {
  let assert Ok(row) = list.first(board.units())
  let hinted = pointing_at(row)

  let plain = without_colour(fn() { render.frame(hinted) })

  // The wash is gone, so the pointer has to stand in for it: once for every
  // cell of the row the hint is arguing from, in both grids, bar the one the
  // cursor is sitting on — that stays reverse video, which needs no colour.
  assert !string.contains(plain, helper.hint_wash)
  assert count(plain, palette.pointer) == 2 * { list.length(row) - 1 }

  // In colour the wash does the pointing, and the grid keeps its spaces.
  let coloured = render.frame(hinted)
  assert string.contains(coloured, helper.hint_wash)
  assert !string.contains(coloured, palette.pointer)
}

pub fn a_plain_board_is_the_same_width_test() {
  // The pointer goes where the leading space of a cell would, so a hint does
  // not push the marks grid sideways.
  let assert Ok(row) = list.first(board.units())
  let hinted = pointing_at(row)

  let widths = fn(frame: String) {
    frame
    |> helper.plain
    |> string.split("\r\n")
    |> list.map(fn(line) { string.length(string.trim_end(line)) })
  }

  assert without_colour(fn() { widths(render.frame(hinted)) })
    == widths(render.frame(hinted))
}

fn count(text: String, part: String) -> Int {
  list.length(string.split(text, part)) - 1
}

/// A game with a hint up, resting its argument on one cell and the row
/// around it.
fn pointing_at(row: List(Int)) -> game.Game {
  game.Game(
    ..helper.fixture(),
    showing: option.Some(logic.Step(
      technique: logic.HiddenSingle,
      move: logic.Settle(2, 4),
      evidence: [2],
      about: [4],
      unit: row,
    )),
  )
}

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

pub fn colours_go_and_shapes_stay_test() {
  // A clashing digit is bold, struck through and red; the red is the part
  // that goes.
  assert term.uncoloured(palette.conflict()) == "1;9"

  // Cyan on its own leaves nothing behind, and so writes nothing at all.
  assert term.uncoloured(palette.entered()) == ""
  assert term.uncoloured("") == ""

  // The cursor is reverse video, which is not a colour and does not need one.
  assert term.uncoloured(palette.cursor()) == palette.cursor()

  // A wrong digit keeps its underline.
  assert term.uncoloured(palette.wrong()) == "1;4"
}

pub fn a_colour_with_arguments_is_swallowed_whole_test() {
  // 48;5;22 is three codes making one colour. Dropping only the 48 would
  // leave 5 and 22 behind to be read as blink and something in the 20s.
  //
  // Written out rather than taken from the palette: what is being asked is
  // how a code with arguments is read, and the palette's answer now depends
  // on how much colour the terminal has.
  assert term.uncoloured("48;5;22") == ""
  assert term.uncoloured("48;5;22;" <> palette.given()) == "1"
  assert term.uncoloured("38;2;10;20;30;4") == "4"
  assert term.uncoloured("4;48;5;236;1") == "4;1"
}

pub fn styled_writes_no_escape_where_nothing_is_left_test() {
  let #(bare, struck) =
    helper.without_colour(fn() {
      #(
        term.styled(palette.entered(), "5"),
        term.styled(palette.conflict(), "5"),
      )
    })

  assert bare == "5"
  assert struck == term.esc <> "[1;9m5" <> term.reset
}

pub fn a_plain_board_is_drawn_without_colour_test() {
  let frame = helper.without_colour(fn() { render.frame(helper.fixture()) })

  assert !string.contains(frame, helper.hint_wash)
  assert !string.contains(frame, "[96m")
  assert !string.contains(frame, "[90m")

  // Not simply stripped of everything: the cursor is still where it was.
  assert string.contains(frame, "[7m")
}

pub fn a_hint_points_at_its_cells_without_colour_test() {
  let assert Ok(row) = list.first(board.units())
  let hinted = pointing_at(row)

  let plain = helper.without_colour(fn() { render.frame(hinted) })

  // The wash is gone, so the pointer has to stand in for it: once for every
  // cell of the row the hint is arguing from, in both grids. The cell the
  // cursor is on gets one too — its colour is spoken for either way.
  assert !string.contains(plain, helper.hint_wash)
  assert count(plain, palette.pointer) == 2 * list.length(row)

  // In colour the wash does the pointing everywhere it can be seen, which is
  // everywhere but the cell the cursor is on — that one gets a mark in both
  // grids and nowhere else does.
  let coloured = render.frame(hinted)
  assert list.contains(row, hinted.cursor)
  assert string.contains(coloured, helper.hint_wash)
  assert count(coloured, palette.pointer) == 2
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

  assert helper.without_colour(fn() { widths(render.frame(hinted)) })
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

/// Every colour the game draws with can be named in a palette file, and
/// every name has something behind it.
///
/// The accessors are written from the same table `names` reads, so this is
/// what keeps a colour added to one from going missing from the other: a
/// name nobody can set is a colour nobody can fix.
pub fn every_colour_can_be_named_in_a_palette_file_test() {
  let named = palette.names()

  assert named != []
  assert list.unique(named) == named

  use name <- list.each(named)
  assert name != ""
  // Lowercase and underscores: a name typed into a file by hand, rather
  // than one that needs quoting or shifting.
  assert string.lowercase(name) == name
}

/// The colours the board is actually drawn with are the ones a file can
/// name, spelled the same way. Nothing here is reachable only through a
/// name that is not on the list.
pub fn the_names_cover_what_the_board_uses_test() {
  let named = palette.names()

  use name <- list.each([
    "given", "entered", "conflict", "wrong", "cursor", "dim", "empty",
    "peer_wash", "match_wash", "hint_wash", "scan_wash", "wash",
  ])
  assert list.contains(named, name)
}

/// The characters are not among them, and that is on purpose: a colour that
/// is wrong is ugly, and a character of the wrong width takes the grid
/// apart — and there are tests about the width of the grid that a file
/// nobody compiles could otherwise walk straight through.
pub fn the_characters_are_not_settable_test() {
  use name <- list.each(["empty_cell", "crowded_cell", "pointer", "could_go"])
  assert !list.contains(palette.names(), name)
}

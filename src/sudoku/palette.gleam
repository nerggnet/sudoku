//// The colours the game is drawn in, and the two characters that stand for
//// what a cell does not hold.
////
//// Kept apart from the drawing so that the board and the help can be drawn
//// in the same colours without one of them having to know how the other
//// works — and so that changing what the game looks like is a matter of
//// reading one short file.
////
//// Reading it is no longer the only way to change it. Every colour here is
//// a default rather than a decree: a line in `~/.config/sudoku/palette`
//// naming one has the last word on it, so a terminal this was not tuned for
//// — a pale one, most of all, since all of this assumes a dark screen —
//// can be put right without a compiler.
////
//// Only the colours. The characters below stay where they are, because a
//// colour that is wrong is ugly and a character of the wrong width takes
//// the grid apart, and there are tests about the width of the grid that a
//// file nobody compiles could otherwise walk straight through.

import gleam/list
import gleam/result
import sudoku/term

/// An empty cell, and a cell carrying more than one pencil mark.
pub const empty_cell = "\u{00b7}"

pub const crowded_cell = "*"

/// What stands in for the wash behind a hint's cells when there is no colour
/// to wash with. It goes where the leading space of a cell would, so the grid
/// keeps its width.
pub const pointer = "\u{203a}"

/// The same, for a cell a scan says the digit could still go in. A different
/// mark from the hint's, since the two can be up at once.
pub const could_go = "+"

/// Every colour there is, by the name a palette file calls it, and what it
/// is where no file says otherwise.
///
/// One list rather than two. A colour added here is a colour a palette file
/// can name, without anybody having to remember to write it down twice.
const defaults = [
  #("given", "1;97"),
  #("entered", "96"),
  #("conflict", "1;9;91"),
  #("alarm", "1;91"),
  #("wrong", "1;91;4"),
  #("key", "96"),
  #("best", "92"),
  #("note", "93"),
  #("empty", "90"),
  #("dim", "90"),
  #("title", "1;95"),
  #("good", "1;92"),
  #("mark", "33"),
  #("cursor", "7"),
  #("peer_wash", "48;5;236"),
  #("match_wash", "48;5;238"),
  #("hint_wash", "48;5;22"),
  #("scan_wash", "48;5;17"),
  // The one a terminal of sixteen colours washes with, there being only one
  // of it to name.
  #("wash", only_grey),
]

pub fn names() -> List(String) {
  list.map(defaults, fn(entry) { entry.0 })
}

// Foreground colours.
pub fn given() -> String {
  chosen("given")
}

pub fn entered() -> String {
  chosen("entered")
}

/// A digit clashing with another in its row, column or box: red, and struck
/// through so that it says so without the red being seen. Bold is spoken for
/// by the clues, underline by a wrong digit and reverse by the cursor, which
/// leaves this — apt enough for a digit that cannot stand.
pub fn conflict() -> String {
  chosen("conflict")
}

/// Red for something gone wrong that is said in words rather than drawn in a
/// cell. Words do not need striking through to be read.
pub fn alarm() -> String {
  chosen("alarm")
}

/// Wrong, while checking is on: red, and underlined so that it says so
/// without relying on the colour being seen.
pub fn wrong() -> String {
  chosen("wrong")
}

/// A key to press, where the game is listing them for choosing between. Not
/// the same thing as a digit written in, though they look alike: one is an
/// instruction and the other is an answer.
pub fn key() -> String {
  chosen("key")
}

/// A time to beat, mentioned in passing. The green a result is announced in
/// is bolder; this one sits in a list and should not shout.
pub fn best() -> String {
  chosen("best")
}

/// Something the player should know that is nobody's fault — a terminal in
/// line mode, say. Not `alarm`, which is for something gone wrong.
pub fn note() -> String {
  chosen("note")
}

pub fn empty() -> String {
  chosen("empty")
}

pub fn dim() -> String {
  chosen("dim")
}

pub fn title() -> String {
  chosen("title")
}

pub fn good() -> String {
  chosen("good")
}

pub fn mark() -> String {
  chosen("mark")
}

/// The cursor itself, which is reverse video rather than a colour, so that it
/// is the cursor whatever the rest is painted in.
pub fn cursor() -> String {
  chosen("cursor")
}

// A wash behind the cells sharing a unit with the cursor, behind cells
// holding the same digit as the one under the cursor, and behind the cells a
// hint is resting its argument on.
pub fn peer_wash() -> String {
  wash("peer_wash")
}

pub fn match_wash() -> String {
  wash("match_wash")
}

pub fn hint_wash() -> String {
  wash("hint_wash")
}

/// Behind the cells a scan says its digit could still go in. Blue against the
/// hint's green: a hint is telling you something, a scan is only showing you
/// where to look.
pub fn scan_wash() -> String {
  wash("scan_wash")
}

/// The one grey a terminal with sixteen colours can wash with.
///
/// Bright black, which is the only background of the sixteen that is neither
/// the terminal's own nor a shout: grey on a dark terminal and grey on a
/// light one. Every other candidate is a colour somebody has chosen their
/// whole screen to be, or one loud enough to lose the digits inside it.
const only_grey = "100"

/// A wash, or what becomes of it where four shades cannot be told apart.
///
/// Sixteen colours have one usable background and this game wants four, so
/// under them the four become one and the wash stops saying which kind it
/// is. What the two that were saying something lose by merging they get
/// back in the column in front of the cell — the same mark a terminal with
/// no colour at all has always been given.
///
/// One name for that one grey, since there is only one of it to name.
fn wash(name: String) -> String {
  case term.colours() {
    term.Full -> chosen(name)
    term.Basic | term.Plain -> chosen("wash")
  }
}

/// What the player has said this colour should be, or what it has always
/// been where they have said nothing — which is the usual case, there being
/// no file at all until somebody writes one.
fn chosen(name: String) -> String {
  case list.key_find(theme(), name) {
    Ok(codes) -> codes
    Error(_) ->
      // Only reachable with a name no longer in the table above, which the
      // accessors are written from. A test keeps them together.
      list.key_find(defaults, name) |> result.unwrap("")
  }
}

/// The palette file, read once and kept.
@external(erlang, "sudoku_ffi", "theme")
fn theme() -> List(#(String, String))

//// The colours the game is drawn in, and the two characters that stand for
//// what a cell does not hold.
////
//// Kept apart from the drawing so that the board and the help can be drawn
//// in the same colours without one of them having to know how the other
//// works — and so that changing what the game looks like is a matter of
//// reading one short file.

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

// Foreground colours.
pub const given = "1;97"

pub const entered = "96"

/// A digit clashing with another in its row, column or box: red, and struck
/// through so that it says so without the red being seen. Bold is spoken for
/// by the clues, underline by a wrong digit and reverse by the cursor, which
/// leaves this — apt enough for a digit that cannot stand.
pub const conflict = "1;9;91"

/// Red for something gone wrong that is said in words rather than drawn in a
/// cell. Words do not need striking through to be read.
pub const alarm = "1;91"

/// Wrong, while checking is on: red, and underlined so that it says so
/// without relying on the colour being seen.
pub const wrong = "1;91;4"

/// A key to press, where the game is listing them for choosing between. Not
/// the same thing as a digit written in, though they look alike: one is an
/// instruction and the other is an answer.
pub const key = "96"

/// A time to beat, mentioned in passing. The green a result is announced in
/// is bolder; this one sits in a list and should not shout.
pub const best = "92"

/// Something the player should know that is nobody's fault — a terminal in
/// line mode, say. Not `alarm`, which is for something gone wrong.
pub const note = "93"

pub const empty = "90"

pub const dim = "90"

pub const title = "1;95"

pub const good = "1;92"

pub const mark = "33"

// A wash behind the cells sharing a unit with the cursor, behind cells
// holding the same digit as the one under the cursor, and behind the cells a
// hint is resting its argument on.
pub fn peer_wash() -> String {
  wash("48;5;236")
}

pub fn match_wash() -> String {
  wash("48;5;238")
}

pub fn hint_wash() -> String {
  wash("48;5;22")
}

/// Behind the cells a scan says its digit could still go in. Blue against the
/// hint's green: a hint is telling you something, a scan is only showing you
/// where to look.
pub fn scan_wash() -> String {
  wash("48;5;17")
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
fn wash(full: String) -> String {
  case term.colours() {
    term.Full -> full
    term.Basic | term.Plain -> only_grey
  }
}

/// The cursor itself, which is reverse video rather than a colour, so that it
/// is the cursor whatever the rest is painted in.
pub const cursor = "7"

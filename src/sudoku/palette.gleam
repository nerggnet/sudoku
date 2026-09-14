//// The colours the game is drawn in, and the two characters that stand for
//// what a cell does not hold.
////
//// Kept apart from the drawing so that the board and the help can be drawn
//// in the same colours without one of them having to know how the other
//// works — and so that changing what the game looks like is a matter of
//// reading one short file.

/// An empty cell, and a cell carrying more than one pencil mark.
pub const empty_cell = "\u{00b7}"

pub const crowded_cell = "*"

// Foreground colours.
pub const given = "1;97"

pub const entered = "96"

pub const conflict = "1;91"

/// Wrong, while checking is on: red, and underlined so that it says so
/// without relying on the colour being seen.
pub const wrong = "1;91;4"

pub const empty = "90"

pub const dim = "90"

pub const title = "1;95"

pub const good = "1;92"

pub const mark = "33"

// A wash behind the cells sharing a unit with the cursor, behind cells
// holding the same digit as the one under the cursor, and behind the cells a
// hint is resting its argument on.
pub const peer_wash = "48;5;236"

pub const match_wash = "48;5;238"

pub const hint_wash = "48;5;22"

/// The cursor itself, which is reverse video rather than a colour, so that it
/// is the cursor whatever the rest is painted in.
pub const cursor = "7"

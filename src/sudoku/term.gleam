//// Terminal plumbing: raw input and the handful of ANSI escapes the game
//// needs.

import gleam/int
import gleam/io
import gleam/list
import gleam/string

/// Switch the terminal to raw mode so that keystrokes arrive one byte at a
/// time without being echoed. Returns `False` when that is not possible,
/// which happens on OTP versions before 26 and when input is piped rather
/// than typed. The game stays playable either way; keys just need Enter.
@external(erlang, "sudoku_ffi", "enable_raw")
pub fn enable_raw() -> Bool

/// Read one byte of input, or -1 once input has run out.
@external(erlang, "sudoku_ffi", "read_byte")
pub fn read_byte() -> Int

/// The same, waiting no longer than this for one to arrive. Answers -2
/// where none did, which is not the same as -1: nothing has been typed yet,
/// and there may be plenty still to come.
@external(erlang, "sudoku_ffi", "read_byte_after")
pub fn read_byte_after(milliseconds: Int) -> Int

@external(erlang, "sudoku_ffi", "now_ms")
pub fn now_ms() -> Int

/// Stop the game, saying how it went: 0 where nothing went wrong, and
/// anything else where something did. Never returns.
@external(erlang, "sudoku_ffi", "stop")
pub fn stop(status: Int) -> Nil

/// A name for a game's save file, unique among the games that could be being
/// played at one time. Minted when a puzzle starts and kept for as long as
/// the game lasts, so that a game put down and picked up again goes back
/// into the file it came out of rather than forking into a second one.
@external(erlang, "sudoku_ffi", "new_id")
pub fn new_id() -> String

/// What was asked for on the command line.
@external(erlang, "sudoku_ffi", "arguments")
pub fn arguments() -> List(String)

/// How wide and how tall the terminal is, or -1 where it will not say.
@external(erlang, "sudoku_ffi", "columns")
pub fn columns() -> Int

@external(erlang, "sudoku_ffi", "rows")
pub fn rows() -> Int

/// How much colour the terminal has.
///
/// Three answers rather than two, because there are three terminals. The
/// washes behind the board are 256-colour greys and a terminal with sixteen
/// draws them as nothing at all, so it needs telling apart from one that has
/// them and from one that has no colour whatever.
pub type Colours {
  /// None. `NO_COLOR`, `--plain`, or a terminal that says it is dumb.
  Plain
  /// The sixteen every terminal has had since the beginning, which is every
  /// colour this game uses except the washes.
  Basic
  /// The 256, which is where the washes live.
  Full
}

/// What the terminal has, worked out from the environment and settled once.
@external(erlang, "sudoku_ffi", "colours")
pub fn colours() -> Colours

/// Say otherwise, before anything is drawn.
@external(erlang, "sudoku_ffi", "colouring")
pub fn colouring(colours: Colours) -> Nil

/// Whether the game is being drawn without colour at all.
pub fn plain() -> Bool {
  colours() == Plain
}

pub const esc = "\u{1b}"

pub const reset = "\u{1b}[0m"

/// Wrap text in an SGR sequence, e.g. `styled("1;31", "danger")`.
///
/// Without colour the hues are dropped and the rest is kept: bold, dim,
/// underline, reverse and strikethrough are shapes rather than colours, and
/// a terminal that will not show green will still show those.
pub fn styled(codes: String, text: String) -> String {
  let codes = case plain() {
    True -> uncoloured(codes)
    False -> codes
  }

  case codes {
    "" -> text
    _ -> esc <> "[" <> codes <> "m" <> text <> reset
  }
}

/// The same list of SGR codes with every colour taken out of it.
///
/// Colours are the 30s and 40s and their bright halves, and the two that take
/// arguments — `38;5;n` and `48;5;n` for the 256-colour palette, `38;2;r;g;b`
/// for a colour named outright — which have to be swallowed whole or their
/// arguments are left behind to be read as codes of their own.
pub fn uncoloured(codes: String) -> String {
  case codes {
    "" -> ""
    _ -> codes |> string.split(";") |> shapes |> string.join(";")
  }
}

fn shapes(codes: List(String)) -> List(String) {
  case codes {
    [] -> []
    ["38", "5", _, ..rest] | ["48", "5", _, ..rest] -> shapes(rest)
    ["38", "2", _, _, _, ..rest] | ["48", "2", _, _, _, ..rest] -> shapes(rest)
    [code, ..rest] ->
      case int.parse(code) {
        Ok(value) if value >= 30 && value <= 49 -> shapes(rest)
        Ok(value) if value >= 90 && value <= 97 -> shapes(rest)
        Ok(value) if value >= 100 && value <= 107 -> shapes(rest)
        _ -> [code, ..shapes(rest)]
      }
  }
}

/// Move the cursor home and erase everything below it. Combined with
/// erase-to-end-of-line on each row this redraws without flicker.
pub const home = "\u{1b}[H"

pub const clear_line = "\u{1b}[K"

pub const clear_below = "\u{1b}[J"

/// Wipe the screen entirely. Drawing a frame does not need this — every line
/// clears what it lands on — but redrawing by request does, since the mess
/// being cleared up after was not put there by us.
pub const blank = "\u{1b}[2J"

/// Take the screen over for the length of this, and give it back at the end
/// of it — whether that end is the game finishing or the game falling over.
///
/// The screen being given back matters most in the case nobody plans for. A
/// crash on the alternate screen leaves the terminal hidden, unechoed and
/// showing the shell as it was an hour ago, with the report saying what
/// happened printed underneath where none of it can be read.
pub fn taking_over(play: fn() -> a) -> a {
  enter()
  protected(play, leave)
}

@external(erlang, "sudoku_ffi", "protected")
fn protected(play: fn() -> a, restore: fn() -> Nil) -> a

pub fn enter() -> Nil {
  // Alternate screen buffer, cursor hidden.
  write(esc <> "[?1049h" <> esc <> "[?25l" <> esc <> "[2J")
}

pub fn leave() -> Nil {
  write(esc <> "[?25h" <> esc <> "[?1049l")
}

pub fn write(text: String) -> Nil {
  io.print(text)
}

/// Say something after the screen has been given back.
///
/// With CRLF, for the same reason a frame is drawn with it: raw mode does no
/// newline translation, and giving the screen back does not give that back —
/// `shell:start_interactive` is a thing that happens once. So a line ended
/// with a newline alone moves the cursor down without bringing it home, and
/// every line after the first starts where the last one stopped. The parting
/// words walked off the right-hand side of the screen in steps.
pub fn tell(said: String) -> Nil {
  write(told(said))
}

/// The same, as the text it would write. Kept apart from the writing so that
/// what goes out can be looked at without a terminal to write it to.
pub fn told(said: String) -> String {
  string.replace(said, "\n", "\r\n") <> "\r\n"
}

/// Paint a whole screen from the top down, one line per entry.
///
/// Raw mode does no newline translation, so lines are joined with CRLF. Each
/// line clears whatever the last frame left to its right, and the frame ends
/// by clearing the rows below, so there is never a need to blank the screen
/// first and therefore never a flicker.
pub fn screen(lines: List(String)) -> String {
  home
  <> lines
  |> list.map(fn(line) { " " <> line <> clear_line })
  |> string.join("\r\n")
  <> "\r\n"
  <> clear_below
}

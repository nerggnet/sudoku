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

/// What was asked for on the command line.
@external(erlang, "sudoku_ffi", "arguments")
pub fn arguments() -> List(String)

/// How wide and how tall the terminal is, or -1 where it will not say.
@external(erlang, "sudoku_ffi", "columns")
pub fn columns() -> Int

@external(erlang, "sudoku_ffi", "rows")
pub fn rows() -> Int

/// Whether the game is being drawn without colour, either because `NO_COLOR`
/// is set or because `--plain` asked for it.
@external(erlang, "sudoku_ffi", "plain")
pub fn plain() -> Bool

/// Say so, once, before anything is drawn.
@external(erlang, "sudoku_ffi", "set_plain")
pub fn plainly(plain: Bool) -> Nil

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

//// Terminal plumbing: raw input and the handful of ANSI escapes the game
//// needs.

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

@external(erlang, "sudoku_ffi", "now_ms")
pub fn now_ms() -> Int

pub const esc = "\u{1b}"

pub const reset = "\u{1b}[0m"

/// Wrap text in an SGR sequence, e.g. `styled("1;31", "danger")`.
pub fn styled(codes: String, text: String) -> String {
  case codes {
    "" -> text
    _ -> esc <> "[" <> codes <> "m" <> text <> reset
  }
}

/// Move the cursor home and erase everything below it. Combined with
/// erase-to-end-of-line on each row this redraws without flicker.
pub const home = "\u{1b}[H"

pub const clear_line = "\u{1b}[K"

pub const clear_below = "\u{1b}[J"

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

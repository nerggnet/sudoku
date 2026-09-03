//// Turning raw bytes from the terminal into keystrokes.

import gleam/string
import sudoku/term

pub type Key {
  Up
  Down
  Left
  Right
  /// A digit key, 1 through 9.
  Digit(Int)
  /// Anything meaning "clear this cell": 0, space, backspace or delete.
  Erase
  /// A printable key. Case is kept, so `H` and `h` are different keys.
  Char(String)
  /// Input has run out, or the user pressed Ctrl-C.
  Quit
  Unknown
}

/// Read the next keystroke from the terminal.
pub fn read() -> Key {
  let #(pressed, _) = decode(Nil, fn(_) { #(term.read_byte(), Nil) })
  pressed
}

/// Decode one keystroke, pulling bytes from `next` as the sequence demands.
///
/// The byte source is threaded through as a value rather than read straight
/// from the terminal so that the decoding can be tested on its own; `next`
/// returns -1 once there is nothing left.
pub fn decode(
  source: source,
  next: fn(source) -> #(Int, source),
) -> #(Key, source) {
  let #(byte, source) = next(source)

  case byte {
    -1 -> #(Quit, source)
    0x1b -> escape(source, next)
    _ -> #(from_byte(byte), source)
  }
}

/// After an Escape byte, `[` or `O` introduces a control sequence. Anything
/// else was a lone Escape press followed by a real key, so that key is used
/// rather than swallowed.
fn escape(
  source: source,
  next: fn(source) -> #(Int, source),
) -> #(Key, source) {
  let #(byte, source) = next(source)

  case byte {
    -1 -> #(Quit, source)
    0x5b | 0x4f -> sequence(source, next)
    _ -> #(from_byte(byte), source)
  }
}

fn sequence(
  source: source,
  next: fn(source) -> #(Int, source),
) -> #(Key, source) {
  let #(byte, source) = next(source)

  case byte {
    0x41 -> #(Up, source)
    0x42 -> #(Down, source)
    0x43 -> #(Right, source)
    0x44 -> #(Left, source)
    // Delete arrives as `ESC [ 3 ~`; swallow the trailing tilde.
    0x33 -> {
      let #(_, source) = next(source)
      #(Erase, source)
    }
    -1 -> #(Quit, source)
    _ -> #(Unknown, source)
  }
}

fn from_byte(byte: Int) -> Key {
  case byte {
    // Ctrl-C and Ctrl-D.
    0x03 | 0x04 -> Quit
    // Backspace, delete, space and `0` all clear a cell.
    0x08 | 0x7f | 0x20 | 0x30 -> Erase
    // Carriage return and newline mean nothing here, but arrive in line mode.
    0x0a | 0x0d -> Unknown
    _ if byte >= 0x31 && byte <= 0x39 -> Digit(byte - 0x30)
    _ -> printable(byte)
  }
}

fn printable(byte: Int) -> Key {
  case string.utf_codepoint(byte) {
    Ok(codepoint) -> Char(string.from_utf_codepoints([codepoint]))
    Error(_) -> Unknown
  }
}

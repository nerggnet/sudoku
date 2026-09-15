//// Turning raw bytes from the terminal into keystrokes.

import gleam/list
import gleam/string
import sudoku/term

pub type Key {
  Up
  Down
  Left
  Right
  /// A digit key, 1 through 9.
  Digit(Int)
  /// A digit with shift held: `!` for 1, `"` or `@` for 2, and so on. The
  /// shifted row is not the same on every keyboard, so what counts is the
  /// position of the key rather than the character it produces.
  Shifted(Int)
  /// Anything meaning "clear this cell": 0, space, backspace or delete.
  Erase
  /// A printable key. Case is kept, so `H` and `h` are different keys.
  Char(String)
  /// Ctrl-L: draw the screen again. Whatever has made a mess of it came from
  /// outside the game, so the game cannot do better than start over.
  Redraw
  /// Input has run out, or the user pressed Ctrl-C.
  Quit
  Unknown
}

/// Read the next keystroke from the terminal.
pub fn read() -> Key {
  let #(pressed, _) = decode(Nil, fn(_) { #(term.read_byte(), Nil) })
  pressed
}

/// The same, given up on if nothing is pressed within so many milliseconds.
///
/// Only the wait for the first byte is given up on. Once a key has started
/// arriving the rest of it is read the ordinary way: an arrow is three bytes
/// and a clock going off between two of them would tear the keystroke in
/// half, leaving a `[` to be read as a keystroke of its own.
pub fn read_within(milliseconds: Int) -> Result(Key, Nil) {
  case term.read_byte_after(milliseconds) {
    -2 -> Error(Nil)
    first -> {
      let #(pressed, _) = {
        use waiting <- decode(True)
        case waiting {
          True -> #(first, False)
          False -> #(term.read_byte(), False)
        }
      }
      Ok(pressed)
    }
  }
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
    -1 -> #(Quit, source)
    _ if byte >= 0x30 && byte <= 0x39 -> numbered(byte - 0x30, source, next)
    _ -> #(Unknown, source)
  }
}

/// A numbered sequence: `ESC [ 3 ~` for Delete, and `ESC [ 1 ~`, `ESC [ 5 ~`
/// and the rest for Home, the page keys and their friends.
///
/// Only Delete means anything here, but the whole of a sequence has to be
/// read whatever it turns out to be. Reading the number and leaving the `~`
/// behind hands it to the next read, where it arrives as a keystroke the
/// player never made.
fn numbered(
  number: Int,
  source: source,
  next: fn(source) -> #(Int, source),
) -> #(Key, source) {
  let #(byte, source) = next(source)

  case byte {
    -1 -> #(Quit, source)
    _ if byte >= 0x30 && byte <= 0x39 ->
      numbered(number * 10 + byte - 0x30, source, next)
    // Whatever ends it, `~` or otherwise.
    _ ->
      case number {
        3 -> #(Erase, source)
        _ -> #(Unknown, source)
      }
  }
}

fn from_byte(byte: Int) -> Key {
  case byte {
    // Ctrl-C and Ctrl-D.
    0x03 | 0x04 -> Quit
    // Ctrl-L.
    0x0c -> Redraw
    // Backspace, delete, space and `0` all clear a cell.
    0x08 | 0x7f | 0x20 | 0x30 -> Erase
    // Carriage return and newline mean nothing here, but arrive in line mode.
    0x0a | 0x0d -> Unknown
    _ if byte >= 0x31 && byte <= 0x39 -> Digit(byte - 0x30)
    _ -> printable(byte)
  }
}

/// The number row with shift held, on two of the keyboards it is laid out
/// differently on. A player whose keyboard is neither still has `M` and a
/// digit, which no layout can get wrong.
const shifted_rows = ["!\"#$%&/()", "!@#$%^&*("]

fn printable(byte: Int) -> Key {
  case string.utf_codepoint(byte) {
    Error(_) -> Unknown
    Ok(codepoint) -> {
      let character = string.from_utf_codepoints([codepoint])
      case shifted(character) {
        Ok(digit) -> Shifted(digit)
        Error(_) -> Char(character)
      }
    }
  }
}

/// Which digit this character sits over, where every layout agrees that it
/// sits over the same one.
///
/// Some of them do not agree. `&` is shift-6 in Stockholm and shift-7 in
/// Seattle, and the byte that arrives is the same either way, so there is
/// nothing in it to say which key was pressed. A guess would be wrong for
/// half the keyboards in the world and silently wrong at that — a 6
/// pencilled in where a 7 was asked for reads like a slip of the hand. So a
/// character the rows disagree about is let go rather than guessed at, and
/// `M` and a digit is there for anybody it leaves out.
fn shifted(character: String) -> Result(Int, Nil) {
  case shifted_rows |> list.filter_map(over(_, character)) |> list.unique {
    [digit] -> Ok(digit)
    _ -> Error(Nil)
  }
}

/// Which digit the character sits over on one keyboard.
fn over(row: String, character: String) -> Result(Int, Nil) {
  row
  |> string.to_graphemes
  |> list.index_map(fn(over, index) { #(over, index + 1) })
  |> list.key_find(character)
}

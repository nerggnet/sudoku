//// Turning bytes from the terminal into keystrokes.

import helper
import sudoku/key

pub fn digits_decode_test() {
  assert helper.press([0x31]) == key.Digit(1)
  assert helper.press([0x39]) == key.Digit(9)
}

pub fn erasing_keys_decode_test() {
  // 0, space, backspace, delete.
  assert helper.press([0x30]) == key.Erase
  assert helper.press([0x20]) == key.Erase
  assert helper.press([0x08]) == key.Erase
  assert helper.press([0x7f]) == key.Erase
}

pub fn arrow_keys_decode_test() {
  assert helper.press([0x1b, 0x5b, 0x41]) == key.Up
  assert helper.press([0x1b, 0x5b, 0x42]) == key.Down
  assert helper.press([0x1b, 0x5b, 0x43]) == key.Right
  assert helper.press([0x1b, 0x5b, 0x44]) == key.Left
  // Some terminals send the application-mode form, `ESC O A`.
  assert helper.press([0x1b, 0x4f, 0x41]) == key.Up
}

pub fn a_numbered_sequence_is_read_to_its_end_test() {
  // Home, End and the page keys mean nothing here, but a sequence has to be
  // read to the end whatever it means, or its tail arrives as a keystroke
  // the player never made.
  assert helper.press_leaving([0x1b, 0x5b, 0x31, 0x7e]) == #(key.Unknown, [])
  assert helper.press_leaving([0x1b, 0x5b, 0x36, 0x7e]) == #(key.Unknown, [])

  // Two digits, as the function keys use.
  assert helper.press_leaving([0x1b, 0x5b, 0x31, 0x35, 0x7e])
    == #(key.Unknown, [])

  // What follows a sequence is the next key, and nothing else.
  assert helper.press_leaving([0x1b, 0x5b, 0x31, 0x7e, 0x35])
    == #(key.Unknown, [0x35])
}

pub fn the_delete_key_decodes_test() {
  assert helper.press([0x1b, 0x5b, 0x33, 0x7e]) == key.Erase
}

pub fn shifted_digits_decode_test() {
  // The number row with shift held. Both rows are read, so ! is a 1 either
  // way, and @ and " are each a 2 on the keyboard that has one there.
  assert helper.press([0x21]) == key.Shifted(1)
  assert helper.press([0x22]) == key.Shifted(2)
  assert helper.press([0x40]) == key.Shifted(2)
  assert helper.press([0x5e]) == key.Shifted(6)
  assert helper.press([0x2f]) == key.Shifted(7)
  assert helper.press([0x2a]) == key.Shifted(8)
  assert helper.press([0x29]) == key.Shifted(9)

  // Where the two rows disagree nobody wins. & sits over 6 on one keyboard
  // and 7 on another, and the byte says which character arrived rather than
  // which key was pressed — so it stays a character, and M and a digit is
  // the way in that no layout can get wrong.
  assert helper.press([0x26]) == key.Char("&")
  assert helper.press([0x28]) == key.Char("(")

  // A character over no digit at all is still itself.
  assert helper.press([0x3d]) == key.Char("=")
}

pub fn letter_case_is_kept_test() {
  // `h` moves the cursor and `H` asks for a hint, so they must stay distinct.
  assert helper.press([0x68]) == key.Char("h")
  assert helper.press([0x48]) == key.Char("H")
  assert helper.press([0x72]) == key.Char("r")
  assert helper.press([0x52]) == key.Char("R")
  assert helper.press([0x3f]) == key.Char("?")
}

pub fn ctrl_l_asks_for_a_redraw_test() {
  assert helper.press([0x0c]) == key.Redraw

  // It is not mistaken for a printable character, which is what it was.
  assert helper.press([0x0c]) != key.Char("\u{c}")
}

pub fn a_lone_escape_does_not_eat_the_next_key_test() {
  assert helper.press([0x1b, 0x71]) == key.Char("q")
}

pub fn running_out_of_input_quits_test() {
  assert helper.press([]) == key.Quit
  assert helper.press([0x1b]) == key.Quit
  assert helper.press([0x1b, 0x5b]) == key.Quit
  // Ctrl-C.
  assert helper.press([0x03]) == key.Quit
}

pub fn enter_does_nothing_test() {
  // Line mode delivers a newline after every key; it must not be a command.
  assert helper.press([0x0d]) == key.Unknown
  assert helper.press([0x0a]) == key.Unknown
}

//// Running the tests.
////
//// Gleeunit runs every function ending in `_test` anywhere under `test`, so
//// the tests themselves live beside the subject they are about.

import gleeunit
import sudoku/term

pub fn main() -> Nil {
  // Draw as a terminal with every colour, whatever the one running the tests
  // turns out to be.
  //
  // The palette answers to the environment now — a terminal with sixteen
  // colours washes with one grey and a dumb one washes with nothing — so a
  // test that looks at a frame is a test that would otherwise pass or fail
  // by whatever `TERM` happened to be. It said so at once: green on a
  // machine with `COLORTERM` set and red on a runner with no `TERM` at all,
  // six tests apart, and the six were right both times.
  //
  // A test that wants one of the other terminals asks for it by name, with
  // `helper.with_colours`, and puts back what it found.
  term.colouring(term.Full)
  gleeunit.main()
}

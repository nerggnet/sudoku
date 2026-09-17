//// Randomness, borrowed from Erlang's `rand` module.

@external(erlang, "sudoku_ffi", "shuffle")
pub fn shuffle(items: List(a)) -> List(a)

/// Start the chance in a deal at a named place, so that the deal can be
/// asked for again.
@external(erlang, "sudoku_ffi", "seed")
pub fn seed(from: Int) -> Nil

/// A seed nobody chose, for a deal nobody asked to have back.
@external(erlang, "sudoku_ffi", "fresh_seed")
pub fn fresh_seed() -> Int

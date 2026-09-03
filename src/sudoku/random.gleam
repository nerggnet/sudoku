//// Randomness, borrowed from Erlang's `rand` module.

@external(erlang, "sudoku_ffi", "shuffle")
pub fn shuffle(items: List(a)) -> List(a)

//// Puzzle generation.
////
//// Fill a grid at random, then keep carving clues out of it for as long as
//// the puzzle still has exactly one solution. Cells are removed in
//// rotationally symmetric pairs, which is what hand-made puzzles look like;
//// if that alone does not reach the target clue count, a second pass removes
//// single cells.

import gleam/dict
import gleam/list
import gleam/string
import sudoku/board.{type Board, type Grid, type Peers}
import sudoku/logic
import sudoku/random
import sudoku/solver

pub type Difficulty {
  Easy
  Medium
  Hard
  Expert
}

/// Where a puzzle came from: carved out of a random grid at one of the
/// difficulties, typed in by hand from a newspaper, or kept to be practised
/// on because of the one technique it cannot be finished without.
pub type Origin {
  Dealt(Difficulty)
  Handwritten
  Practising(technique: logic.Technique)
}

pub type Puzzle {
  Puzzle(board: Board, solution: Grid, origin: Origin)
}

/// The difficulties a puzzle can be dealt at, in menu order. A handwritten
/// puzzle is not among them: its clues are typed in rather than carved out,
/// so how hard it is was settled by whoever wrote it.
pub const difficulties = [Easy, Medium, Hard, Expert]

/// Every kind of puzzle there is, in the order they are offered: dealt at
/// each difficulty, easiest first, and then one typed in by hand.
pub fn origins() -> List(Origin) {
  difficulties |> list.map(Dealt) |> list.append([Handwritten])
}

pub fn label(difficulty: Difficulty) -> String {
  case difficulty {
    Easy -> "Easy"
    Medium -> "Medium"
    Hard -> "Hard"
    Expert -> "Expert"
  }
}

/// The difficulty going by this name, however it is capitalised.
pub fn named(name: String) -> Result(Difficulty, Nil) {
  use difficulty <- list.find(difficulties)
  string.lowercase(label(difficulty)) == string.lowercase(name)
}

/// How a puzzle is named on screen.
pub fn origin_label(origin: Origin) -> String {
  case origin {
    Dealt(difficulty) -> label(difficulty)
    Handwritten -> "Custom"
    // Not the technique: which one it is was just chosen from a screen that
    // said so, and is said again in the line under the board as the puzzle
    // opens. What the header is for is which kind of puzzle this is.
    Practising(_) -> "Practice"
  }
}

/// What a difficulty asks of a player: the reasoning it should call for, at
/// the least and at the most, and how many clues to leave standing.
///
/// Two different things make a puzzle hard and a difficulty sets them both.
/// One is the reasoning: a grid that never asks for more than a naked single
/// is easy whatever else is true of it. The other is how much of the grid is
/// missing, which is not reasoning at all but hunting — a singles-only puzzle
/// with twenty clues is still a long stare before the first digit goes in.
type Band {
  Band(clues: Int, floor: logic.Technique, ceiling: logic.Technique)
}

fn band(difficulty: Difficulty) -> Band {
  case difficulty {
    Easy -> Band(40, logic.NakedSingle, logic.NakedSingle)
    Medium -> Band(32, logic.HiddenSingle, logic.HiddenSingle)
    Hard -> Band(26, logic.LockedCandidates, logic.LockedCandidates)
    // The floor for the hardest puzzles, and the ceiling of what the
    // reasoning knows how to do.
    Expert -> Band(17, logic.NakedPair, logic.XWing)
  }
}

/// The hardest reasoning a puzzle at this difficulty is allowed to call for.
/// Carving stops where the next cell out would ask for more, so no dealt
/// puzzle ever needs a guess: one that could not be reasoned out was never
/// carved that far.
pub fn hardest(difficulty: Difficulty) -> logic.Technique {
  band(difficulty).ceiling
}

/// The reasoning a difficulty asks for, for the menu to say so.
pub fn asks_for(difficulty: Difficulty) -> String {
  let Band(floor:, ceiling:, ..) = band(difficulty)
  case logic.rank(floor) == logic.rank(ceiling) {
    True -> logic.labels(floor)
    False -> logic.labels(floor) <> " and better"
  }
}

/// How many grids to carve looking for one that asks for the reasoning its
/// difficulty promises.
///
/// Carving is greedy and takes what it is given, so a grid often comes out
/// easier than its level wants and the answer is to carve another. The
/// hardest of them is kept as they go, so running out of attempts deals the
/// best of the bunch rather than the last of it: a puzzle a shade easier than
/// promised beats one that never arrives.
const attempts = 30

/// A carved grid and what it turned out to ask for, kept together.
///
/// Rating a grid means reasoning it out to the end, which is the dearest
/// thing here after the carving itself. It used to be worked out three times
/// an attempt — once to ask whether the best so far was hard enough, and once
/// for each side of the comparison that keeps the harder of two — and it is
/// the same answer every time.
type Cut {
  Cut(puzzle: Puzzle, asks: Result(logic.Technique, Nil))
}

/// How a deal is going, for a screen to say so while it happens.
pub type Carving {
  Carving(attempt: Int, of: Int, asks: Result(logic.Technique, Nil))
}

pub fn generate(difficulty: Difficulty) -> Puzzle {
  generate_telling(difficulty, fn(_) { Nil })
}

/// The same, saying how it is going as it goes.
///
/// Carving is greedy and takes what it is given, so a grid often comes out
/// easier than its level wants and the answer is to carve another. Most
/// deals are over in a moment; an Expert one can take four seconds, and four
/// seconds of a screen that says the same thing throughout is the one place
/// this game looks like it has stopped working.
pub fn generate_telling(
  difficulty: Difficulty,
  telling: fn(Carving) -> Nil,
) -> Puzzle {
  let peers = board.peers_table()
  telling(Carving(attempt: 1, of: attempts, asks: Error(Nil)))
  deal(difficulty, peers, telling, 1, cut(difficulty, peers))
}

fn deal(
  difficulty: Difficulty,
  peers: Peers,
  telling: fn(Carving) -> Nil,
  taken: Int,
  best: Cut,
) -> Puzzle {
  case taken >= attempts || asks_enough(band(difficulty), best) {
    True -> best.puzzle
    False -> {
      telling(Carving(attempt: taken + 1, of: attempts, asks: best.asks))
      deal(
        difficulty,
        peers,
        telling,
        taken + 1,
        harder_of(best, cut(difficulty, peers)),
      )
    }
  }
}

/// One grid, carved as far as its difficulty will let it go, and rated once.
fn cut(difficulty: Difficulty, peers: Peers) -> Cut {
  let assert Ok(solution) = solver.search(peers, board.empty_grid(), True)
    as "an empty grid always has a solution"

  let band = band(difficulty)
  let grid =
    solution
    |> carve(band, symmetric_groups(), _)
    |> carve(band, single_groups(), _)

  Cut(
    puzzle: Puzzle(
      board: board.from_grid(grid),
      solution: solution,
      origin: Dealt(difficulty),
    ),
    asks: logic.rate(grid),
  )
}

fn asks_enough(band: Band, cut: Cut) -> Bool {
  asked_rank(cut.asks) >= logic.rank(band.floor)
}

fn harder_of(one: Cut, other: Cut) -> Cut {
  case asked_rank(other.asks) > asked_rank(one.asks) {
    True -> other
    False -> one
  }
}

/// How hard what a grid asks for is, with a grid that reasoning cannot
/// finish at all counting as below everything: it is not a puzzle at this or
/// any other difficulty.
fn asked_rank(asks: Result(logic.Technique, Nil)) -> Int {
  case asks {
    Ok(needed) -> logic.rank(needed)
    Error(_) -> -1
  }
}

// ---------------------------------------------------------------------------
// Puzzles typed in by hand
// ---------------------------------------------------------------------------

/// Why a hand-entered grid cannot be played.
pub type Rejection {
  /// Two of the same digit share a row, column or box.
  Clashes
  /// The clues obey the rules but cannot all be true at once.
  Unsolvable
  /// The clues can be finished in more than one way.
  Ambiguous
}

/// Turn a grid of hand-entered clues into a playable puzzle.
///
/// Play needs the answer as well as the clues, since checking and hints have
/// nothing to work from without it, so the grid has to have exactly one. That
/// also catches the usual slips in copying a puzzle out of a newspaper: a
/// mistyped digit leaves the grid unsolvable, and a missed one leaves it with
/// several answers.
pub fn from_clues(clues: Grid) -> Result(Puzzle, Rejection) {
  made_of(clues, Handwritten)
}

/// The same, for clues that came from somewhere other than a player typing
/// them in. They are checked exactly as sternly: a puzzle kept for practice
/// is worth nothing if it turns out to have two answers.
pub fn made_of(clues: Grid, origin: Origin) -> Result(Puzzle, Rejection) {
  case board.is_consistent(clues) {
    False -> Error(Clashes)
    True -> {
      let peers = board.peers_table()
      // Counting stops at two, which is all it takes to know the answer is
      // not unique.
      case solver.count(peers, clues, 2) {
        0 -> Error(Unsolvable)
        1 ->
          case solver.search(peers, clues, False) {
            Ok(solution) ->
              Ok(Puzzle(
                board: board.from_grid(clues),
                solution: solution,
                origin: origin,
              ))
            Error(_) -> Error(Unsolvable)
          }
        _ -> Error(Ambiguous)
      }
    }
  }
}

/// Cells paired with their 180-degree rotation, centre cell on its own.
fn symmetric_groups() -> List(List(Int)) {
  board.span(0, board.cell_count / 2 - 1)
  |> list.map(fn(index) { [index, board.cell_count - 1 - index] })
  |> list.prepend([board.cell_count / 2])
  |> random.shuffle
}

fn single_groups() -> List(List(Int)) {
  board.indices() |> list.map(fn(index) { [index] }) |> random.shuffle
}

/// Take each group of cells out in turn, keeping the ones the puzzle can
/// spare and putting back the ones it cannot.
///
/// A grid the reasoning can finish has exactly one answer, since every step
/// it took was forced, so asking whether the puzzle is still within its
/// difficulty asks whether it still has a single answer at the same time.
fn carve(band: Band, groups: List(List(Int)), grid: Grid) -> Grid {
  use grid, group <- list.fold(groups, grid)

  case clue_count(grid) <= band.clues {
    True -> grid
    False -> {
      let stripped =
        list.fold(group, grid, fn(grid, index) { dict.insert(grid, index, 0) })

      case within(band.ceiling, stripped) {
        True -> stripped
        False -> grid
      }
    }
  }
}

fn clue_count(grid: Grid) -> Int {
  grid |> dict.values |> list.count(fn(digit) { digit != 0 })
}

fn within(ceiling: logic.Technique, grid: Grid) -> Bool {
  case logic.rate(grid) {
    Ok(needed) -> logic.rank(needed) <= logic.rank(ceiling)
    Error(_) -> False
  }
}

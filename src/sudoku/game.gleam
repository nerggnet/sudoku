//// The state of a game in progress, and the plain facts about it.
////
//// What a keystroke does with all this is next door in `rules`, and what a
//// hint makes of it in `hint`. Both of those reach in here; nothing here
//// reaches back out, which is what lets the three be three.

import gleam/dict
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/set
import sudoku/board.{type Board}
import sudoku/date
import sudoku/generator.{type Puzzle}
import sudoku/key.{type Key}
import sudoku/logic
import sudoku/term

// --------------------------------------------------------------------------
// What a game is
// --------------------------------------------------------------------------

const max_undo = 200

/// How many wrong digits checking will call out before the puzzle is lost.
/// The one after that forfeits it.
///
/// Checking turns a guess into a free question, and without a price on it
/// there is nothing to stop a player asking the grid rather than reading it.
pub const mistake_limit = 3

pub type Game {
  Game(
    /// Which saved game this is, so that two being played at once do not
    /// write over one another. It names the file and nothing else.
    id: String,
    puzzle: Puzzle,
    board: Board,
    cursor: Int,
    history: List(Moment),
    /// Moments undone, waiting to be done again. Anything else written to the
    /// board empties it: the way back is only the way back from here.
    undone: List(Moment),
    message: String,
    /// Whether wrong digits are being called out.
    checking: Bool,
    /// Whether the digit keys write pencil marks instead of answers.
    marking: Bool,
    /// The page of help on show, if any.
    help: Option(Help),
    /// Whether the board is put away and the clock stopped.
    ///
    /// Safe to offer because the board goes with it. A pause that left the
    /// grid on screen would be a way to think about it for nothing, and a
    /// best time is only worth having if the clock could not be talked out
    /// of running.
    paused: Bool,
    /// When the game stopped counting, while it is stopped — the help going
    /// up, or a pause. Reading is not playing and neither is being away, so
    /// the clock waits for both.
    resting_since: Option(Int),
    /// What the game has offered to do if asked a second time.
    offered: Option(Offer),
    /// What the record books made of this game, once it was over.
    verdict: Option(Verdict),
    /// The step the last hint gave, until the next keystroke: what the board
    /// marks out, and which page of the help `?` opens at.
    showing: Option(logic.Step),
    /// The digit being looked for, if any.
    scan: Scan,
    /// How far the tutor has been asked to go at the position the board is
    /// in now.
    ///
    /// Unlike an offer or a hint's markings, this outlives a keystroke: the
    /// whole point of being told where to look is looking, and a lesson that
    /// went away the moment the cursor moved would be a lesson nobody could
    /// act on. It goes when the board changes instead, the position it was
    /// about having gone.
    teaching: Teaching,
    /// A digit asked for and not yet given, until the next keystroke.
    asking: Asking,
    hints: Int,
    /// Wrong digits checking has caught, counting towards `mistake_limit`.
    mistakes: Int,
    /// Whether the game has been helped along — by checking, or by a hint —
    /// and so is no longer a time worth keeping.
    aided: Bool,
    /// How the game ended, once it has. Set together with `finished_ms`.
    ending: Option(Ending),
    started_ms: Int,
    finished_ms: Option(Int),
  )
}

/// Something the game will do if asked again, having declined to do it
/// unasked.
///
/// An offer stands only until the next keystroke. Asking again means asking
/// again straight away, so that a key pressed a minute later cannot turn out
/// to have meant something the player has long since forgotten offering.
pub type Offer {
  /// Nothing settles this cell yet. Asking again looks elsewhere.
  LookElsewhere(Int)
  /// Every empty cell is marked up. Asking again marks them all afresh,
  /// which is the only way to be rid of marks made wrongly by hand.
  RedoMarks
  /// There is a puzzle under way. Asking again gives it up.
  GiveUp
  /// The game is still the player's own work. Asking again takes a hint, and
  /// it stops being.
  TakeHint
  /// Checking is off. Asking again switches it on, for good, and with
  /// whatever that costs where it stands.
  StartChecking
  /// There is a puzzle here to solve. Asking again fills the answer in and
  /// ends it.
  Reveal
  /// There is work on the grid. Asking again wipes it back to the clues.
  StartAgain
}

/// The key that made an offer is the key that takes it up. Anything else
/// puts the offer away.
pub fn asked_by(offer: Offer) -> List(Key) {
  case offer {
    LookElsewhere(_) -> [key.Char("H")]
    RedoMarks -> [key.Char("f")]
    GiveUp -> [key.Char("n"), key.Char("N")]
    TakeHint -> [key.Char("H")]
    StartChecking -> [key.Char("c")]
    Reveal -> [key.Char("R")]
    StartAgain -> [key.Char("X")]
  }
}

/// The board as it was, and where the player was looking when it was that
/// way.
///
/// The cursor rides along with the board because a change taken back where
/// nobody is looking might as well not have happened. It is the cell the
/// change is about rather than wherever the player has since wandered: you
/// were standing at the cell when you wrote in it, and that is the cell that
/// changes again whichever way the pile is walked.
pub type Moment {
  Moment(board: Board, cursor: Int)
}

/// Looking for somewhere a digit can still go.
///
/// This is a way of reading the board rather than a thing the game knows and
/// the player does not: where a digit can go is there to be worked out from
/// the row, the column and the box, by anyone willing to look. So it costs
/// nothing, the same as pencilling the candidates in costs nothing.
pub type Scan {
  NotScanning
  /// Every empty cell this digit could still go in is marked out, and stays
  /// marked out while the player moves about looking at them.
  ScanningFor(digit: Int)
}

/// A key that has asked for a digit and is waiting to hear which one.
///
/// Two keys ask, and a digit means whatever the one that asked meant it to.
/// Only the very next keystroke: asking is not a mode to be in, and anything
/// else means the player has gone back to playing, so that keystroke should
/// do what it always does.
///
/// One question at a time, which is why this is one field rather than a flag
/// apiece. Nothing can be waiting to hear two answers to the same digit.
pub type Asking {
  NotAsking
  /// `S`: which digit to look for.
  WhichToLookFor
  /// `M`: which digit to pencil in, or rub out.
  WhichToPencil
}

/// The help, a page at a time: the keys, and then a page on each way of
/// working a digit out.
pub type Help {
  /// Getting about the board and putting digits on it, and the three keys
  /// that mean the same thing wherever they are pressed.
  Keys
  /// Pencilling, and what the grid beside the board is showing.
  Marking
  /// Asking the game for something, and the ways a game ends.
  Asking
  Starting
  /// The ways of being handed a puzzle somebody else had: a seed, and the
  /// day. A page of its own because the one before it was full, which is
  /// the same reason the keys take two.
  Repeating
  About(logic.Technique)
}

/// Every page, in the order they are paged through.
pub fn pages() -> List(Help) {
  [
    Keys,
    Marking,
    Asking,
    Starting,
    Repeating,
    ..list.map(logic.techniques, About)
  ]
}

/// What the record books make of a game that is over.
///
/// Only a puzzle solved unaided is timed. Checking and hints both work from
/// the answer, and a time set with the answer to hand is not a time; filling
/// the candidates in is another matter, since it works out nothing the player
/// could not have worked out with a pencil.
pub type Verdict {
  /// Quicker than anything at this difficulty before it, and written down.
  BestYet
  /// Quicker than anything before it, but the record books would not take
  /// it. A time nobody can look up afterwards is worth saying out loud now.
  BestNotKept
  /// Timed, with a standing best still to beat.
  Behind(best: Int)
  /// Not timed: the game was asked for something along the way.
  Aided
  /// Not timed: a puzzle typed in has no difficulty to file a time under,
  /// and a game not won has no time to file.
  Untimed
  /// The day's puzzle, done and written into the book of days, and how many
  /// days in a row that makes.
  ///
  /// Not a best and not a personal record: there is one of these a day and
  /// everybody gets the same one, so the thing worth saying about a time is
  /// that it is yours for that day rather than that it beat something. What
  /// there is to beat is the run of days, and only your own.
  DailyDone(running: Int)
  /// The same, but the book would not take it.
  DailyNotKept
  /// This day had already been done, in that time, and that time stands.
  ///
  /// A day played a second time is a day whose answer is already known, so
  /// a quicker run at it is not a quicker solve. The first is kept.
  DailyAlready(first: Int)
}

/// Whether the game is still the player's own work.
///
/// Kept as a fact of its own rather than worked out from the hints taken and
/// the checking asked for, because the player is told it is about to become
/// true and agrees to it. What they agreed to should not then depend on what
/// the hint turned out to say.
pub fn unaided(game: Game) -> Bool {
  !game.aided
}

/// How many times over the tutor has been asked about this position.
///
/// A count rather than a named rung, because what each answer says depends
/// on the step the position turns out to want, and that is worked out afresh
/// every time rather than carried.
pub type Teaching {
  NotTeaching
  Teaching(asked: Int)
}

/// The three ways a game can be over.
pub type Ending {
  Solved
  /// The grid was revealed rather than worked out.
  Revealed
  /// One wrong digit too many while checking.
  Forfeited
}

/// What the main loop should do after handling a key.
pub type Step {
  Continue(Game)
  Restart
  Exit
}

// --------------------------------------------------------------------------
// Starting one, and asking after it
// --------------------------------------------------------------------------

pub fn new(puzzle: Puzzle) -> Game {
  Game(
    id: term.new_id(),
    puzzle: puzzle,
    board: puzzle.board,
    cursor: first_empty(puzzle.board) |> option.unwrap(0),
    history: [],
    undone: [],
    message: opening(puzzle.origin),
    checking: False,
    marking: False,
    help: None,
    paused: False,
    resting_since: None,
    offered: None,
    verdict: None,
    showing: None,
    scan: NotScanning,
    teaching: NotTeaching,
    asking: NotAsking,
    hints: 0,
    mistakes: 0,
    aided: False,
    ending: None,
    started_ms: term.now_ms(),
    finished_ms: None,
  )
}

/// What the game says as a puzzle opens.
///
/// A grid kept for practising says what it is for. Which technique is not
/// something to work out by playing until something goes wrong: it was
/// chosen a screen ago, and being told again is what makes the grid a
/// lesson rather than a puzzle that happens to be hard in one place.
fn opening(origin: generator.Origin) -> String {
  case origin {
    generator.Practising(technique) ->
      "This grid cannot be finished without "
      <> logic.labels(technique)
      <> ".\nPress ? for the page explaining them."
    // Which day this is, since the header has only room to say how hard it
    // is, and a daily picked up a week after it was put down is otherwise a
    // puzzle with no date on it at all.
    generator.Daily(on) ->
      "The puzzle for "
      <> date.day_name(date.weekday(on))
      <> " "
      <> date.to_string(on)
      <> ".\nPress ? for help."
    _ -> "Press ? for help."
  }
}

pub fn is_finished(game: Game) -> Bool {
  game.finished_ms != None
}

pub fn elapsed_ms(game: Game) -> Int {
  case game.finished_ms {
    Some(finished) -> finished - game.started_ms
    None -> term.now_ms() - game.started_ms
  }
}

/// The digit the solution has for a cell.
pub fn answer(game: Game, index: Int) -> Int {
  case dict.get(game.puzzle.solution, index) {
    Ok(digit) -> digit
    Error(_) -> 0
  }
}

/// A filled-in, non-clue cell that disagrees with the solution.
pub fn is_wrong(game: Game, index: Int) -> Bool {
  let digit = board.value(game.board, index)
  digit != 0
  && !board.is_given(game.board, index)
  && digit != answer(game, index)
}

// --------------------------------------------------------------------------
// Changing one
// --------------------------------------------------------------------------

/// The three below are the only way the board itself changes, and both
/// `rules` and `hint` write through them: a digit placed by hand and one
/// placed by a hint should land on the undo pile the same way and finish the
/// puzzle the same way.
pub fn with_board(game: Game, next: Board) -> Game {
  // The lesson was about the position, and this is a different one.
  Game(..game, board: next, message: "", teaching: NotTeaching)
}

/// What the reasoning should read off a game: the candidates the grid
/// allows, narrowed wherever the player has pencilled something in.
///
/// A player's marks are a position of their own — narrower than the grid
/// alone allows wherever they have been working — and reasoning from them is
/// what lets one step that rules candidates out lead to the next.
pub fn reading(current: Game) -> logic.Pencil {
  use marks, index <- list.fold(
    board.indices(),
    logic.pencil(current.board.values),
  )

  let theirs = board.marks_at(current.board, index)
  case board.value(current.board, index) == 0 && !set.is_empty(theirs) {
    True -> dict.insert(marks, index, theirs)
    False -> marks
  }
}

/// Put this moment on the pile to come back to, and throw away the way
/// forward: whatever is about to happen is a different way forward.
pub fn remember(game: Game) -> Game {
  Game(
    ..game,
    history: list.take(
      [Moment(board: game.board, cursor: game.cursor), ..game.history],
      max_undo,
    ),
    undone: [],
  )
}

/// Notice when the last keystroke completed the puzzle.
pub fn settle(game: Game) -> Game {
  case board.is_solved(game.board) {
    False -> game
    // Checking is left on: it is the record that the game was asked, and a
    // solved grid has nothing left for it to call out anyway.
    True -> Game(..game, ending: Some(Solved), finished_ms: Some(term.now_ms()))
  }
}

pub fn first_empty(current: Board) -> Option(Int) {
  board.indices()
  |> list.find(fn(index) { board.value(current, index) == 0 })
  |> option.from_result
}

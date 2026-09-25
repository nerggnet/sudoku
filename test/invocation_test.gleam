//// Reading a command line.

import gleam/list
import gleam/option
import gleam/string
import helper
import sudoku/board
import sudoku/generator
import sudoku/help
import sudoku/invocation

fn read(arguments: List(String)) -> Result(invocation.Invocation, String) {
  invocation.read(arguments)
}

pub fn no_arguments_leave_it_to_the_menu_test() {
  assert read([])
    == Ok(invocation.Invocation(invocation.Menu, False, option.None))
}

pub fn a_difficulty_is_dealt_straight_away_test() {
  use difficulty <- list.each(generator.difficulties)
  let name = generator.label(difficulty)

  // However it is capitalised: a command line is typed in a hurry.
  use spelling <- list.each([
    name,
    string.lowercase(name),
    string.uppercase(name),
  ])
  assert read([spelling])
    == Ok(invocation.Invocation(invocation.Deal(difficulty), False, option.None))
}

pub fn custom_and_resume_are_words_of_their_own_test() {
  assert read(["custom"])
    == Ok(invocation.Invocation(invocation.Compose, False, option.None))
  assert read(["Resume"])
    == Ok(invocation.Invocation(invocation.Resume, False, option.None))
}

pub fn a_puzzle_is_taken_as_its_eighty_one_characters_test() {
  let clues = board.to_string(helper.grid(helper.puzzle_text))
  let assert Ok(invocation.Invocation(
    invocation.Play(puzzle),
    False,
    option.None,
  )) = read([clues])

  assert puzzle.board.values == helper.grid(helper.puzzle_text)
  assert puzzle.origin == generator.Handwritten

  // And the answer came with it, since the game needs one to check against.
  assert puzzle.solution == helper.grid(helper.solution_text)
}

pub fn a_puzzle_that_is_not_one_is_refused_by_its_clues_test() {
  // The right length, so it was meant as a puzzle: the complaint should be
  // about the puzzle rather than about how to start the game.
  let assert Error(complaint) = read([string.repeat(".", 81)])

  assert !string.contains(complaint, "Usage:")
  assert string.contains(string.lowercase(complaint), "answer")
}

pub fn a_word_that_is_neither_gets_the_usage_test() {
  let assert Error(complaint) = read(["impossible"])
  assert complaint == help.usage()

  // As does more than one thing to play at once.
  assert read(["easy", "hard"]) == Error(help.usage())
}

pub fn the_plain_flag_can_come_on_either_side_test() {
  let dealt = invocation.Deal(generator.Hard)

  assert read(["--plain"])
    == Ok(invocation.Invocation(invocation.Menu, True, option.None))
  assert read(["--plain", "hard"])
    == Ok(invocation.Invocation(dealt, True, option.None))
  assert read(["hard", "--plain"])
    == Ok(invocation.Invocation(dealt, True, option.None))
}

pub fn a_flag_the_game_does_not_know_gets_the_usage_test() {
  assert read(["--colour"]) == Error(help.usage())
  assert read(["--plain", "--colour"]) == Error(help.usage())
  assert read(["-p"]) == Error(help.usage())
}

pub fn the_usage_names_every_way_in_test() {
  // The flag is one of the invocations the help lists, so the two cannot
  // come to disagree about what the game accepts.
  assert list.any(help.every_invocation(), fn(entry) {
    string.contains(entry.0, invocation.plain_flag)
  })
}

pub fn asking_what_the_command_line_takes_is_not_a_mistake_test() {
  use flag <- list.each(invocation.help_flags)
  let assert Ok(asked) = invocation.read([flag])
  assert asked.asked == invocation.Explain

  // Nothing beside it can turn the question into a mistake: not a puzzle,
  // not a difficulty, and not a flag that would have been one on its own.
  let assert Ok(beside) = invocation.read(["hard", flag])
  assert beside.asked == invocation.Explain

  let assert Ok(muddled) = invocation.read([flag, "--nonsense"])
  assert muddled.asked == invocation.Explain

  // And a flag that says how the game should look is still read.
  let assert Ok(plainly) = invocation.read([flag, invocation.plain_flag])
  assert plainly.asked == invocation.Explain
  assert plainly.plain
}

pub fn asking_which_build_this_is_is_not_a_mistake_either_test() {
  use flag <- list.each(invocation.version_flags)
  let assert Ok(asked) = invocation.read([flag])
  assert asked.asked == invocation.Name

  // Indulged the same way, and for a better reason than --help is: the line
  // carrying it is most often one being pasted into a bug report, beside
  // whatever the game was started with when it went wrong.
  let assert Ok(beside) = invocation.read(["hard", "--seed", "7", flag])
  assert beside.asked == invocation.Name

  let assert Ok(muddled) = invocation.read([flag, "--nonsense"])
  assert muddled.asked == invocation.Name
}

pub fn a_line_asking_both_questions_is_answered_with_the_larger_one_test() {
  // Somebody who typed both wants to be told what the game takes, and the
  // usage says how to ask for the version anyway — so the help wins and the
  // answer they did not get is one line away.
  let assert Ok(both) = invocation.read(["--version", "--help"])
  assert both.asked == invocation.Explain
}

pub fn the_usage_says_how_to_ask_for_it_test() {
  // One row for the two spellings, since -h is the same question in fewer
  // letters and a second row saying so would be a row about nothing.
  assert string.contains(help.usage(), "--help")
  assert invocation.help_flags == ["--help", "-h"]

  // The same, for the same reason. Capital V, the lowercase one meaning
  // something else wherever it means anything.
  assert string.contains(help.usage(), "--version")
  assert invocation.version_flags == ["--version", "-V"]
}

pub fn a_seed_is_read_either_way_round_test() {
  let dealt = invocation.Deal(generator.Hard)

  assert read(["hard", "--seed", "42"])
    == Ok(invocation.Invocation(dealt, False, option.Some(42)))
  assert read(["hard", "--seed=42"])
    == Ok(invocation.Invocation(dealt, False, option.Some(42)))

  // And from either side of the difficulty, the way --plain can.
  assert read(["--seed", "42", "hard"])
    == Ok(invocation.Invocation(dealt, False, option.Some(42)))
  assert read(["--seed=42", "hard"])
    == Ok(invocation.Invocation(dealt, False, option.Some(42)))

  // Beside the other flag, in any order.
  assert read(["--plain", "hard", "--seed", "42"])
    == Ok(invocation.Invocation(dealt, True, option.Some(42)))
}

pub fn a_seed_that_is_not_a_number_is_refused_by_name_test() {
  use line <- list.each([
    ["hard", "--seed", "banana"],
    ["hard", "--seed=banana"],
  ])
  let assert Error(complaint) = read(line)

  // Named, rather than the usage: the line was almost right, and which word
  // was wrong is the thing worth saying.
  assert !string.contains(complaint, "Usage:")
  assert string.contains(complaint, "banana")
}

pub fn a_seed_with_nothing_after_it_says_so_test() {
  let assert Error(complaint) = read(["hard", "--seed"])
  assert string.contains(complaint, invocation.seed_flag)

  // A flag where the number should be is the same slip, and the complaint
  // names what turned up instead.
  let assert Error(beside) = read(["hard", "--seed", "--plain"])
  assert string.contains(beside, "--plain")
}

pub fn two_seeds_are_two_deals_and_neither_is_taken_test() {
  let assert Error(complaint) = read(["hard", "--seed", "1", "--seed", "2"])
  assert string.contains(complaint, invocation.seed_flag)
}

/// A seed names a deal, so there has to be one on the line to name. The
/// menu is not one: a seed given there would sit unused while somebody
/// picked a difficulty, and the puzzle they got would not be the one the
/// seed promised.
pub fn a_seed_wants_a_difficulty_beside_it_test() {
  let clues = board.to_string(helper.grid(helper.puzzle_text))

  use line <- list.each([
    ["--seed", "42"],
    ["custom", "--seed", "42"],
    ["resume", "--seed", "42"],
    [clues, "--seed", "42"],
  ])
  let assert Error(complaint) = read(line)

  assert string.contains(complaint, invocation.seed_flag)
  assert string.contains(complaint, "difficulty")
}

/// Help still wins over everything on the line, a seed that is not a number
/// included: somebody who types --help is asking what the words mean, and
/// being told they got one of them wrong is not an answer to that.
pub fn help_outranks_a_seed_that_will_not_read_test() {
  let assert Ok(asked) = read(["--help", "hard", "--seed", "banana"])
  assert asked.asked == invocation.Explain

  let assert Ok(alone) = read(["--seed", "--help"])
  assert alone.asked == invocation.Explain
}

pub fn the_usage_names_the_seed_flag_test() {
  assert list.any(help.every_invocation(), fn(entry) {
    string.contains(entry.0, invocation.seed_flag)
  })
  assert string.contains(help.usage(), invocation.seed_flag)
}

pub fn the_usage_names_the_daily_test() {
  assert list.any(help.every_invocation(), fn(entry) {
    string.contains(entry.0, invocation.daily_word)
  })
  assert string.contains(help.usage(), invocation.daily_word)
}

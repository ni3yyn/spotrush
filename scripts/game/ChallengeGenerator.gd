class_name ChallengeGenerator
extends RefCounted

## v16 RUN FORGE - compatibility facade.
##
## The old per-round tier-table generator (fixed rotation, hardcoded
## margins, thresholds and layouts) is gone; all generation now flows
## through the RunDeck system (see scripts/challenges/). This facade keeps
## the historical entry point working for any code that still asks for a
## single challenge: it forges a minimal deck from the given seed and
## deals the requested round out of it, so even one-off calls get curve
## difficulty, variety-checked phrasing, computed answers and the same
## quality gate as a full run.

## Generate one challenge for a given round index, forged from a deck.
## seed_val <= 0 draws fresh entropy (a never-before-seen round).
static func generate_challenge(round_index: int, difficulty: int = 1, seed_val: int = -1) -> ChallengeDefinition:
	var start_band := clampi(difficulty, GameConfig.DIFFICULTY_MIN, GameConfig.DIFFICULTY_MAX)
	var rounds := maxi(round_index + 1, GameConfig.MIN_ROUNDS)
	var deck := RunDeck.forge(rounds, seed_val, start_band, false, 0.5)
	return deck.begin_round(mini(round_index, rounds - 1))

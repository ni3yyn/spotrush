class_name TestAnswerValidation
extends RefCounted

static func run_all_tests() -> Dictionary:
	var passed = 0
	var failed = 0
	var errors = []
	
	# Setup sample choice challenge
	var ch = ChallengeDefinition.new("test_ch_1", "choice_type", "Pick correct option", 6.0)
	ch.input_mode = "choice"
	ch.options = ["A", "B", "C", "D"]
	ch.correct_answer = "B"
	
	# Test 1: Valid correct answer
	var res1 = AnswerValidator.validate_submission(ch, "B", 2.0, false)
	if res1["is_correct"] == true and res1["is_valid_format"] == true:
		passed += 1
	else:
		failed += 1
		errors.append("Valid correct answer failed validation")
		
	# Test 2: Valid incorrect answer
	var res2 = AnswerValidator.validate_submission(ch, "A", 2.5, false)
	if res2["is_correct"] == false and res2["is_valid_format"] == true:
		passed += 1
	else:
		failed += 1
		errors.append("Incorrect answer unexpectedly marked correct")
		
	# Test 3: Late answer rejection
	var res3 = AnswerValidator.validate_submission(ch, "B", 7.0, false)
	if res3["is_correct"] == false:
		passed += 1
	else:
		failed += 1
		errors.append("Late answer was not rejected!")

	# Test 4: Tap targets validation
	var tap_ch = ChallengeDefinition.new("test_tap_1", "tap_type", "Tap targets", 8.0)
	tap_ch.input_mode = "tap_targets"
	tap_ch.correct_answer = 2
	tap_ch.visual_data = {
		"items": [
			{"is_target": true},
			{"is_target": false},
			{"is_target": true},
			{"is_target": false}
		]
	}
	
	# Player tapped [0, 2] -> all targets hit!
	var res4 = AnswerValidator.validate_submission(tap_ch, [0, 2], 3.0, false)
	if res4["is_correct"] == true:
		passed += 1
	else:
		failed += 1
		errors.append("All targets tapped was not marked correct")
		
	# Player tapped [0, 1] -> hit 1 target and 1 distractor
	var res5 = AnswerValidator.validate_submission(tap_ch, [0, 1], 3.0, false)
	if res5["is_correct"] == false:
		passed += 1
	else:
		failed += 1
		errors.append("Distractor tap was not marked incorrect")

	# Test 5: Withhold response (Don't tap) validation
	var withhold_ch = ChallengeDefinition.new("test_withhold", "dont_tap", "Don't tap!", 4.0)
	withhold_ch.input_mode = "withhold_response"
	withhold_ch.correct_answer = true # should withhold
	
	# Player withheld until timeout
	var res6 = AnswerValidator.validate_submission(withhold_ch, null, 4.0, true)
	if res6["is_correct"] == true:
		passed += 1
	else:
		failed += 1
		errors.append("Withheld response until timeout was not marked correct")
		
	# Player tapped when instructed not to
	var res7 = AnswerValidator.validate_submission(withhold_ch, "TAP", 1.5, false)
	if res7["is_correct"] == false:
		passed += 1
	else:
		failed += 1
		errors.append("Premature tap on withhold challenge was not marked incorrect")
		
	return {
		"name": "AnswerValidationTests",
		"passed": passed,
		"failed": failed,
		"errors": errors
	}

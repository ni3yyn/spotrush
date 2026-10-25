class_name TestChallengeGeneration
extends RefCounted

static func run_all_tests() -> Dictionary:
	var passed = 0
	var failed = 0
	var errors = []
	
	# Test 1: Check generation across all difficulty tiers
	for diff in [1, 2, 3, 4]:
		for round_idx in range(10):
			var ch = ChallengeGenerator.generate_challenge(round_idx, diff, 1000 + round_idx * 10 + diff)
			if ch == null:
				failed += 1
				errors.append("Challenge is null for round %d, diff %d" % [round_idx, diff])
				continue
			if not ch.is_valid():
				failed += 1
				errors.append("Challenge invalid for round %d, diff %d: %s" % [round_idx, diff, ch.type])
				continue
			passed += 1
			
	# Test 2: Quantity Estimation Challenge Integrity
	var est = ChallengeGenerator.generate_estimation_count(RandomNumberGenerator.new(), 1, 2)
	if est.options.has(est.correct_answer):
		passed += 1
	else:
		failed += 1
		errors.append("Estimation correct answer not in options list!")
		
	if est.visual_data["items"].size() == est.correct_answer:
		passed += 1
	else:
		failed += 1
		errors.append("Visual item count (%d) doesn't match correct answer (%d)" % [est.visual_data["items"].size(), est.correct_answer])

	# Test 3: Side Comparison Integrity
	var comp = ChallengeGenerator.generate_side_comparison(RandomNumberGenerator.new(), 2, 2)
	var left_c = comp.visual_data["left_count"]
	var right_c = comp.visual_data["right_count"]
	var expected_winner = "LEFT" if left_c > right_c else "RIGHT"
	if comp.correct_answer == expected_winner:
		passed += 1
	else:
		failed += 1
		errors.append("Side comparison winner mismatch!")
		
	# Test 4: Serialization round-trip
	var serialized = est.to_dict()
	var deserialized = ChallengeDefinition.from_dict(serialized)
	if deserialized.is_valid() and deserialized.id == est.id and deserialized.correct_answer == est.correct_answer:
		passed += 1
	else:
		failed += 1
		errors.append("Serialization round-trip failed!")
		
	return {
		"name": "ChallengeGenerationTests",
		"passed": passed,
		"failed": failed,
		"errors": errors
	}

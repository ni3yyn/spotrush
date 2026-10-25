class_name AnswerValidator
extends RefCounted

static func validate_submission(
	challenge: ChallengeDefinition,
	player_submission: Variant,
	elapsed_time: float,
	is_timeout: bool
) -> Dictionary:
	if challenge == null or not challenge.is_valid():
		return {
			"is_valid_format": false,
			"is_correct": false,
			"accuracy": 0.0,
			"details": "Invalid challenge specification"
		}
		
	if is_timeout:
		if challenge.input_mode == "withhold_response":
			# If the rule was "Do not tap", withholding until timeout is correct!
			var should_withhold: bool = bool(challenge.correct_answer)
			return {
				"is_valid_format": true,
				"is_correct": should_withhold,
				"accuracy": 1.0 if should_withhold else 0.0,
				"details": "Withheld until timeout (Correct)" if should_withhold else "Timeout without action"
			}
		return {
			"is_valid_format": true,
			"is_correct": false,
			"accuracy": 0.0,
			"details": "Time limit expired"
		}
		
	# Answer arrived before timeout
	if elapsed_time > challenge.time_limit + 0.5: # 500ms grace period for network jitter
		return {
			"is_valid_format": true,
			"is_correct": false,
			"accuracy": 0.0,
			"details": "Late answer rejected"
		}
		
	match challenge.input_mode:
		"choice":
			var submitted_str: String = str(player_submission).strip_edges().to_upper()
			var correct_str: String = str(challenge.correct_answer).strip_edges().to_upper()
			var is_correct = (submitted_str == correct_str)
			return {
				"is_valid_format": true,
				"is_correct": is_correct,
				"accuracy": 1.0 if is_correct else 0.0,
				"details": "Correct selection" if is_correct else "Incorrect selection"
			}
			
		"tap_targets":
			# player_submission should be an Array of tapped item indices
			if not (player_submission is Array):
				return {
					"is_valid_format": false,
					"is_correct": false,
					"accuracy": 0.0,
					"details": "Submission must be an array of tapped indices"
				}
				
			var items: Array = challenge.visual_data.get("items", [])
			var target_indices: Array = []
			for i in range(items.size()):
				if items[i].get("is_target", false) == true:
					target_indices.append(i)
					
			var tapped_set: Array = player_submission
			var false_positives: int = 0
			var true_positives: int = 0
			
			for idx in tapped_set:
				if idx in target_indices:
					true_positives += 1
				else:
					false_positives += 1
					
			var is_correct = (false_positives == 0) and (true_positives == target_indices.size())
			var accuracy = 0.0
			if target_indices.size() > 0:
				accuracy = clampf(float(true_positives - false_positives) / float(target_indices.size()), 0.0, 1.0)
				
			return {
				"is_valid_format": true,
				"is_correct": is_correct,
				"accuracy": accuracy,
				"details": ("All %d targets tapped!" % target_indices.size()) if is_correct else ("Missed or tapped wrong items (Hits: %d, Faults: %d)" % [true_positives, false_positives])
			}
			
		"withhold_response":
			# If player tapped before timeout
			var should_withhold: bool = bool(challenge.correct_answer)
			var is_correct = not should_withhold
			return {
				"is_valid_format": true,
				"is_correct": is_correct,
				"accuracy": 1.0 if is_correct else 0.0,
				"details": "Tapped when instructed" if is_correct else "Tapped on a Don't Tap challenge!"
			}
			
		_:
			return {
				"is_valid_format": false,
				"is_correct": false,
				"accuracy": 0.0,
				"details": "Unknown input mode"
			}

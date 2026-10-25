class_name ChallengeDefinition
extends RefCounted

var id: String = ""
var type: String = ""
var difficulty: int = 1
var instruction: String = ""
var time_limit: float = 8.0
var visual_data: Dictionary = {}
var options: Array = []
var correct_answer: Variant = null
var input_mode: String = "choice" # "choice", "tap_targets", "withhold_response"
var version: int = 1

func _init(p_id: String = "", p_type: String = "", p_instruction: String = "", p_time_limit: float = 8.0) -> void:
	id = p_id
	type = p_type
	instruction = p_instruction
	time_limit = p_time_limit

func to_dict() -> Dictionary:
	return {
		"id": id,
		"type": type,
		"difficulty": difficulty,
		"instruction": instruction,
		"time_limit": time_limit,
		"visual_data": visual_data,
		"options": options,
		"correct_answer": correct_answer,
		"input_mode": input_mode,
		"version": version
	}

static func from_dict(data: Dictionary) -> ChallengeDefinition:
	var c = ChallengeDefinition.new(
		data.get("id", ""),
		data.get("type", ""),
		data.get("instruction", ""),
		float(data.get("time_limit", 8.0))
	)
	c.difficulty = int(data.get("difficulty", 1))
	c.visual_data = data.get("visual_data", {})
	c.options = data.get("options", [])
	c.correct_answer = data.get("correct_answer", null)
	c.input_mode = data.get("input_mode", "choice")
	c.version = int(data.get("version", 1))
	return c

func is_valid() -> bool:
	if id.is_empty():
		return false
	if type.is_empty():
		return false
	if instruction.is_empty():
		return false
	if time_limit <= 0.0:
		return false
	
	match input_mode:
		"choice":
			if options.is_empty():
				return false
			# Correct answer must be one of the options
			var found = false
			for opt in options:
				if str(opt) == str(correct_answer):
					found = true
					break
			if not found:
				return false
		"tap_targets":
			# Needs visual items and expected target count >= 0
			if not visual_data.has("items") or not (visual_data["items"] is Array):
				return false
			if not (correct_answer is int) or correct_answer < 0:
				return false
		"withhold_response":
			# Boolean whether action should be withheld or tapped
			if typeof(correct_answer) != TYPE_BOOL:
				return false
		_:
			return false
			
	return true

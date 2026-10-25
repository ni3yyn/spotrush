extends Node

const TestChallengeGeneration = preload("res://tests/test_challenge_generation.gd")
const TestAnswerValidation = preload("res://tests/test_answer_validation.gd")
const TestScoring = preload("res://tests/test_scoring.gd")
const TestNetworkingLogic = preload("res://tests/test_networking_logic.gd")
const TestFullGameLoop = preload("res://tests/test_full_game_loop.gd")
const TestMultiplayerSimulation = preload("res://tests/test_multiplayer_simulation.gd")
const TestUiSceneFlow = preload("res://tests/test_ui_scene_flow.gd")

func _ready() -> void:
	print("\n==========================================")
	print("       SPOTRUSH AUTOMATED TEST SUITE      ")
	print("==========================================\n")
	
	var all_passed = true
	var total_passed = 0
	var total_failed = 0
	
	var suites = [
		TestChallengeGeneration.run_all_tests(),
		TestAnswerValidation.run_all_tests(),
		TestScoring.run_all_tests(),
		TestNetworkingLogic.run_all_tests(),
		TestFullGameLoop.run_all_tests(),
		TestMultiplayerSimulation.run_all_tests(),
		TestUiSceneFlow.run_all_tests()
	]
	
	for suite in suites:
		print("[%s] Passed: %d, Failed: %d" % [suite["name"], suite["passed"], suite["failed"]])
		total_passed += suite["passed"]
		total_failed += suite["failed"]
		if suite["failed"] > 0:
			all_passed = false
			for err in suite["errors"]:
				print("   - FAIL: %s" % err)
				
	print("\n------------------------------------------")
	print("SUMMARY: %d passed, %d failed" % [total_passed, total_failed])
	print("------------------------------------------")
	
	if all_passed:
		print(">> ALL TESTS PASSED SUCCESSFULLY! <<\n")
		get_tree().quit(0)
	else:
		print(">> SOME TESTS FAILED! <<\n")
		get_tree().quit(1)

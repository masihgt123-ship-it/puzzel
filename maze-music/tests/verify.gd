extends SceneTree

var failures := 0
var checks := 0
var game
var music
const DIRS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

func _initialize() -> void:
	call_deferred("run_tests")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func direction_between(a: Vector2i, b: Vector2i) -> int:
	return DIRS.find(b - a)

func walk(route: Array, tick: float = 0.0) -> void:
	for i in range(1, route.size()):
		var before: Vector2i = game.player
		var d := direction_between(before, route[i])
		check(d >= 0, "Non-adjacent route step")
		if d < 0:
			return
		check(not game.walls[game.index(before)][d], "Route crosses a wall")
		game.step(d)
		check(game.player == route[i], "Unexpected collision/reset on solution route, stage %d" % game.level)
		if game.player != route[i]:
			return
		if tick > 0 and not game.won:
			game.elapsed += tick
			game.update_hunter(tick)
			check(game.player == route[i], "Hunter caught solution walker at stage %d, tick %.2f" % [game.level, tick])
			if game.player != route[i]:
				return

func run_tests() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_process_input(false)
	for child in game.get_children():
		if child is AudioStreamPlayer and child.get_script() != null:
			music = child
			music.set_process(false)
	check(game.level == 1, "New session must start at stage 1")
	check(not game.status.visible, "Top status should be hidden")
	check(not game.title.visible, "Top game title should be hidden")
	var previous_interval := 99.0
	var summary: Array = []
	for stage in range(1, 51):
		game.level = stage
		game.generate()
		var expected_stars := 2 if stage >= 5 else 0
		check(game.star_positions.size() == expected_stars, "Wrong star count at %d" % stage)
		check(game.collected_stars.is_empty(), "Collection state leaked across stages")
		check(game.exit_open() == (stage < 5), "Wrong initial exit state")
		# Full flood fill: all cells reachable; every open edge is in bounds and symmetric.
		var queue: Array[Vector2i] = [Vector2i.ZERO]
		var seen := {Vector2i.ZERO: true}
		var head := 0
		while head < queue.size():
			var p: Vector2i = queue[head]
			head += 1
			for d in range(4):
				if not game.walls[game.index(p)][d]:
					var n: Vector2i = p + DIRS[d]
					check(game.inside(n), "Open boundary wall")
					if not game.inside(n):
						continue
					check(not game.walls[game.index(n)][(d + 2) % 4], "Asymmetric wall")
					if not seen.has(n):
						seen[n] = true
						queue.append(n)
		check(seen.size() == game.side * game.side, "Disconnected maze at %d" % stage)
		var goal := Vector2i(game.side - 1, game.side - 1)
		var route: Array = game.path_between(Vector2i.ZERO, goal)
		check(not route.is_empty(), "No solution at %d" % stage)
		var last_star_index := 0
		for p in game.star_positions:
			check(p != Vector2i.ZERO and p != goal, "Star on start or exit")
			check(route.find(p) > last_star_index, "Stars not distinct and ordered on safe route")
			last_star_index = route.find(p)
		check(game.next_target() == (game.star_positions[0] if stage >= 5 else goal), "Wrong hint target")
		game.show_hint()
		check(game.hint_path[0] == game.player and game.hint_path.back() == game.next_target(), "Hint is not a valid objective route")
		game.restart()
		game.advance()
		check(game.level == stage, "Premature advance allowed")
		for d in range(4):
			if game.walls[game.index(game.player)][d]:
				var before: Vector2i = game.player
				game.step(d)
				check(game.player == before and game.moves == 0, "Movement through closed wall")
		# Drive actual gameplay one objective at a time, checking that one star is insufficient.
		if stage >= 5:
			walk(game.path_between(game.player, game.star_positions[0]))
			check(game.collected_stars.size() == 1 and not game.exit_open() and not game.won, "One star incorrectly unlocked exit")
			check(game.next_target() == game.star_positions[1], "Hint failed to switch to second star")
			walk(game.path_between(game.player, game.star_positions[1]))
			check(game.collected_stars.size() == 2 and game.exit_open(), "Two stars did not unlock exit")
			check(game.next_target() == goal, "Hint should point to exit after both stars")
		walk(game.path_between(game.player, goal))
		check(game.won, "Cannot complete stage %d" % stage)
		check(game.next_button.disabled == (stage == 50), "Wrong next-button state")
		if stage < 50:
			game.advance()
			check(game.level == stage + 1 and not game.won, "Advance failed")
		else:
			game.advance()
			check(game.level == 50, "Advanced beyond 50")
		game.level = stage
		game.generate()
		var stars_copy: Array = game.star_positions.duplicate()
		var walls_copy: Array = game.walls.duplicate(true)
		game.generate()
		check(game.star_positions == stars_copy and game.walls == walls_copy, "Stage generation is not stable")
		# Force entry to exit while stars are missing, independently of star placement.
		if stage >= 5:
			game.player = route[route.size() - 2]
			game.step(direction_between(game.player, goal))
			check(not game.won and game.next_button.disabled, "Locked exit permitted completion")
			game.collected_stars[game.star_positions[0]] = true
			game.player = route[route.size() - 2]
			game.step(direction_between(game.player, goal))
			check(not game.won, "Exit permitted completion with one star")
			game.restart()
			check(game.collected_stars.is_empty() and not game.exit_open(), "Restart did not reset stars/exit")
		# Actual hunter update at two fixed input rates, without bypassing collision logic.
		for tick in [0.30, 0.40]:
			game.restart()
			walk(route, tick)
			check(game.won, "Timed completion failed at stage %d with %.2fs moves" % [stage, tick])
		if stage >= 7:
			check(game.hunter_interval() <= previous_interval, "Difficulty decreased")
			previous_interval = game.hunter_interval()
			game.restart()
			game.elapsed = 4.9
			game.update_hunter(4.9)
			check(not game.hunter_active, "Hunter activated before grace period")
			# A hunter touching an idle player at spawn causes a proper restart.
			game.elapsed = 5.0
			game.update_hunter(0.1)
			check(game.elapsed == 0.0 and not game.hunter_active and game.collected_stars.is_empty(), "Caught/reset failed")
			# Walking into an already active hunter is a collision as well.
			game.restart()
			game.hunter_active = true
			game.hunter = route[1]
			game.step(direction_between(game.player, route[1]))
			check(game.player == Vector2i.ZERO and not game.hunter_active, "Player-to-hunter collision failed")
		else:
			game.restart()
			game.elapsed = 100.0
			game.update_hunter(100.0)
			check(not game.hunter_active, "Hunter appeared before stage 7")
		music.update_track()
		check(music.track_index == (stage - 1) % 12, "Wrong music at stage %d" % stage)
		check(music.stream != null and music.playing, "Music failed to start")
		check(music.stream.resource_path == "res://music/track_%02d.mp3" % ((stage - 1) % 12 + 1), "Wrong music resource")
		summary.append({"stage": stage, "cells": game.side * game.side, "solution_moves": route.size() - 1, "stars": expected_stars, "hunter_interval": game.hunter_interval() if stage >= 7 else 0.0})
	# Same-stage updates should retain the current track; finish handler must replay it.
	var stream_before = music.stream
	music.update_track()
	check(music.stream == stream_before, "Same-stage update replaced track")
	music.stop()
	music.finished.emit()
	check(music.playing, "Track end did not restart playback")
	var output := FileAccess.open("res://tests/results.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"engine": Engine.get_version_info().string, "checks": checks, "failures": failures, "levels": summary}, "\t"))
	output.close()
	print("MAZE_TEST_RESULT checks=%d failures=%d levels=50 timed_runs=100" % [checks, failures])
	music.stop()
	game.star_sound.stop()
	stream_before = null
	await create_timer(0.15).timeout
	game.queue_free()
	await process_frame
	music = null
	game = null
	await create_timer(0.15).timeout
	quit(0 if failures == 0 else 1)

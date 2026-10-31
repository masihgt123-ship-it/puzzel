extends Control

const DIRS = [Vector2i(0,-1), Vector2i(1,0), Vector2i(0,1), Vector2i(-1,0)]
const MAX_LEVEL := 50
var accent := Color.CYAN
var backdrop := Color.BLACK
var board_color := Color.BLACK
var rng := RandomNumberGenerator.new()
var level := 1
var side := 7
var walls: Array = []
var player := Vector2i.ZERO
var visited := {}
var hint_path: Array = []
var moves := 0
var elapsed := 0.0
var won := false
var origin := Vector2(45, 250)
var cell := 80.0
var touch_start := Vector2.ZERO
var status: Label
var title: Label
var notice: Label
var next_button: Button
var hint_button: Button
var help_left := 3
var trail: Array[Vector2i] = []
var hunter := Vector2i.ZERO
var hunter_index := 0
var hunter_active := false
var hunter_clock := 0.0
const HUNTER_DELAY := 5.0
var star_positions: Array[Vector2i] = []
var collected_stars: Dictionary = {}
var star_flash := 0.0
var star_flash_position := Vector2i.ZERO
var star_sound: AudioStreamPlayer

func _ready() -> void:
	rng.randomize()
	var theme_res := Theme.new()
	theme_res.default_font = load("res://fonts/DejaVuSans.ttf")
	theme_res.default_font_size = 25
	theme = theme_res
	# Always begin a new session at stage 1, ignoring older saved progress.
	level = 1
	title = make_label("هزارتوی نور", Vector2(30,40), Vector2(660,65), 42)
	title.hide() # Keep the entire top HUD, including the game title, hidden.
	status = make_label("", Vector2(20,120), Vector2(680,70), 24)
	status.hide() # Hide the stage, move count and timer HUD.
	notice = make_label("با کشیدن انگشت یا دکمه‌ها حرکت کن", Vector2(20,865), Vector2(680,60), 23)
	make_button("↑", Vector2(290,940), Vector2(140,85), func(): step(0))
	make_button("←", Vector2(130,1035), Vector2(140,85), func(): step(3))
	make_button("↓", Vector2(290,1035), Vector2(140,85), func(): step(2))
	make_button("→", Vector2(450,1035), Vector2(140,85), func(): step(1))
	hint_button = make_button("راهنما", Vector2(40,1160), Vector2(190,70), show_hint)
	make_button("شروع دوباره", Vector2(245,1160), Vector2(230,70), restart)
	next_button = make_button("مرحله بعد", Vector2(490,1160), Vector2(190,70), advance)
	star_sound = AudioStreamPlayer.new()
	star_sound.stream = load("res://sounds/star.wav")
	star_sound.volume_db = -10.0
	add_child(star_sound)
	generate()
	var stage_music := AudioStreamPlayer.new()
	stage_music.set_script(load("res://stage_music.gd"))
	add_child(stage_music)

func make_label(text_value: String, pos: Vector2, dimensions: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.text = text_value
	label.position = pos
	label.size = dimensions
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	add_child(label)
	return label

func make_button(text_value: String, pos: Vector2, dimensions: Vector2, action: Callable) -> Button:
	var button := Button.new()
	button.text = text_value
	button.position = pos
	button.size = dimensions
	button.pressed.connect(action)
	add_child(button)
	return button

func index(p: Vector2i) -> int:
	return p.y * side + p.x

func inside(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < side and p.y < side

func generate() -> void:
	# Stable layouts: returning to a stage preserves its maze.
	rng.seed = 731927 + level * 104729
	side = mini(7 + 2 * int((level - 1) / 5.0), 19)
	var hue := fposmod(0.52 + (level - 1) * 0.071, 1.0)
	accent = Color.from_hsv(hue, 0.55, 0.95)
	backdrop = Color.from_hsv(hue, 0.65, 0.09)
	board_color = Color.from_hsv(hue, 0.60, 0.15)
	apply_palette()
	cell = 630.0 / side
	walls.clear()
	for i in range(side * side):
		walls.append([true,true,true,true])
	var stack: Array[Vector2i] = [Vector2i.ZERO]
	var carved := {Vector2i.ZERO: true}
	while not stack.is_empty():
		var current: Vector2i = stack.back()
		var options: Array[int] = []
		for d in range(4):
			var neighbor: Vector2i = current + DIRS[d]
			if inside(neighbor) and not carved.has(neighbor):
				options.append(d)
		if options.is_empty():
			stack.pop_back()
		else:
			var d: int = options[rng.randi_range(0, options.size()-1)]
			var neighbor: Vector2i = current + DIRS[d]
			walls[index(current)][d] = false
			walls[index(neighbor)][(d+2)%4] = false
			carved[neighbor] = true
			stack.append(neighbor)
	place_stars()
	restart()

func path_between(start: Vector2i, target: Vector2i) -> Array[Vector2i]:
	var queue: Array[Vector2i] = [start]
	var parents := {start: start}
	var head := 0
	while head < queue.size():
		var p: Vector2i = queue[head]
		head += 1
		if p == target:
			break
		for d in range(4):
			var n: Vector2i = p + DIRS[d]
			if inside(n) and not walls[index(p)][d] and not parents.has(n):
				parents[n] = p
				queue.append(n)
	var path: Array[Vector2i] = []
	if not parents.has(target):
		return path
	var cursor := target
	while cursor != start:
		path.append(cursor)
		cursor = parents[cursor]
	path.append(start)
	path.reverse()
	return path

func place_stars() -> void:
	star_positions.clear()
	if level < 5:
		return
	# Put both stars on the solution route, not in dead ends behind the hunter.
	var route := path_between(Vector2i.ZERO, Vector2i(side - 1, side - 1))
	assert(route.size() >= 4, "Maze has no valid route for two stars")
	star_positions.append(route[int((route.size() - 1) / 3.0)])
	star_positions.append(route[int(2 * (route.size() - 1) / 3.0)])

func exit_open() -> bool:
	return collected_stars.size() == star_positions.size()

func next_target() -> Vector2i:
	# Follow the safe start-to-exit order; collecting either star first is allowed.
	for p in star_positions:
		if not collected_stars.has(p):
			return p
	return Vector2i(side - 1, side - 1)

func hunter_interval() -> float:
	# Continuous, predictable difficulty increase from stage 7 to stage 50.
	return maxf(0.44, 0.80 - (level - 7) * 0.008)

func restart() -> void:
	player = Vector2i.ZERO
	visited = {player: true}
	hint_path.clear()
	moves = 0
	elapsed = 0
	won = false
	help_left = 3
	collected_stars.clear()
	star_flash = 0.0
	if is_instance_valid(star_sound):
		star_sound.stop()
	trail = [player]
	hunter = player
	hunter_index = 0
	hunter_active = false
	hunter_clock = 0.0
	next_button.disabled = true
	hint_button.disabled = false
	notice.text = "نقطه روشن را به حلقه سبز برسان"
	if level >= 5:
		notice.text = "هر دو ستاره را بگیر تا خروج باز شود"
	if level >= 7:
		notice.text = "دو ستاره را بگیر؛ سایه پس از ۵ ثانیه وارد می‌شود"
	queue_redraw()

func advance() -> void:
	if not won or level >= MAX_LEVEL:
		return
	level += 1
	generate()

func _process(delta: float) -> void:
	if star_flash > 0.0:
		star_flash = maxf(0.0, star_flash - delta)
		queue_redraw()
	if not won:
		elapsed += delta
		update_hunter(delta)
	status.text = "مرحله %d از ۵۰  |  حرکت %d  |  زمان %d ثانیه" % [level,moves,int(elapsed)]

func step(d: int) -> void:
	if won or walls[index(player)][d]:
		return
	player += DIRS[d]
	trail.append(player)
	if hunter_active and player == hunter:
		caught()
		return
	visited[player] = true
	moves += 1
	hint_path.clear()
	if player in star_positions and not collected_stars.has(player):
		collected_stars[player] = true
		star_flash = 0.45
		star_flash_position = player
		star_sound.play()
		notice.text = "یک ستاره ماند؛ ستارهٔ دوم را پیدا کن"
		if exit_open():
			notice.text = "هر دو ستاره را گرفتی؛ خروج سبز باز شد"
	if player == Vector2i(side-1,side-1) and not exit_open():
		notice.text = "خروج قفل است؛ اول هر دو ستاره را بگیر"
	if player == Vector2i(side-1,side-1) and exit_open():
		won = true
		next_button.disabled = level >= MAX_LEVEL
		hint_button.disabled = true
		if level == MAX_LEVEL:
			notice.text = "تبریک! هر ۵۰ مرحله را تمام کردی!"
		else:
			notice.text = "آفرین! خروج را پیدا کردی؛ مرحله بعد آماده است"
	queue_redraw()

func update_hunter(delta: float) -> void:
	if level < 7 or elapsed < HUNTER_DELAY:
		return
	if not hunter_active:
		hunter_active = true
		hunter = trail[0]
		hunter_clock = 0.0
		notice.text = "سایه وارد شد! توقف نکن"
		queue_redraw()
		if hunter == player:
			caught()
		return
	hunter_clock += delta
	# One tile per beat, never skipping corners, including the player's backtracking.
	var interval := hunter_interval()
	while hunter_clock >= interval:
		hunter_clock -= interval
		if hunter_index + 1 < trail.size():
			hunter_index += 1
			hunter = trail[hunter_index]
			queue_redraw()
		if hunter == player:
			caught()
			return

func caught() -> void:
	restart()
	notice.text = "سایه گرفتت! دوباره فرار کن؛ ۵ ثانیه فرصت داری"

func show_hint() -> void:
	if won or help_left <= 0:
		return
	help_left -= 1
	var target := next_target()
	hint_path = path_between(player, target)
	hint_button.disabled = help_left <= 0
	if exit_open():
		notice.text = "مسیر طلایی راه خروج است؛ راهنمای باقی‌مانده: %d" % help_left
	else:
		notice.text = "مسیر طلایی راه ستاره است؛ راهنمای باقی‌مانده: %d" % help_left
	queue_redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_UP, KEY_W: step(0)
			KEY_RIGHT, KEY_D: step(1)
			KEY_DOWN, KEY_S: step(2)
			KEY_LEFT, KEY_A: step(3)
	if event is InputEventScreenTouch:
		if event.pressed:
			touch_start = event.position
		elif touch_start.y >= 230 and touch_start.y < 890:
			swipe(event.position - touch_start)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			touch_start = event.position
		elif touch_start.y >= 230 and touch_start.y < 890:
			swipe(event.position - touch_start)

func swipe(diff: Vector2) -> void:
	if diff.length() < 25:
		return
	if absf(diff.x) > absf(diff.y):
		step(1 if diff.x > 0 else 3)
	else:
		step(2 if diff.y > 0 else 0)

func center(p: Vector2i) -> Vector2:
	return origin + (Vector2(p) + Vector2(0.5,0.5)) * cell

func apply_palette() -> void:
	for child in get_children():
		if child is Button:
			for state in ["normal", "hover", "pressed", "disabled"]:
				var style := StyleBoxFlat.new()
				style.bg_color = accent.darkened(0.78 if state == "disabled" else 0.58)
				if state == "pressed":
					style.bg_color = accent.darkened(0.30)
				style.set_corner_radius_all(18)
				style.set_border_width_all(2)
				style.border_color = accent.darkened(0.55 if state == "disabled" else 0.1)
				child.add_theme_stylebox_override(state, style)
	title.add_theme_color_override("font_color", accent)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), backdrop)
	# Decorative stars change position and shape across stages.
	for i in range(32):
		var point := Vector2(fposmod(i * 173.0 + level * 29, 720), fposmod(i * 277.0 + level * 41, 1280))
		var tint := Color(accent, 0.15)
		if level % 2 == 0:
			draw_arc(point, 4 + i % 4, 0, TAU, 12, tint, 1.0, true)
		else:
			draw_circle(point, 2 + i % 3, tint)
	draw_style_box(panel_style(), Rect2(25,230,670,670))
	if walls.is_empty():
		return
	for p in visited:
		draw_circle(center(p), cell * 0.1, accent.darkened(0.65))
	for y in range(side):
		for x in range(side):
			var p := Vector2i(x,y)
			var a := origin + Vector2(p) * cell
			var w: Array = walls[index(p)]
			var color := accent
			if w[0]: draw_line(a,a+Vector2(cell,0),color,3,true)
			if w[3]: draw_line(a,a+Vector2(0,cell),color,3,true)
			if y == side-1 and w[2]: draw_line(a+Vector2(0,cell),a+Vector2(cell,cell),color,3,true)
			if x == side-1 and w[1]: draw_line(a+Vector2(cell,0),a+Vector2(cell,cell),color,3,true)
	for i in range(hint_path.size()-1):
		draw_line(center(hint_path[i]),center(hint_path[i+1]),Color(1,0.75,0.22,0.8),4,true)
	if hunter_active:
		var h := center(hunter)
		var radius := cell * 0.30
		draw_circle(h, radius, Color(1.0, 0.22, 0.36))
		draw_rect(Rect2(h + Vector2(-radius, 0), Vector2(radius * 2, radius)), Color(1.0, 0.22, 0.36))
		for eye in [-1, 1]:
			var e := h + Vector2(eye * radius * 0.38, -radius * 0.15)
			draw_circle(e, radius * 0.26, Color.WHITE)
			draw_circle(e + Vector2(0, radius * 0.05), radius * 0.12, Color(0.08, 0.05, 0.15))
	for p in star_positions:
		if not collected_stars.has(p):
			draw_star(center(p), cell * 0.28)
	if star_flash > 0.0:
		var progress := 1.0 - star_flash / 0.45
		draw_arc(center(star_flash_position), cell * (0.3 + progress * 0.65), 0, TAU, 32, Color(1.0, 0.8, 0.2, 1.0 - progress), 3.0, true)
	var goal := center(Vector2i(side-1,side-1))
	var goal_color := Color(0.25, 1.0, 0.65) if exit_open() else Color(1.0, 0.38, 0.2)
	draw_circle(goal, cell * 0.3, Color(goal_color, 0.25))
	draw_arc(goal, cell * 0.3, 0, TAU, 32, goal_color, 3, true)
	if not exit_open():
		draw_line(goal - Vector2.ONE * cell * 0.15, goal + Vector2.ONE * cell * 0.15, goal_color, 3, true)
		draw_line(goal + Vector2(-1, 1) * cell * 0.15, goal + Vector2(1, -1) * cell * 0.15, goal_color, 3, true)
	draw_circle(center(player),cell*0.29,Color(accent, 0.25))
	draw_circle(center(player),cell*0.19,accent.lightened(0.3))
	draw_circle(center(player)-Vector2(cell*0.05,cell*0.05),cell*0.06,Color.WHITE)

func draw_star(point: Vector2, radius: float) -> void:
	var points := PackedVector2Array()
	for i in range(10):
		var angle := -PI / 2.0 + i * PI / 5.0
		var length := radius if i % 2 == 0 else radius * 0.43
		points.append(point + Vector2(cos(angle), sin(angle)) * length)
	draw_circle(point, radius * 1.25, Color(1.0, 0.76, 0.14, 0.15))
	draw_colored_polygon(points, Color(1.0, 0.82, 0.18))
	points.append(points[0])
	draw_polyline(points, Color(1.0, 0.96, 0.65), 1.5, true)

func panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = board_color
	style.corner_radius_top_left = 20
	style.corner_radius_top_right = 20
	style.corner_radius_bottom_left = 20
	style.corner_radius_bottom_right = 20
	return style

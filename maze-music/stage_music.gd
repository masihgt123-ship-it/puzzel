extends AudioStreamPlayer

var track_index := -1

func _ready() -> void:
	volume_db = -12.0
	finished.connect(play)
	update_track()

func _process(_delta: float) -> void:
	update_track()

func update_track() -> void:
	var stage: int = int(get_parent().get("level"))
	# All 12 full tracks cycle in order, changing at every new stage.
	var next_index: int = (maxi(stage, 1) - 1) % 12
	if next_index == track_index:
		return
	track_index = next_index
	stream = load("res://music/track_%02d.mp3" % (track_index + 1))
	play()

func _exit_tree() -> void:
	stop()
	stream = null

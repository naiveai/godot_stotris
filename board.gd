tool
extends Node2D

signal pause
signal game_over

enum GameState {RUNNING, COMPLETED_LINES, OVER, STOPPED}

const FallingTile = preload("res://falling_tile.tscn")

const START_BLOCK_TIME = 1
const BLOCK_ACCEL = 0.1
const LINES_PER_LEVEL = 10

const MOVE_TIME = 0.2

const BORDER_TILE_NAME = "grey"
const COMPLETED_TILE_NAME = "white"

const BLOCKS_PER_QUEUE = 7

var _block_types = [
	preload("res://blocks/i.tscn"),
	preload("res://blocks/j.tscn"),
	preload("res://blocks/l.tscn"),
	preload("res://blocks/o.tscn"),
	preload("res://blocks/s.tscn"),
	preload("res://blocks/t.tscn"),
	preload("res://blocks/z.tscn")
]

export(Vector2) var board_size = Vector2(20, 29) setget _set_size

var stock_info = [
	"[center][b]META[/b][/center]",
	"[center]$96.47[/center]",
	"[center][color=red]v -0.25 (0.26%)[/color][/center]",
	"[center]Tech[/center]"
]

var _current_stock_info = 0

var _block_queue

var _block

var _max_block_time
var _block_time
var _grace

var _lines_left

var _move_time

var _completed_lines

var _game_state

func _ready():
	_game_state = GameState.STOPPED
	_completed_lines = []

	$monthly_timer.connect("timeout", self, "_on_monthly_timeout")
	$annual_timer.connect("timeout", self, "_on_annual_timeout")

	$chart.initialize($chart.LABELS_TO_SHOW.NO_LABEL, {
	   depenses = Color(1.0, 0.18, 0.18),
	   recettes = Color(0.58, 0.92, 0.07),
	   interet = Color(0.5, 0.22, 0.6)
	})

	$chart.create_new_point({
							label = 'JANVIER',
							values = {
							depenses = 150,
							recettes = 1025,
							interet = 1050
							}
							})

	$chart.create_new_point({
							label = 'FEVRIER',
							values = {
							depenses = 500,
							recettes = 1020,
							interet = -150
							}
							})

	$chart.create_new_point({
							label = 'MARS',
							values = {
							depenses = 10,
							recettes = 1575,
							interet = -450
							}
							})

	$chart.create_new_point({
							label = 'AVRIL',
							values = {
							depenses = 350,
							recettes = 750,
							interet = -509
							}
							})

	$chart.create_new_point({
							label = 'MAI',
							values = {
							depenses = 1350,
							recettes = 750,
							interet = -505
							}
							})

	$chart.create_new_point({
							label = 'JUIN',
							values = {
							depenses = 350,
							recettes = 1750,
							interet = -950
							}
							})

	$chart.create_new_point({
							label = 'JUILLET',
							values = {
							depenses = 100,
							recettes = 1500,
							interet = -350
							}
							})

	$chart.create_new_point({
							label = 'AOUT',
							values = {
							depenses = 350,
							recettes = 750,
							interet = -500
							}
							})

	$chart.create_new_point({
							label = 'SEPTEMBRE',
							values = {
							depenses = 1350,
							recettes = 750,
							interet = -50
							}
							})

	$chart.create_new_point({
							label = 'OCTOBRE',
							values = {
							depenses = 350,
							recettes = 1750,
							interet = -750
							}
							})

	$chart.create_new_point({
							label = 'NOVEMBRE',
							values = {
							depenses = 450,
							recettes = 200,
							interet = -150
							}
							})

	$chart.create_new_point({
							label = 'DECEMBRE',
							values = {
							depenses = 1350,
							recettes = 500,
							interet = -500
							}
							})

func _on_monthly_timeout():
	if _game_state == GameState.RUNNING:
		print("Month passed")
		_check_for_completed_lines(Buckets.MONTHLY)

func _on_annual_timeout():
	if _game_state == GameState.RUNNING:
		print("Year passed")
		_check_for_completed_lines(Buckets.ANNUALLY)

func _set_size(value):
	board_size = value

	if get_child_count() > 0:
		$board_tiles.clear()

		var border_tile = $board_tiles.tile_set.find_tile_by_name(
				BORDER_TILE_NAME)
		assert(border_tile != null)

		# Top and bottom
		for x in range(board_size.x + 2):
			$board_tiles.set_cell(x, 0, border_tile)
			$board_tiles.set_cell(x, board_size.y + 1, border_tile)

		# Left and right
		for y in range(1, board_size.y + 1):
			$board_tiles.set_cell(0, y, border_tile)
			$board_tiles.set_cell(board_size.x + 1, y, border_tile)

func start_game():
	randomize()

	_game_state = GameState.RUNNING

	_block_queue = []
	_generate_block_queue()

	_block = null

	_max_block_time = START_BLOCK_TIME
	_lines_left = LINES_PER_LEVEL

	_block_time = START_BLOCK_TIME
	_grace = false

	_move_time = MOVE_TIME

	_spawn_block()

func _input(event):
	if not Engine.editor_hint and (_game_state == GameState.RUNNING):
		if event.is_action_pressed("cancel"):
			get_tree().set_input_as_handled()
			emit_signal("pause")
		elif _block:
			if event.is_action_pressed("drop"):
				_drop_block_fast()
			else:
				var move_left = event.is_action_pressed("move_left")
				var move_right = event.is_action_pressed("move_right")
				var move_down = event.is_action_pressed("move_down")

				_control_block(
						move_left,
						move_right,
						move_down,
						event.is_action_pressed("rotate_ccw"),
						event.is_action_pressed("rotate_cw")
						)

				if move_left or move_right or move_down:
					_move_time += MOVE_TIME
				if move_down:
					_block_time += _max_block_time

func _process(delta):
	if not Engine.editor_hint and (_game_state != GameState.STOPPED):
		if _game_state == GameState.RUNNING:
			var block_dropped = false

			_block_time -= delta
			if _block_time <= 0:
				if _block:
					_drop_block()
					block_dropped = true
				else:
					_spawn_block()
				_block_time += _max_block_time

			if _block:
				_move_time -= delta

				var can_move = _move_time <= 0

				var move_left = Input.is_action_pressed("move_left") \
						and can_move
				var move_right = Input.is_action_pressed("move_right") \
						and can_move
				# Don't drop block manually if it's already falling fast enough
				# naturally.
				var move_down = Input.is_action_pressed("move_down") \
						and can_move and (_max_block_time > MOVE_TIME) \
						and not block_dropped

				_control_block(move_left, move_right, move_down, false, false)

				if can_move:
					_move_time += MOVE_TIME
		elif _game_state == GameState.OVER:
			if $falling_tiles.get_child_count() == 0:
				end_game()

func _control_block(move_left, move_right, move_down, rotate_ccw, rotate_cw):
	var move = Vector2()
	var rotate = 0

	if move_left:
		move.x -= 1
	if move_right:
		move.x += 1
	if move_down:
		move.y += 1

	if rotate_ccw:
		rotate -= 1
		_current_stock_info -= 1
		if _current_stock_info < 0:
			_current_stock_info = stock_info.size() - 1
	if rotate_cw:
		rotate += 1
		_current_stock_info += 1
		if _current_stock_info >= stock_info.size():
			_current_stock_info = 0

	$stock_info_label.bbcode_text = stock_info[_current_stock_info]
	_move_block(move, rotate)

func _spawn_block():
	if _block_queue.empty():
		_generate_block_queue()

	var index = randi() % _block_queue.size()
	_block = _block_queue[index].instance()
	_block_queue.remove(index)
	add_child(_block)

	var block_rect = _block.get_rect()

	var board_middle = int(board_size.x / 2)
	var block_middle = int(block_rect.size.x / 2)

	var block_pos = Vector2(board_middle - block_middle + 1, 1)
	_block.block_position = block_pos

	$stock_info_label.bbcode_text = stock_info[_current_stock_info]

	if not _is_block_space_empty(block_pos, 0):
		_set_game_over()

func _generate_block_queue():
	for b in _block_types:
		#warning-ignore:unused_variable
		for i in range(BLOCKS_PER_QUEUE):
			_block_queue.append(b)

func _drop_block():
	_move_block(Vector2(0, 1), 0)

	if not _is_block_space_empty(_block.block_position + Vector2(0, 1),
			_block.block_rotation):
		if _grace:
			_end_block()
			_grace = false
			_block_time = 0
		else:
			_grace = true
			_block_time -= _max_block_time / 2.0

func _drop_block_fast():
	while _block:
		_drop_block()

func _move_block(pos, rot):
	var new_pos = _block.block_position + pos
	var new_rot = _block.block_rotation + rot

	if _is_block_space_empty(new_pos, new_rot):
		_block.block_position = new_pos
		_block.block_rotation = new_rot

func _is_block_space_empty(pos, rot):
	var result = true
	for t in _block.get_tiles(pos, rot):
		if $board_tiles.get_cellv(t) != -1:
			result = false
			break
	return result

func _end_block():
	var tiles = _block.get_tiles()
	for t in tiles:
		$board_tiles.set_cellv(t + _block.block_position,
				_block.get_tile_type(t))

	_block.queue_free()
	_block = null

	if _game_state == GameState.RUNNING:
		_check_for_completed_lines(Buckets.DAILY)

enum Buckets {
	DAILY = 1,
	MONTHLY = 8,
	ANNUALLY = 15,
}

const BUCKET_SIZE = 6

func _check_for_completed_lines(bucket):
	for y in range(29, 20, -1):
		var complete = true
		for x in range(bucket, bucket + BUCKET_SIZE):
			if $board_tiles.get_cell(x, y) == -1:
				complete = false
				break
		if complete:
			_completed_lines.append([bucket, y])

	_lines_left -= _completed_lines.size()
	while _lines_left <= 0:
		_lines_left += LINES_PER_LEVEL
		_max_block_time -= BLOCK_ACCEL
		_max_block_time = max(_max_block_time, MOVE_TIME)

	if not _completed_lines.empty():
		_show_completed_lines()

func _show_completed_lines():
	_game_state = GameState.COMPLETED_LINES

	var completed_tile = $completed_lines.tile_set.find_tile_by_name(
			COMPLETED_TILE_NAME)
	assert(completed_tile != null)

	for line_info in _completed_lines:
		var bucket = line_info[0]
		var y = line_info[1]

		for x in range(bucket, bucket + BUCKET_SIZE):
			$completed_lines.set_cell(x, y, completed_tile)
	$completed_animation.play("completed")

func _on_completed_animation_animation_finished( anim_name ):
	assert(anim_name == "completed")

	$completed_lines.clear()

	while not _completed_lines.empty():
		var line_info = _completed_lines.pop_front()
		var bucket = line_info[0]
		var current_y = line_info[1]

		for i in range(_completed_lines.size()):
			_completed_lines[i][1] += 1

		for x in range(bucket, bucket + BUCKET_SIZE):
			for y in range(current_y, 0, -1):
				if y - 1 > 0:
					var tile_above = $board_tiles.get_cell(x, y - 1)
					$board_tiles.set_cell(x, y, tile_above)
				else:
					$board_tiles.set_cell(x, y, -1)

	_game_state = GameState.RUNNING

func _set_game_over():
	_end_block()
	_game_state = GameState.OVER
	_spawn_falling_blocks()

func _spawn_falling_blocks():
	for x in range(1, board_size.x + 1):
		for y in range(1, board_size.y + 1):
			if $board_tiles.get_cell(x, y) != -1:
				var tile = FallingTile.instance()
				tile.set_tile($board_tiles, Vector2(x, y))
				$falling_tiles.add_child(tile)

				$board_tiles.set_cell(x, y, -1)

func end_game():
	if _block != null:
		_end_block()
	for x in range(1, board_size.x + 1):
		for y in range(1, board_size.y + 1):
			$board_tiles.set_cell(x, y, -1)
	_game_state = GameState.STOPPED
	emit_signal("game_over")

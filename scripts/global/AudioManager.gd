class_name AudioManager
extends Node

const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"

@export var menu_music: AudioStream
@export var battle_music: AudioStream
@export var unit_shoot_sfx: AudioStream
@export var explosion_sfx: AudioStream
@export var structure_death_sfx: AudioStream
@export var victory_sfx: AudioStream

var _music_player: AudioStreamPlayer
var _ui_sfx_player: AudioStreamPlayer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_music_player = AudioStreamPlayer.new()
	_music_player.bus = BUS_MUSIC
	_music_player.max_polyphony = 1
	add_child(_music_player)

	_ui_sfx_player = AudioStreamPlayer.new()
	_ui_sfx_player.bus = BUS_SFX
	_ui_sfx_player.max_polyphony = 8
	add_child(_ui_sfx_player)

	_apply_default_bus_volumes()

func _apply_default_bus_volumes() -> void:
	var master_idx: int = AudioServer.get_bus_index("Master")
	var music_idx: int = AudioServer.get_bus_index("Music")
	var sfx_idx: int = AudioServer.get_bus_index("SFX")

	if master_idx != -1:
		AudioServer.set_bus_volume_db(master_idx, 0.0)

	if music_idx != -1:
		AudioServer.set_bus_volume_db(music_idx, -30.0)

	if sfx_idx != -1:
		AudioServer.set_bus_volume_db(sfx_idx, -10.0)

func play_menu_music() -> void:
	if menu_music == null:
		return
	if _music_player.stream == menu_music and _music_player.playing:
		return
	_music_player.stream = menu_music
	_music_player.play()

func play_battle_music() -> void:
	if battle_music == null:
		return
	if _music_player.stream == battle_music and _music_player.playing:
		return
	_music_player.stream = battle_music
	_music_player.play()

func stop_music() -> void:
	_music_player.stop()

func play_victory_sfx() -> void:
	if victory_sfx == null:
		return
	_ui_sfx_player.stream = victory_sfx
	_ui_sfx_player.play()

func play_world_sfx(stream: AudioStream, world_pos: Vector2, parent: Node) -> void:
	if stream == null or parent == null:
		return

	var p := AudioStreamPlayer2D.new()
	p.bus = BUS_SFX
	p.stream = stream
	p.global_position = world_pos
	p.finished.connect(p.queue_free)
	parent.add_child(p)
	p.play()

func play_unit_shoot(world_pos: Vector2, parent: Node) -> void:
	play_world_sfx(unit_shoot_sfx, world_pos, parent)

func play_explosion(world_pos: Vector2, parent: Node) -> void:
	play_world_sfx(explosion_sfx, world_pos, parent)

func play_structure_death(world_pos: Vector2, parent: Node) -> void:
	play_world_sfx(structure_death_sfx, world_pos, parent)

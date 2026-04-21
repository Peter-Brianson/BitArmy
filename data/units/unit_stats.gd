class_name UnitStats
extends Resource

const TYPE_BASIC := 1 << 0
const TYPE_MYSTIC := 1 << 1
const TYPE_BEAST := 1 << 2
const TYPE_MACHINE := 1 << 3
const TYPE_ALIEN := 1 << 4
const TYPE_ELEMENTAL := 1 << 5

# ...keep your existing enums/constants above or below as needed...

@export_category("Identity")
@export var unit_name: String = "Unit"
@export var description: String = ""

@export_category("Sprites")
@export var sprite_idle: Texture2D
@export var sprite_walk: Texture2D
@export var sprite_attack: Texture2D
@export var sprite_dead: Texture2D

@export_category("UI")
@export var icon_texture: Texture2D

@export_flags("Basic", "Mystic", "Beast", "Machine", "Alien", "Elemental")
var unit_type_tags: int = TYPE_BASIC

@export_category("Core")
@export var max_health: int = 1
@export var damage: int = 1
@export var move_speed: float = 50.0
@export var radius: float = 8.0
@export var body_size: Vector2 = Vector2(8, 16)
@export var build_time: float = 1.0
@export var cost: int = 10

# keep the rest of your existing fields and methods
enum DamageType {
	PHYSICAL,
	MAGICAL,
	SIEGE,
	TRUE
}

const KW_FLYING := 1
const KW_PHYSICAL_IMMUNITY := 2
const KW_MAGICAL_IMMUNITY := 4
const KW_ARMORED := 8
const KW_ANTI_AIR := 16
const KW_STRUCTURE := 32

const TARGET_UNITS := 1
const TARGET_STRUCTURES := 2

@export_category("Core Stats")
@export var attack_speed: float = 1.0
@export var attack_range: float = 18.0

@export_category("Combat")
@export var damage_type: DamageType = DamageType.PHYSICAL
@export_flags(
	"Flying:1",
	"Physical Immunity:2",
	"Magical Immunity:4",
	"Armored:8",
	"Anti Air:16",
	"Structure:32"
) var keywords: int = 0

@export_flags(
	"Units:1",
	"Structures:2"
) var target_categories: int = TARGET_UNITS

@export var aggro_range: float = 64.0

@export_category("Simulation")
@export var death_time: float = 0.25

@export_category("Presentation")
@export var body_color: Color = Color.WHITE
@export var attack_flash_color: Color = Color(1, 1, 1, 1)
@export var hit_flash_color: Color = Color(1, 1, 1, 1)

func get_attack_cooldown() -> float:
	return 1.0 / max(attack_speed, 0.001)

func has_keyword(flag: int) -> bool:
	return (keywords & flag) != 0

func can_target_units() -> bool:
	return (target_categories & TARGET_UNITS) != 0

func can_target_structures() -> bool:
	return (target_categories & TARGET_STRUCTURES) != 0

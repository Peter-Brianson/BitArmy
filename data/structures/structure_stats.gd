class_name StructureStats
extends Resource

@export_category("Identity")
@export var structure_name: String = "Structure"
@export var description: String = ""

@export_category("Sprites")
@export var sprite_normal: Texture2D
@export var sprite_destroyed: Texture2D

@export_category("UI")
@export var icon_texture: Texture2D

@export_category("Core")
@export var max_health: int = 10
@export var radius: float = 16.0
@export var footprint_size: Vector2 = Vector2(30, 30)
@export var death_time: float = 1.0
@export var cost: int = 10

@export_category("Production")
@export var can_produce: bool = false
@export var can_train_units: bool = false
@export var can_place_structures: bool = false
@export var trained_unit_stats: UnitStats
@export var spawn_offset: Vector2 = Vector2(0, 8)

@export_category("Team Bonuses")
@export var income_bonus_per_second: float = 0.0

@export_flags("Basic", "Mystic", "Beast", "Machine", "Alien", "Elemental")
var teamwide_buff_unit_tags: int = 0

@export var teamwide_bonus_damage: int = 0
@export var teamwide_bonus_health: int = 0

# keep any existing combat / keyword fields you already had

const KW_FLYING := 1
const KW_PHYSICAL_IMMUNITY := 2
const KW_MAGICAL_IMMUNITY := 4
const KW_ARMORED := 8
const KW_ANTI_AIR := 16
const KW_STRUCTURE := 32

const TARGET_UNITS := 1
const TARGET_STRUCTURES := 2

@export_category("Combat")
@export var can_attack: bool = false
@export var damage: int = 0
@export var attack_speed: float = 1.0
@export var attack_range: float = 0.0
@export_flags("Units:1", "Structures:2")
var target_categories: int = 0

@export_category("Combat2")
@export var attack_damage: int = 0
@export var attack_cooldown: float = 1.0
@export var attack_windup: float = 0.0


@export_category("Traits")
@export_flags(
	"Flying:1",
	"Physical Immunity:2",
	"Magical Immunity:4",
	"Armored:8",
	"Anti Air:16",
	"Structure:32"
)
var keywords: int = KW_STRUCTURE


func can_target_units() -> bool:
	return (target_categories & TARGET_UNITS) != 0

func can_target_structures() -> bool:
	return (target_categories & TARGET_STRUCTURES) != 0

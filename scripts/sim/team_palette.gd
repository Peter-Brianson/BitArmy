class_name TeamPalette
extends RefCounted

const COLORS: Array[Color] = [
	Color("#4A90E2"), # 0 blue
	Color("#E94E4E"), # 1 red
	Color("#50C878"), # 2 green
	Color("#F5A623"), # 3 orange
	Color("#9B59B6"), # 4 purple
	Color("#F8E71C"), # 5 yellow
	Color("#00BCD4"), # 6 cyan
	Color("#E91E63"), # 7 pink
	Color("#8D6E63"), # 8 brown
	Color("#B0BEC5")  # 9 gray
]

static func get_team_color(team_id: int) -> Color:
	if COLORS.is_empty():
		return Color.WHITE
	return COLORS[team_id % COLORS.size()]

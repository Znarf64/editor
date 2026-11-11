package editor

Draw_Command_Rect :: struct {
	rect:          Rect,
	color:         [4]f32,
	border_radius: f32,
	border_width:  f32,
	border_color:  [4]f32,
	shadow_width:  f32,
}

Draw_Command_Char :: struct #all_or_none {
	position: [2]f32,
	char:     rune,
	color:    [4]f32,
	font:     ^Font,
}

Draw_Shape :: enum {
	Sine_Wave,
}

Draw_Command_Shape :: struct #all_or_none {
	position:  [2]f32,
	color:     [4]f32,
	shape:     Draw_Shape,
	size:      [2]f32,
	thickness: f32,
}

Draw_Command_Clip :: distinct Rect

Draw_Command_Blur :: struct {
	rect:          Rect,
	radius:        f32,
	border_radius: f32,
}

DRAW_COMMAND_CLIP_DISABLE :: Draw_Command_Clip { min = min(f32), max = max(f32), }

Draw_Command :: union {
	Draw_Command_Rect,
	Draw_Command_Char,
	Draw_Command_Shape,
	Draw_Command_Clip,
	Draw_Command_Blur,
}

draw_rect :: proc(
	commands:     ^[dynamic]Draw_Command,
	position:      [2]f32,
	size:          [2]f32,
	color:         [4]f32,
	border_radius: f32    = 0,
	border_width:  f32    = 0,
	border_color:  [4]f32 = 0,
	shadow_width:  f32    = 0,
	blur_radius:   f32    = 0,
) {
	if size == 0 {
		return
	}
	rect := rect_from_min_max(position, position + size)
	if blur_radius != 0 {
		append(commands, Draw_Command_Blur {
			rect          = rect,
			radius        = blur_radius,
			border_radius = border_radius,
		})
	}
	append(commands, Draw_Command_Rect {
		rect          = rect,
		color         = color,
		border_radius = border_radius,
		border_width  = border_width,
		border_color  = border_color,
		shadow_width  = shadow_width,
	})
}

draw_sine_wave :: proc(
	commands:  ^[dynamic]Draw_Command,
	position:  [2]f32,
	size:      [2]f32,
	color:     [4]f32,
	thickness: f32,
) {
	append(commands, Draw_Command_Shape {
		shape     = .Sine_Wave,
		position  = position,
		size      = size,
		color     = color,
		thickness = thickness,
	})
}

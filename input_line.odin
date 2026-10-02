package editor

import unicode "core:unicode"
import utf8    "core:unicode/utf8"

Input_Line :: struct {
	buffer:      [dynamic]u8,
	default:     string,
	cursor:      int,
	cursor_anim: Animation(f32),
}

Input_Line_Result :: enum {
	None = 0,
	Submit,
	Exit,
	Change,

	Next,
	Prev,
}

input_line_set_text :: proc(input: ^Input_Line, text: string) {
	clear(&input.buffer)
	append(&input.buffer, text)
	input.cursor = len(input.buffer)
}

@(require_results)
input_line_handle_event :: proc(input: ^Input_Line, event: Event) -> Input_Line_Result {
	@(require_results)
	is_word :: proc(r: rune) -> bool {
		return r == '_' || unicode.is_letter(r) || unicode.is_number(r)
	}

	#partial switch e in event {
	case Event_Input_Key:
		if e.action == .Up {
			return .None
		}
		#partial switch e.key {
		case .Escape:
			clear(&input.buffer)
			input.cursor = 0
			return .Exit
		case .Enter:
			return .Submit
		case .Backspace:
			end := input.cursor

			r, w := utf8.decode_last_rune(input.buffer[:input.cursor])
			(w != 0) or_break
			input.cursor -= w

			if e.modifiers & { .Control, .Alt, } != {} {
				for !is_word(r) {
					r, w = utf8.decode_last_rune(input.buffer[:input.cursor])
					(w != 0) or_break
					input.cursor -= w
				}
				for {
					r, w = utf8.decode_last_rune(input.buffer[:input.cursor])
					(w != 0) or_break
					if is_word(r) {
						input.cursor -= w
					} else {
						break
					}
				}
			}

			remove_range(&input.buffer, input.cursor, end)

			return .Change
		case .Tab:
			if .Shift in e.modifiers {
				return .Prev
			} else {
				return .Next
			}
		case .Down:
			return .Next
		case .Up:
			return .Prev
		case .Left:
			r, w := utf8.decode_last_rune(input.buffer[:input.cursor])
			(w != 0) or_break
			input.cursor -= w

			if e.modifiers & { .Control, .Alt, } != {} {
				for !is_word(r) {
					r, w = utf8.decode_last_rune(input.buffer[:input.cursor])
					(w != 0) or_break
					input.cursor -= w
				}
				for {
					r, w = utf8.decode_last_rune(input.buffer[:input.cursor])
					(w != 0) or_break
					if is_word(r) {
						input.cursor -= w
					} else {
						break
					}
				}
			}
		case .Right:
			r, w := utf8.decode_rune(input.buffer[input.cursor:])
			(w != 0) or_break
			input.cursor += w

			if e.modifiers & { .Control, .Alt, } != {} {
				for !is_word(r) {
					r, w = utf8.decode_rune(input.buffer[input.cursor:])
					(w != 0) or_break
					input.cursor += w
				}
				for {
					r, w = utf8.decode_rune(input.buffer[input.cursor:])
					(w != 0) or_break
					if is_word(r) {
						input.cursor += w
					} else {
						break
					}
				}
			}
		}
		return .None
	case Event_Input_Codepoint:
		buf, n := utf8.encode_rune(e.codepoint)
		inject_at(&input.buffer, input.cursor, ..buf[:n])
		input.cursor += n
		return .Change
	case Event_Input_Mouse_Button:
		// TODO?
		return .None
	case:
		return .None
	}
}

input_line_destroy :: proc(input: Input_Line) {
	delete(input.buffer)
}

input_line_reset :: proc(input: ^Input_Line) {
	clear(&input.buffer)
	input.cursor = 0
}

@(require_results)
input_line_get_text :: proc(input: Input_Line) -> string {
	return string(input.buffer[:])
}

input_line_render :: proc(
	editor:     ^Editor,
	commands:   ^[dynamic]Draw_Command,
	input:      ^Input_Line,
	position:   [2]f32,
	delta_time: f32,
	default := "",
) -> (width: f32) {
	text := input_line_get_text(input^)
	if text == "" {
		text = default
	}
	width = draw_text(
		editor,
		commands,
		.Ui,
		text[:input.cursor],
		editor.config.theme[.Ui_Text].fg,
		position,
	)

	animation_set_target(&input.cursor_anim, width)
	anim   := animation_update(&input.cursor_anim, delta_time, editor.config.cursor_animation_speed)
	font   := find_font(editor, .Ui, {})
	height := (f32(font.ascender) - f32(font.descender)) * font.scale
	draw_rect(commands,
		offset = position + { anim, -(height + f32(font.descender) * font.scale), },
		size   = { 1, height, },
		color  = editor.config.theme[.Ui_Text].fg,
	)
	width += draw_text(
		editor,
		commands,
		.Ui,
		text[input.cursor:],
		editor.config.theme[.Ui_Text].fg,
		position + { width, 0, },
	)

	return
}

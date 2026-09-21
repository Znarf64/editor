package editor

import runtime "base:runtime"

import ease    "core:math/ease"
import fmt     "core:fmt"
import la      "core:math/linalg"
import log     "core:log"
import mem     "core:mem"
import os      "core:os"
import slice   "core:slice"
import strconv "core:strconv"
import strings "core:strings"
import time    "core:time"
import unicode "core:unicode"
import utf8    "core:unicode/utf8"
import vmem    "core:mem/virtual"

import cm      "vendor:commonmark"

import regex   "vendor/regex"

Draw_Command_Rect :: struct {
	rect:          Rect,
	color:         [4]f32,
	border_radius: f32,
	border_width:  f32,
	border_color:  [4]f32,
	shadow_width:  f32,
}

Draw_Command_Char :: struct {
	position: [2]f32,
	char:     rune,
	color:    [4]f32,
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
	Draw_Command_Clip,
	Draw_Command_Blur,
}

Position :: struct {
	line, column: int,
}

Selection :: struct {
	cursor:        Index,
	anchor:        Index,
	anim:          Animation(Rect),
	target_cursor: Index, // The offset of the position that dicatates the visual target column, so effective the offset that resulted from the last horizontal movement
}

Mode :: enum {
	Normal,
	Insert,
	Visual,
	Prompt,
	Picker,
}

Prompt_Mode :: enum {
	Command,
	Search,
	Keep,
	Select,
}

New_Selection :: struct {
	using selection: Selection,
	primary:         bool,
}

Diagnostic :: struct {
	start, end:    Index,
	message, code: string,
	severity:      Diagnostic_Severity,
}

Buffer_View :: struct {
	using buffer: ^Buffer,

	selections:    [dynamic]Selection,
	primary:       int,
	scroll:        int,
	scroll_anim:   Animation(f32),
	visible_lines: int,
}

Buffer :: struct {
	path:              Normalized_Path,
	btree:             BTree,

	uri:               Uri,
	language:          Language,
	diagnostics:       []Diagnostic,
	diagnostics_arena: vmem.Arena,
	version:           int,
}

buffer_view_destroy :: proc(view: Buffer_View) {
	delete(view.selections)
}

@(require_results)
buffer_view_clone :: proc(view: Buffer_View) -> Buffer_View {
	view := view
	view.selections = slice.clone_to_dynamic(view.selections[:])
	return view
}

editor_open_buffer :: proc(editor: ^Editor, buffer: ^Buffer) {
	if editor.buffer != nil && editor.buffer.buffer == buffer {
		return
	}

	w := &editor.window_tree
	for {
		switch &v in w {
		case Multi_Window:
			w = &v.children[v.focused]
		case Buffer_View:
			buffer_view_destroy(v)
			v = {
				buffer     = buffer,
				selections = make([dynamic]Selection, 1, context.allocator),
			}
			editor.buffer = &v
			return
		case:
			v = Buffer_View {
				buffer     = buffer,
				selections = make([dynamic]Selection, 1, context.allocator),
			}
			editor.buffer = (^Buffer_View)(&v)
			return
		}
	}
}

window_split :: proc(editor: ^Editor, vertical: bool) {
	w := &editor.window_tree
	p: ^Multi_Window
	for {
		switch &v in w {
		case Multi_Window:
			if v.vertical == vertical {
				p = &v
			} else {
				p = nil
			}
			w = &v.children[v.focused]
		case Buffer_View:
			view := buffer_view_clone(v)
			if p != nil {
				p.focused += 1
				inject_at(&p.children, p.focused, view)
				editor.buffer = (^Buffer_View)(&p.children[p.focused])
			} else {
				m := Multi_Window {
					children = make([dynamic]Window, 0, 2, context.allocator),
					vertical = vertical,
					focused  = 1,
				}
				append(&m.children, v)
				append(&m.children, view)
				w^ = m

				editor.buffer = (^Buffer_View)(&m.children[m.focused])
			}
			return
		case:
			panic("Corrupted window tree")
		}
	}
}

window_focus :: proc(editor: ^Editor, vertical: bool, next: bool) -> (changed: bool) {
	w := &editor.window_tree
	p: ^Multi_Window
	for {
		switch &v in w {
		case Multi_Window:
			defer w = &v.children[v.focused]

			if v.vertical != vertical {
				break
			}
			if next {
				if v.focused == len(v.children) - 1 {
					break
				}
			} else {
				if v.focused == 0 {
					break
				}
			}
			p = &v
		case Buffer_View:
			if p == nil {
				return
			}

			if next {
				p.focused += 1
			} else {
				p.focused -= 1
			}

			window_focus_update(editor)
			return true
		case:
			panic("Corrupted window tree")
		}
	}

	return false
}

window_move :: proc(editor: ^Editor, vertical: bool, next: bool) {
	b := editor.buffer
	if window_focus(editor, vertical, next) {
		editor.buffer^, b^ = b^, editor.buffer^
	}
}

window_transpose :: proc(editor: ^Editor) {
	w := &editor.window_tree
	p: ^Multi_Window
	for {
		switch &v in w {
		case Multi_Window:
			p = &v
			w = &v.children[v.focused]
		case Buffer_View:
			if p != nil {
				p.vertical ~= true
				window_focus_update(editor)
			}
			return
		case:
			panic("Corrupted window tree")
		}
	}
}

window_focus_update :: proc(editor: ^Editor) {
	w := &editor.window_tree
	p: ^Multi_Window
	for {
		switch &v in w {
		case Multi_Window:
			if p != nil && p.vertical == v.vertical {
				v := v
				ordered_remove(&p.children, p.focused)
				inject_at(&p.children, p.focused, ..v.children[:])
				delete(v.children)
				p.focused += v.focused
				w          = &p.children[p.focused]
				continue
			}
			p = &v
			w = &v.children[v.focused]
		case Buffer_View:
			editor.buffer = &v
			return
		case:
			panic("Corrupted window tree")
		}
	}
}

window_close :: proc(editor: ^Editor) {
	w := &editor.window_tree
	p: ^Window
	for {
		switch &v in w {
		case Multi_Window:
			p = w
			w = &v.children[v.focused]
		case Buffer_View:
			if p == nil {
				os.exit(0)
			}
			buffer_view_destroy(v)

			m := &p.(Multi_Window)
			ordered_remove(&m.children, m.focused)
			if m.focused == len(m.children) {
				m.focused -= 1
			}

			if len(m.children) == 1 {
				arr := m.children
				p^   = m.children[0]
				delete(arr)
			}

			window_focus_update(editor)
			return
		case:
			panic("Corrupted window tree")
		}
	}
}

file_open :: proc(editor: ^Editor, path: Normalized_Path) {
	editor.mode = .Normal
	for b in editor.buffers {
		if b.path == path {
			editor_open_buffer(editor, b)
			return
		}
	}

	buffer := new(Buffer)
	editor_open_buffer(editor, buffer)
	buffer_init(editor, buffer, path)
}

editor_go_to :: proc(editor: ^Editor, path: Normalized_Path, start: Index, end: Index = -1) {
	end := end
	if end == -1 {
		end = start
	}

	if path != "" {
		file_open(editor, path)
	}

	editor.buffer.primary = 0
	resize(&editor.buffer.selections, 1)
	editor.buffer.selections[0].anchor        = start
	editor.buffer.selections[0].cursor        = end
	editor.buffer.selections[0].target_cursor = end
}

buffer_init :: proc(editor: ^Editor, buffer: ^Buffer, path: Normalized_Path, language: Language = "") {
	data := os.read_entire_file(string(path), context.temp_allocator) or_else { '\n', }
	b    := strings.builder_make(0, len(data), context.temp_allocator)
	// iterating byte-wise is fine here
	for x in data {
		if x == '\r' {
			continue // nope
		}
		strings.write_byte(&b, x)
	}
	if len(data) == 0 || data[len(data) - 1] != '\n' {
		strings.write_byte(&b, '\n')
	}
	buffer_init_with_data(editor, buffer, path, strings.to_string(b), language)
}

buffer_init_with_data :: proc(editor: ^Editor, buffer: ^Buffer, path: Normalized_Path, data: string, language: Language = "") {
	path := path_clone(path, context.allocator)
	log.infof("Opening file '%s'", path)

	language := language
	if language == "" {
		language = get_language_from_extension(editor, path)
	}

	buffer^ = {
		path     = path,
		uri      = uri_from_path(path, context.allocator),
		btree    = btree_build(string(data), context.allocator),
		language = language,
	}
	err := vmem.arena_init_growing(&buffer.diagnostics_arena)
	assert(err == nil, "OOM")

	if lsp := editor_get_lsp_server(editor, language); lsp != nil {
		lsp_open_file(lsp, buffer.uri, data)
	}
	append(&editor.buffers, buffer)
}

@(require_results)
get_language_from_extension :: proc(editor: ^Editor, path: $S/string) -> Language {
	extension := string(path)
	if dot := strings.last_index_byte(extension, '.'); dot != -1 {
		extension = extension[dot + 1:]
	}

	return editor.language_extensions[extension] or_else "text"
}

@(require_results)
editor_get_lsp_server :: proc(editor: ^Editor, language: Language) -> ^LSP_Server {
	if lsp, ok := editor.language_servers[language]; ok {
		return lsp
	}

	config := editor.config.languages[language]
	if config.language_server == "" {
		log.warnf("No language server available for language '%s'", language)
		return nil
	}

	lsp := new(LSP_Server, context.allocator)
	err := lsp_init(lsp, { config.language_server, })
	lsp.language = language
	if err != nil {
		free(lsp, context.allocator)
		log.errorf("Failed to initialize lsp server '%s' (language: %s)", config.language_server, language)
		return nil
	}

	editor.language_servers[language] = lsp
	return lsp
}

buffer_destroy :: proc(buffer: ^Buffer) {
	vmem.arena_destroy(&buffer.diagnostics_arena)
	btree_destroy(buffer.btree)
	delete(string(buffer.path))
	delete(string(buffer.uri))
}

Leader_Entry :: struct {
	bind, action: string,
}

Leader :: struct {
	active:      bool,
	sequence:    strings.Builder,
	binds:       Keybinds,
	motion:      Argument_Motion,
	title:       string,
	entries:     []Leader_Entry,
	size:        [2]f32,
	binds_width: f32,
	rect:        Animation(Rect),
	alpha:       Animation(f32),
	arena:       vmem.Arena,
}

Multi_Window :: struct {
	children: [dynamic]Window,
	focused:  int,
	vertical: bool,
}

Window :: union {
	Multi_Window,
	Buffer_View,
}

Popup :: struct {
	rect:         Animation(Rect),
	text:         strings.Builder,
	highlight:    Range,
	content_type: Popup_Content_Type,
}

Popup_Content_Type :: enum {
	Markdown,
	Code,
	Text,
}

// Relative to the primary cursor
Popup_Location :: enum {
	Below,
	Right,
	Above,
}

Editor :: struct {
	backend:             ^Backend,

	mode:                Mode,

	window_tree:         Window,
	buffers:             [dynamic]^Buffer,
	buffer:              ^Buffer_View,

	new_selections:      [dynamic]New_Selection,

	repeat_count:        int,

	leader:              Leader,

	popups:              [Popup_Location]Popup,

	picker:              Picker,

	clipboard:           strings.Builder,

	jumplist:            Jumplist,

	status:              strings.Builder,

	prompt:              Prompt,

	config:              Config,

	font:                Font,

	language_extensions: map[string]Language,
	language_servers:    map[Language]^LSP_Server,
}

Language :: distinct string

Range :: struct {
	start, end: Index,
}

Jumplist_Entry :: struct {
	using range: Range,
	path:        Normalized_Path,
	content:     string,
}

Jumplist :: struct {
	entries: [dynamic]Jumplist_Entry,
	cursor:  int,
	arena:   vmem.Arena `fmt:"-"`,
}

jumplist_init :: proc(editor: ^Editor) {
	vmem.arena_init_growing(&editor.jumplist.arena) or_else panic("Failed to initialize arena")
}

jumplist_add :: proc(editor: ^Editor, selection: Selection) {
	// we should be using a linear allocator that we can reset to some point since entries will become irrelevant in a linear fashion
	allocator := vmem.arena_allocator(&editor.jumplist.arena)

	resize(&editor.jumplist.entries, editor.jumplist.cursor)
	editor.jumplist.cursor += 1

	start := min(selection.anchor, selection.cursor)
	end   := max(selection.anchor, selection.cursor)

	b := strings.builder_make(allocator)
	btree_to_string(&editor.buffer.btree, &b, start, end + 1)

	append(&editor.jumplist.entries, Jumplist_Entry {
		path    = editor.buffer.path,
		start   = start,
		end     = end,
		content = strings.to_string(b),
	})
}

jumplist_forward :: proc(editor: ^Editor) {
	if editor.jumplist.cursor >= len(editor.jumplist.entries) - 1 {
		editor_set_status(editor, "End of jumplist")
		return
	}

	editor.jumplist.cursor += 1
	entry                  := editor.jumplist.entries[editor.jumplist.cursor]

	editor_go_to(editor, entry.path, entry.start, entry.end)
}

jumplist_backward :: proc(editor: ^Editor) {
	if editor.jumplist.cursor == 0 {
		editor_set_status(editor, "End of jumplist")
		return
	}

	editor.jumplist.cursor -= 1
	entry                  := editor.jumplist.entries[editor.jumplist.cursor]

	editor_go_to(editor, entry.path, entry.start, entry.end)
}

Prompt :: struct {
	mode:           Prompt_Mode,
	input:          Input_Line,
	history:        [Prompt_Mode][dynamic]string,
	history_cursor: int,
	arena:          vmem.Arena,
}

window_tree_destroy :: proc(window_tree: Window) {
	switch v in window_tree {
	case Multi_Window:
		for c in v.children {
			window_tree_destroy(c)
		}
		delete(v.children)
	case Buffer_View:
		buffer_view_destroy(v)
	}
}

FONT_HEIGHT :: 12

DEBUG :: proc(x: any, expr := #caller_expression(x)) {
	fmt.println(expr, ": ", x, sep = "")
}

main :: proc() {
	context.logger = log.create_console_logger(.Debug when ODIN_DEBUG else .Error)
	defer log.destroy_console_logger(context.logger)

	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		defer mem.tracking_allocator_destroy(&track)

		context.allocator = mem.tracking_allocator(&track)

		defer for _, leak in track.allocation_map {
			log.warn("leaked", leak.size, "bytes", location = leak.location)
		}

		defer for bad_free in track.bad_free_array {
			log.error("allocation was freed badly", location = bad_free.location)
		}
	}

	editor: Editor
	editor.backend = backend_init()
	if editor.backend == nil {
		log.fatal("Failed to initialize backend")
		os.exit(1)
	}
	editor.new_selections = make([dynamic]New_Selection)

	editor.prompt.history_cursor = -1

	vmem.arena_init_growing(&editor.prompt.arena) or_else panic("Failed to initialize arena")
	vmem.arena_init_growing(&editor.leader.arena) or_else panic("Failed to initialize arena")

	jumplist_init(&editor)

	defer {
		editor.backend->destroy()
		for h in editor.prompt.history {
			delete(h)
		}
		for _, lsp in editor.language_servers {
			lsp_destroy(lsp)
			free(lsp)
		}
		delete(editor.language_servers)
		for b in editor.buffers {
			buffer_destroy(b)
			free(b)
		}
		delete(editor.buffers)
		vmem.arena_destroy(&editor.prompt.arena)
		vmem.arena_destroy(&editor.leader.arena)
		vmem.arena_destroy(&editor.jumplist.arena)
		delete(editor.jumplist.entries)
		delete(editor.new_selections)
		strings.builder_destroy(&editor.leader.sequence)
		input_line_destroy(editor.prompt.input)
		strings.builder_destroy(&editor.status)
		strings.builder_destroy(&editor.clipboard)
		for &popup in editor.popups {
			strings.builder_destroy(&popup.text)
		}
		picker_destroy(&editor.picker)
		window_tree_destroy(editor.window_tree)
	}

	font_ok := font_init(&editor.font, #load("font.ttf"), FONT_HEIGHT, context.allocator)
	assert(font_ok)
	defer font_destroy(editor.font)

	start_time := time.now()
	prev_time: f64

	config_ok := load_config(&editor.config)
	if !config_ok {
		log.error("Failed to load config")
	}
	defer config_destroy(&editor.config)

	editor.language_extensions = make(map[string]Language)
	defer delete(editor.language_extensions)

	for language, config in editor.config.languages {
		for extension in config.extensions {
			editor.language_extensions[extension] = language
		}
	}

	if len(os.args) >= 2 {
		file_open(&editor, normalize_path(os.args[1], context.temp_allocator))
	} else {
		buffer := new(Buffer)
		buffer_init_with_data(&editor, buffer, "<scratch>", "\n")
		editor_open_buffer(&editor, buffer)
	}

	last_print_time    := time.now()
	frames_since_print := 0

	draw_commands := make([dynamic]Draw_Command, context.allocator)
	defer delete(draw_commands)

	screen_size: [2]f32

	main_loop: for {
		frames_since_print += 1
		if time.since(last_print_time) > time.Second {
			editor.backend->set_title(fmt.tprintf("%v FPS", frames_since_print))
			frames_since_print = 0
			last_print_time    = time.now()
		}

		prev_scroll := editor.buffer.scroll
		prev_mode   := editor.mode

		consumed_codepoint_event: int

		for event in editor.backend->poll_events() {
			switch e in event {
			case Event_Window_Close:
				break main_loop
			case Event_Window_Resize:
				screen_size = ([2]f32)(e.size)

			case Event_Input_Key:
				if e.action == .Up {
					break
				}

				if editor.mode == .Prompt {
					switch input_line_handle_event(&editor.prompt.input, e) {
					case .None:
					case .Submit:
						prompt_apply(&editor)
						editor.mode = .Normal
						editor.prompt.history_cursor = -1
					case .Exit:
						editor.mode = .Normal
						editor.prompt.history_cursor = -1
					case .Change:
						editor.prompt.history_cursor = -1
					case .Next:
						history := editor.prompt.history[editor.prompt.mode]
						if len(history) == 0 {
							editor.prompt.history_cursor = -1
							break
						}
						if editor.prompt.history_cursor >= len(history) - 1 {
							editor.prompt.history_cursor = -1
						}
						editor.prompt.history_cursor += 1
						input_line_set_text(&editor.prompt.input, history[editor.prompt.history_cursor])
					case .Prev:
						history := editor.prompt.history[editor.prompt.mode]
						if len(history) == 0 {
							editor.prompt.history_cursor = -1
							break
						}
						if editor.prompt.history_cursor < 1 {
							editor.prompt.history_cursor = len(history)
						}
						editor.prompt.history_cursor -= 1
						input_line_set_text(&editor.prompt.input, history[editor.prompt.history_cursor])
					}
					break
				}

				if editor.mode == .Picker {
					switch input_line_handle_event(&editor.picker.input, e) {
					case .None:
					case .Submit:
						picker_submit(&editor)
						editor.mode = .Normal
					case .Exit:
						editor.mode = .Normal
					case .Change:
						picker_update(&editor)
					case .Next:
						picker_focus_next(&editor)
					case .Prev:
						picker_focus_prev(&editor)
					}
					break
				}

				defer if !editor.leader.active && editor.leader.motion == nil {
					strings.builder_reset(&editor.leader.sequence)
					editor.leader.entries = {}
					vmem.arena_free_all(&editor.leader.arena)
				}

				if editor.leader.motion != nil {
					if e.key == .Escape {
						editor.leader.motion = nil
						editor.repeat_count  = 0
					}
					break
				}

				if e.key >= ._0 && e.key <= ._9 && e.modifiers == {} {
					editor.repeat_count *= 10
					editor.repeat_count += int(e.key - ._0)
					break
				}

				binds                := editor.leader.binds if editor.leader.active else editor.config.keybinds[editor.mode]
				editor.leader.active  = false
				editor.leader.entries = {}
				keybind              := Keybind {
					modifiers = e.modifiers,
					key       = e.key,
				}
				action, ok := binds[keybind]
				if !ok {
					editor.repeat_count = 0
					break
				}

				consumed_codepoint_event = e.id // ignore any codepoint events generated by the same keypress

				action_apply(&editor, action, keybind)
			case Event_Input_Codepoint:
				if e.source == consumed_codepoint_event {
					break
				}
				if editor.leader.motion != nil {
					argument_motion_apply(&editor, editor.buffer, editor.leader.motion, e.codepoint)
					editor.leader.motion = nil
					editor.leader.active = false
					strings.builder_reset(&editor.leader.sequence)
					break
				}
				#partial switch editor.mode {
				case .Prompt:
					_ = input_line_handle_event(&editor.prompt.input, e)
				case .Picker:
					_ = input_line_handle_event(&editor.picker.input, e)
					picker_update(&editor)
				case .Insert:
					argument_motion_apply(&editor, editor.buffer, .Insert_Character, e.codepoint)
				}
			case Event_Input_Mouse_Move:
			case Event_Input_Mouse_Button:
			case Event_Input_Scroll:
				y := int(e.delta.y * editor.config.scroll_scale)
				if y == 0 {
					break
				}
				editor.repeat_count = abs(y)
				if y > 0 {
					action_apply(&editor, Motion.View_Line_Up, {})
				} else {
					action_apply(&editor, Motion.View_Line_Down, {})
				}
			}
		}

		primary := &editor.buffer.selections[editor.buffer.primary]

		if prev_scroll != editor.buffer.scroll {
			primary_position := btree_index_to_position(&editor.buffer.btree, primary.cursor, editor.config.tab_width)
			if primary_position.line < editor.buffer.scroll + 5 || primary_position.line > editor.buffer.scroll + editor.buffer.visible_lines - 5 {
				primary_position.line -= prev_scroll - editor.buffer.scroll
				_                      = position_to_index_normalized(editor.buffer, primary_position, true, primary, editor.config.tab_width)
				primary.anchor         = primary.cursor
			}
		}

		{
			primary_line := btree_index_to_line(&editor.buffer.btree, primary.cursor)
			if editor.buffer.scroll < primary_line - editor.buffer.visible_lines + 5 {
				editor.buffer.scroll = primary_line - editor.buffer.visible_lines + 5
			}

			if editor.buffer.scroll > primary_line - 5 {
				editor.buffer.scroll = primary_line - 5
			}
		}

		if editor.mode == .Insert && editor.mode != prev_mode {
			if lsp := editor_get_lsp_server(&editor, editor.buffer.language); lsp != nil {
				if lsp.capabilities.signatureHelpProvider != nil {
					lsp_get_signature_help(&editor, editor.buffer)
				}
				// if lsp.capabilities.completionProvider != nil {
				// 	lsp_get_completion(&editor, editor.buffer)
				// }
			}
		}

		editor.buffer.scroll = clamp(editor.buffer.scroll, 0, int(editor.buffer.btree.lines - 1))
		animation_set_target(&editor.buffer.scroll_anim, f32(editor.buffer.scroll))

		current_time := time.duration_seconds(time.since(start_time))
		delta_time   := current_time - prev_time
		prev_time     = current_time

		if !editor.config.enable_animations {
			delta_time = max(f64)
		}

		clear(&draw_commands)

		for language, lsp in editor.language_servers {
			lsp_err := lsp_update(&editor, lsp)
			if lsp_err != nil {
				log.error("LSP Error:", language, lsp_err)
				delete_key(&editor.language_servers, language)
				lsp_destroy(lsp)
				free(lsp)
			}
		}

		render(&editor, &draw_commands, f32(delta_time), screen_size)

		editor.backend->draw(editor.font, draw_commands[:], editor.config.theme[.Background].bg)
		free_all(context.temp_allocator)
	}
}

Rect :: struct {
	min, max: [2]f32,
}

@(require_results)
rect_from_min_max :: #force_inline proc "contextless" (min, max: [2]f32) -> Rect {
	return { min = min, max = max,  }
}

@(require_results)
rect_center :: #force_inline proc "contextless" (rect: Rect) -> [2]f32 {
	return (rect.min + rect.max) / 2
}

@(require_results)
rect_size :: #force_inline proc "contextless" (rect: Rect) -> [2]f32 {
	return rect.max - rect.min
}

@(require_results)
rect_inflate :: #force_inline proc "contextless" (rect: Rect, v: [2]f32) -> Rect {
	return {
		min = rect.min - v,
		max = rect.max + v,
	}
}

@(require_results)
rect_round :: #force_inline proc "contextless" (rect: Rect) -> Rect {
	return {
		min = la.round(rect.min),
		max = la.round(rect.max),
	}
}

Animation :: struct(T: typeid) {
	origin:  T,
	target:  T,
	current: T,
	t:       f32,
}

@(require_results)
animation_update :: proc(anim: ^Animation($T), delta_time, speed: f32) -> T {
	if speed <= 0 {
		return anim.target
	}
	anim.t = clamp(anim.t + speed * f32(delta_time), 0, 1)
	when T == Rect {
		anim.current = transmute(Rect)la.lerp(transmute([4]f32)anim.origin, transmute([4]f32)anim.target, ease.quartic_out(anim.t))
	} else {
		anim.current = la.lerp(anim.origin, anim.target, ease.quartic_out(anim.t))
	}
	return anim.current
}

animation_set_target :: proc(anim: ^Animation($T), target: T) {
	if anim.target == target {
		return
	}
	anim.origin = anim.current
	anim.target = target
	anim.t      = 0
}

window_render :: proc(editor: ^Editor, commands, popup_commands: ^[dynamic]Draw_Command, window: ^Window, delta_time: f32, rect: Rect) {
	switch &w in window {
	case Multi_Window:
		gap         := 2 * editor.config.padding + 1
		n           := len(w.children)
		axis        := int(!w.vertical)
		size        := rect_size(rect)
		per_window  := (size[axis] - f32(n - 1) * gap) / f32(n)
		origin      := rect.min
		extent      := size
		extent[axis] = per_window
		for &w, i in w.children {
			if i != 0 {
				size         := extent
				size[axis]    = 1
				origin       := origin
				origin[axis] -= editor.config.padding

				draw_rect(commands,
					offset = la.round(origin),
					size   = size,
					color  = editor.config.theme[.Gutter].fg,
				)
			}
			window_render(editor, commands, popup_commands, &w, delta_time, { min = origin, max = origin + extent, })
			origin[axis] += per_window + gap
		}
	case Buffer_View:
		buffer_render(editor, &w, commands, popup_commands, delta_time, rect_round(rect))
	}
}

render :: proc(editor: ^Editor, commands: ^[dynamic]Draw_Command, delta_time: f32, screen_size: [2]f32) {
	padding           := editor.config.padding
	status_bar_height := FONT_HEIGHT + padding * 2 + 2

	popup_commands := make([dynamic]Draw_Command, context.temp_allocator)
	window_render(editor, commands, &popup_commands, &editor.window_tree, delta_time, { min = padding, max = screen_size - { 0, status_bar_height, } - padding, })
	append(commands, ..popup_commands[:])

	draw_rect(commands,
		offset = { 0, screen_size.y - FONT_HEIGHT - padding * 2, },
		size   = { screen_size.x, FONT_HEIGHT + padding * 2, },
		color  = editor.config.theme[.Background].bg,
	)
	draw_rect(commands,
		offset = { 0, screen_size.y - FONT_HEIGHT - padding * 2 - 2, },
		size   = { screen_size.x, 2, },
		color  = color_from_hex_rgba(0x32363DFF),
	)

	{
		buffer           := editor.buffer
		primary          := buffer.selections[buffer.primary]
		primary_position := btree_index_to_position(&buffer.btree, primary.cursor, editor.config.tab_width)

		{
			x := screen_size.x - padding
			if strings.builder_len(editor.leader.sequence) != 0 {
				str := strings.to_string(editor.leader.sequence)
				x   -= measure_text(&editor.font, str)
				draw_text(&editor.font, commands, str, editor.config.theme[.Ui_Text].fg, { x, screen_size.y - padding, })
			}

			if editor.repeat_count > 0 {
				@(static)
				buf: [32]byte

				str := strconv.write_int(buf[:], i64(editor.repeat_count), base = 10)
				x   -= measure_text(&editor.font, str)
				draw_text(&editor.font, commands, str, editor.config.theme[.Ui_Text].fg, { x, screen_size.y - padding, })
			}

			if x != screen_size.x - padding {
				x -= padding
			}

			{
				center := screen_size.x / 2
				w      := measure_text(&editor.font, buffer.path)
				draw_text(&editor.font, commands, buffer.path, editor.config.theme[.Ui_Text].fg, { center - w / 2, screen_size.y - padding, })
			}

			{
				@(static)
				buf: [32]byte
				str: string

				if editor.buffer.language != "" {
					str = string(editor.buffer.language)
					x  -= measure_text(&editor.font, str)
					draw_text(&editor.font, commands, str, editor.config.theme[.Ui_Text].fg, { x, screen_size.y - padding, })
					x  -= padding
				}

				str = strconv.write_int(buf[:], i64(primary_position.column + 1), base = 10)
				x  -= measure_text(&editor.font, str)
				draw_text(&editor.font, commands, str, editor.config.theme[.Ui_Text].fg, { x, screen_size.y - padding, })

				str = ":"

				x -= measure_text(&editor.font, str)
				draw_text(&editor.font, commands, str, editor.config.theme[.Ui_Text].fg, { x, screen_size.y - padding, })

				str = strconv.write_int(buf[:], i64(primary_position.line + 1), base = 10)
				x  -= measure_text(&editor.font, str)
				draw_text(&editor.font, commands, str, editor.config.theme[.Ui_Text].fg, { x, screen_size.y - padding, })

				x -= padding

				str = "sel"

				x  -= measure_text(&editor.font, str)
				draw_text(&editor.font, commands, str, editor.config.theme[.Ui_Text].fg, { x, screen_size.y - padding, })

				x -= padding

				str = strconv.write_int(buf[:], i64(len(buffer.selections)), base = 10)
				x  -= measure_text(&editor.font, str)
				draw_text(&editor.font, commands, str, editor.config.theme[.Ui_Text].fg, { x, screen_size.y - padding, })
			}
		}
	}

	x := padding
	{
		mode_text:  string
		mode_style: Style_Key
		#partial switch editor.mode {
		case .Normal:
			mode_text  = "NORMAL"
			mode_style = .Indicator_Normal
		case .Visual:
			mode_text  = "VISUAL"
			mode_style = .Indicator_Visual
		case .Insert:
			mode_text  = "INSERT"
			mode_style = .Indicator_Insert
		}

		if mode_text != "" {
			w     := measure_text(&editor.font, mode_text)
			style := editor.config.theme[mode_style]
			if style.bg != 0 {
				draw_rect(commands,
					offset = { x - padding, screen_size.y - FONT_HEIGHT - padding * 2, },
					size   = { w, FONT_HEIGHT, } + padding * 2,
					color  = style.bg,
				)
			}
			draw_text(
				&editor.font,
				commands,
				mode_text,
				editor.config.theme[mode_style].fg,
				{ x, screen_size.y - padding, },
			)

			x += w + padding

			if style.bg != 0 {
				x += padding
			}
		}
	}

	cell_size: [2]f32 = {
		la.round(get_glyph_info(&editor.font, 0).x_advance),
		la.round(((f32(editor.font.ascender) - f32(editor.font.descender)) * editor.font.scale)),
	}

	if editor.mode == .Prompt {
		is_regex: bool
		mode_string: string
		switch editor.prompt.mode {
		case .Command:
			mode_string = ":"
		case .Search:
			mode_string = "search: "
			is_regex    = true
		case .Keep:
			mode_string = "keep: "
			is_regex    = true
		case .Select:
			mode_string = "select: "
			is_regex    = true
		}

		x := x + draw_text(
			&editor.font,
			commands,
			mode_string,
			editor.config.theme[.Ui_Text].fg,
			{ x, screen_size.y - padding, },
		)

		default: string
		if default == "" {
			history := editor.prompt.history[editor.prompt.mode]
			if len(history) != 0 {
				default = history[len(history) - 1]
			}
		}
		w := input_line_render(editor, commands, &editor.prompt.input, { x, screen_size.y - padding, }, delta_time, default)

		text := input_line_get_text(editor.prompt.input)
		if text == "" {
			text = default
		}

		if is_regex {
			case_insensitive := true
			for r in text {
				if unicode.is_upper(r) {
					case_insensitive = false
					break
				}
			}

			if case_insensitive {
				draw_text(
					&editor.font,
					commands,
					" (Aa)",
					editor.config.theme[.Ui_Text].fg,
					{ x + w, screen_size.y - padding, },
				)
			}
		}
	} else {
		draw_text(
			&editor.font,
			commands,
			strings.to_string(editor.status),
			editor.config.theme[.Ui_Text].fg,
			{ x, screen_size.y - padding, },
		)
	}

	leader_target_rect := Rect {
		min = (screen_size - 20 - { 0, FONT_HEIGHT + padding * 2, }) - editor.leader.size,
		max = (screen_size - 20 - { 0, FONT_HEIGHT + padding * 2, }),
	}
	if editor.leader.active {
		animation_set_target(&editor.leader.rect, leader_target_rect)
	} else {
		center := rect_center(leader_target_rect)
		animation_set_target(&editor.leader.rect, Rect{ min = center, max = center, })
	}

	leader_rect := animation_update(&editor.leader.rect, delta_time, editor.config.popup_animation_speed)
	draw_rect(commands,
		offset        = leader_rect.min,
		size          = rect_size(leader_rect),
		color         = editor.config.theme[.Popup_Background].fg,
		border_color  = editor.config.theme[.Popup_Border].fg,
		border_radius = 8,
		border_width  = 2,
		shadow_width  = 16,

		blur_radius   = f32(editor.config.blur_strength),
	)

	animation_set_target(&editor.leader.alpha, editor.leader.active && editor.leader.rect.t == 1 ? 1 : 0)
	leader_alpha := animation_update(&editor.leader.alpha, delta_time, editor.config.popup_animation_speed)

	if editor.leader.active {
		x := leader_rect.min.x + padding
		y := leader_rect.min.y + padding

		text_color := editor.config.theme[.Ui_Text].fg * { 1, 1, 1, leader_alpha, }

		draw_text(&editor.font, commands, editor.leader.title, text_color, { x, y + FONT_HEIGHT, })
		y += FONT_HEIGHT + padding

		draw_rect(commands,
			offset = { x, y, },
			size   = { rect_size(leader_rect).x - padding * 2, 2, },
			color  = color_from_hex_rgba(0x32363DFF) * { 1, 1, 1, leader_alpha, },
		)
		y += padding + 2

		if len(editor.leader.entries) == 0 && len(editor.leader.binds) != 0 {
			allocator            := vmem.arena_allocator(&editor.leader.arena)
			editor.leader.entries = make([]Leader_Entry, len(editor.leader.binds), allocator)

			binds_width:   f32
			actions_width: f32

			i := 0
			for bind, action in editor.leader.binds {
				editor.leader.entries[i] = {
					bind   = keybind_to_string(bind,  &editor.leader.arena),
					action = action_to_string(action, &editor.leader.arena),
				}
				binds_width   = max(binds_width,   measure_text(&editor.font, editor.leader.entries[i].bind  ))
				actions_width = max(actions_width, measure_text(&editor.font, editor.leader.entries[i].action))

				i += 1
			}

			editor.leader.binds_width = binds_width

			editor.leader.size = padding + [2]f32 {
				binds_width + padding + cell_size.x + padding + actions_width,
				FONT_HEIGHT + padding + 2 + padding + f32(len(editor.leader.entries)) * (FONT_HEIGHT + padding) - padding,
			} + padding

			slice.sort_by(editor.leader.entries, proc(a, b: Leader_Entry) -> bool {
				return a.bind < b.bind
			})
		}

		for entry in editor.leader.entries {
			draw_text(&editor.font, commands, entry.bind, text_color, { x, y + FONT_HEIGHT, })
			x := x + editor.leader.binds_width + padding
			x += draw_text(&editor.font, commands, "󰁔", text_color, { x, y + FONT_HEIGHT, }) + padding

			draw_text(&editor.font, commands, entry.action, text_color, { x, y + FONT_HEIGHT, })

			y += FONT_HEIGHT + padding
		}
	} else {
		editor.leader.alpha.target  = 0
		editor.leader.alpha.current = 0
		editor.leader.alpha.t       = 1
	}

	picker_render(editor, commands, delta_time, padding, screen_size)
}

@(require_results)
next_column_after_tab :: proc(column, tab_width: int) -> int {
	column := column + 1
	for column % tab_width != 0 {
		column += 1
	}
	return column
}

editor_set_status :: proc(editor: ^Editor, format: string, args: ..any) {
	strings.builder_reset(&editor.status)
	fmt.sbprintf(&editor.status, format, ..args)
}

editor_set_popup_text :: proc(editor: ^Editor, content_type: Popup_Content_Type, format: string, args: ..any, location: Popup_Location = .Below, highlight: Range = {}) {
	popup := &editor.popups[location]

	popup.content_type = content_type

	strings.builder_reset(&popup.text)
	fmt.sbprintf(&popup.text, format, ..args)
	popup.highlight = highlight

	if popup.content_type == .Markdown {
		content := strings.to_string(popup.text)

		root := cm.parse_document(raw_data(content), len(content), cm.DEFAULT_OPTIONS)
		defer cm.node_free(root)
		iter := cm.iter_new(root)
		defer cm.iter_free(iter)

		code: string
		iter_loop: for {
			ev_type := cm.iter_next(iter)
			if ev_type == .Done {
				break
			}

			cur := cm.iter_get_node(iter)

			#partial switch cur.type {
			case .None, .Document:
			case .Code_Block:
				code = string(cur.data[:cur.len])
			case:
				code = ""
				break iter_loop
			}
		}

		if code != "" {
			strings.builder_reset(&popup.text)
			strings.write_string(&popup.text, code)
			popup.content_type = .Code
		}
	}
}

regex_search :: proc(editor: ^Editor, buffer: ^Buffer_View, pattern_string: string) -> (ok: bool) {
	pattern := regex_create(editor, pattern_string) or_return
	defer if !ok {
		editor_set_status(editor, "Not found")
	}

	selection  := &buffer.selections[buffer.primary]
	start      := max(selection.cursor, selection.anchor)
	b          := strings.builder_make(context.temp_allocator)
	btree_to_string(&buffer.btree, &b, start)

	iter := regex.create_iterator(strings.to_string(b), pattern, permanent_allocator = context.temp_allocator)
	capture: regex.Capture
	capture, _, ok = regex.match(&iter)

	if ok && capture.pos[0][0] == 0 {
		capture, _, ok = regex.match(&iter)
	}

	if ok {
		selection.anchor        = btree_offset_to_index(&buffer.btree, _Offset(capture.pos[0][0]), start)
		selection.cursor        = btree_offset_to_index(&buffer.btree, _Offset(capture.pos[0][1]), start) - 1
		selection.target_cursor = selection.cursor
		return
	}

	if start == 0 {
		return
	}

	strings.builder_reset(&b)
	strings.builder_grow(&b, int(start))
	btree_to_string(&buffer.btree, &b, end = start)

	capture = regex.match(pattern, strings.to_string(b), context.temp_allocator) or_return

	selection.anchor        = btree_offset_to_index(&buffer.btree, _Offset(capture.pos[0][0]))
	selection.cursor        = btree_offset_to_index(&buffer.btree, _Offset(capture.pos[0][1])) - 1
	selection.target_cursor = selection.cursor

	editor_set_status(editor, "Wrapped around document")

	return true
}

regex_search_reverse :: proc(editor: ^Editor, buffer: ^Buffer_View, pattern_string: string) -> (ok: bool) {
	pattern := regex_create(editor, pattern_string, { .Reverse_Pattern, }) or_return
	defer if !ok {
		editor_set_status(editor, "Not found")
	}

	selection  := &buffer.selections[buffer.primary]
	start      := min(selection.cursor, selection.anchor)
	b          := strings.builder_make(0, context.temp_allocator)
	btree_to_string(&buffer.btree, &b, end = start, reverse = true)

	iter := regex.create_iterator(strings.to_string(b), pattern, permanent_allocator = context.temp_allocator)
	capture: regex.Capture
	capture, _, ok = regex.match(&iter)

	if ok && capture.pos[0][0] == 0 {
		capture, _, ok = regex.match(&iter)
	}

	if ok {
		selection.cursor        = btree_offset_to_index(&buffer.btree, -_Offset(capture.pos[0][0]), start) + 1
		selection.anchor        = btree_offset_to_index(&buffer.btree, -_Offset(capture.pos[0][1]), start)
		selection.target_cursor = selection.cursor
		return
	}

	strings.builder_reset(&b)
	strings.builder_grow(&b, int(start))
	btree_to_string(&buffer.btree, &b, start = start, reverse = true)

	capture = regex.match(pattern, strings.to_string(b), context.temp_allocator) or_return

	selection.cursor        = btree_offset_to_index(&buffer.btree, buffer.btree.bytes - _Offset(capture.pos[0][0]))
	selection.anchor        = btree_offset_to_index(&buffer.btree, buffer.btree.bytes - _Offset(capture.pos[0][1])) - 1
	selection.target_cursor = selection.cursor

	editor_set_status(editor, "Wrapped around document")

	return true
}

@(require_results)
regex_create :: proc(editor: ^Editor, pattern_string: string, extra_flags: regex.Flags = {}) -> (pattern: regex.Regular_Expression, ok: bool) {
	flags := regex.Flags { .Unicode, .Case_Insensitive, } | extra_flags

	for r in pattern_string {
		if unicode.is_upper(r) {
			flags -= { .Case_Insensitive, }
			break
		}
	}

	err: regex.Error
	pattern, err = regex.create(pattern_string, flags, permanent_allocator = context.temp_allocator)
	if err != nil {
		editor_set_status(editor, "Failed to parse regex: %v", err)
		return
	}

	ok = true
	return
}

prompt_apply :: proc(editor: ^Editor) {
	history := &editor.prompt.history[editor.prompt.mode]
	if len(editor.prompt.input.buffer) == 0 {
		if len(history) != 0 {
			append(&editor.prompt.input.buffer, history[len(history) - 1])
		}
	} else {
		append(history, strings.clone(input_line_get_text(editor.prompt.input), vmem.arena_allocator(&editor.prompt.arena)))
	}

	input := input_line_get_text(editor.prompt.input)

	switch editor.prompt.mode {
	case .Select:
		pattern := regex_create(editor, input) or_break

		b := strings.builder_make(context.temp_allocator)
		for selection, i in editor.buffer.selections {
			start := min(selection.cursor, selection.anchor)
			end   := max(selection.cursor, selection.anchor) + 1

			strings.builder_grow(&b, int(end - start))
			btree_to_string(&editor.buffer.btree, &b, start, end)

			regex_iter := regex.create_iterator(strings.to_string(b), pattern, permanent_allocator = context.temp_allocator)
			for capture, capture_i in regex.match(&regex_iter) {
				append(&editor.new_selections, New_Selection {
					anchor  = btree_offset_to_index(&editor.buffer.btree, _Offset(capture.pos[0][0]), start),
					cursor  = btree_offset_to_index(&editor.buffer.btree, _Offset(capture.pos[0][1]), start) - 1,
					primary = i == editor.buffer.primary && capture_i == 0,
				})
			}
			strings.builder_reset(&b)
		}

		if len(editor.new_selections) != 0 {
			clear(&editor.buffer.selections)
			reserve(&editor.buffer.selections, len(editor.new_selections))

			for selection in editor.new_selections {
				if selection.primary {
					editor.buffer.primary = len(editor.buffer.selections)
				}
				selection              := selection
				selection.target_cursor = selection.cursor
				append(&editor.buffer.selections, selection)
			}
			clear(&editor.new_selections)
			deduplicate_selections(editor.buffer)
		}
	case .Keep:
		pattern := regex_create(editor, input) or_break

		b := strings.builder_make(context.temp_allocator)

		for i := len(editor.buffer.selections) - 1; i >= 0; i -= 1 {
			selection := editor.buffer.selections[i]

			start := min(selection.cursor, selection.anchor)
			end   := max(selection.cursor, selection.anchor) + 1

			strings.builder_grow(&b, int(end - start))
			btree_to_string(&editor.buffer.btree, &b, start, end)

			_, ok := regex.match(pattern, strings.to_string(b), context.temp_allocator)
			if ok {
				append(&editor.new_selections, New_Selection {
					anchor  = selection.anchor,
					cursor  = selection.cursor,
					primary = i == editor.buffer.primary,
				})
			}
			strings.builder_reset(&b)
		}

		if len(editor.new_selections) != 0 {
			editor.buffer.primary = 0
			clear(&editor.buffer.selections)
			reserve(&editor.buffer.selections, len(editor.new_selections))

			for selection in editor.new_selections {
				if selection.primary {
					editor.buffer.primary = len(editor.buffer.selections)
				}
				selection              := selection
				selection.target_cursor = selection.cursor
				append(&editor.buffer.selections, selection)
			}
			clear(&editor.new_selections)
			deduplicate_selections(editor.buffer)
		}
	case .Search:
		regex_search(editor, editor.buffer, input)
	case .Command:
		command, ok := parse_command(input_line_get_text(editor.prompt.input), context.temp_allocator)
		if !ok {
			editor_set_status(editor, "Failed to parse command")
			break
		}
		command_execute(editor, command)
	}
	input_line_reset(&editor.prompt.input)
}

@(require_results)
position_after :: proc(position: Position, r: rune, tab_width: int) -> Position {
	position := position
	switch r {
	case 0:
	case '\n':
		position.line  += 1
		position.column = 0
	case '\t':
		position.column = next_column_after_tab(position.column, tab_width)
	case:
		position.column += 1
	}

	return position
}

@(require_results)
selection_contains :: proc(selection: Selection, index: Index) -> bool {
	return min(selection.anchor, selection.cursor) <= index && index <= max(selection.anchor, selection.cursor)
}

draw_rect :: proc(
	commands:     ^[dynamic]Draw_Command,
	offset:        [2]f32,
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
	rect := rect_from_min_max(offset, offset + size)
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

code_block_render :: proc(
	editor:    ^Editor,
	commands:  ^[dynamic]Draw_Command,
	position:  [2]f32,
	content:   string,
	language:  Language,
	highlight: Range,
) -> (size: [2]f32) {
	if content == "" {
		return
	}

	highlighter := highlighter_create(content, editor.config.languages[language], context.temp_allocator)

	cell_size: [2]f32 = {
		la.round(get_glyph_info(&editor.font, 0).x_advance),
		la.round((f32(editor.font.ascender) - f32(editor.font.descender)) * editor.font.scale),
	}
	line_height := cell_size.y

	width: f32
	y := la.round(f32(editor.font.ascender) * editor.font.scale)

	column: int
	render_code: for {
		index       := highlighter.index
		text, style := highlighter_advance(&highlighter)
		if style == .Invalid {
			break
		}

		start_column := column

		rect_index := len(commands)
		if editor.config.theme[style].bg != 0 {
			append(commands, nil)
		}

		for r in text {
			defer index += 1

			if r == '\n' {
				width  = max(width, cell_size.x * f32(column))
				y     += line_height
				column = 0
				continue
			}

			if r == '\t' {
				column = next_column_after_tab(column, editor.config.tab_width)
				continue
			}

			if highlight.start <= index && index < highlight.end {
				draw_rect(
					commands,
					offset = { cell_size.x * f32(column), y - la.round(f32(editor.font.ascender) * editor.font.scale), } + position,
					size   = cell_size,
					color  = editor.config.theme[.Selection].bg,
				)
			}

			defer column += 1

			if unicode.is_space(r) {
				continue
			}

			append(commands, Draw_Command_Char {
				position = { cell_size.x * f32(column), y, } + position,
				char     = r,
				color    = editor.config.theme[style].fg,
			})
		}

		if editor.config.theme[style].bg != 0 {
			offset := [2]f32 { f32(start_column) * cell_size.x, y - la.round(f32(editor.font.ascender) * editor.font.scale), } + position
			size   := [2]f32 { f32(column - start_column) * cell_size.x, cell_size.y, }

			commands[rect_index] = Draw_Command_Rect {
				rect  = { min = offset, max = offset + size, },
				color = editor.config.theme[style].bg,

				border_radius = 2,
			}
		}
	}

	if column != 0 {
		y += line_height
	}

	width = max(width, cell_size.x * f32(column))
	y    -= la.round(f32(editor.font.ascender) * editor.font.scale)

	return { width, y, }
}

markdown_render :: proc(
	editor:          ^Editor,
	commands:        ^[dynamic]Draw_Command,
	position:        [2]f32,
	content:         string,
	highlight:       Range,
	container_width: f32,
) -> (size: [2]f32) {
	cell_size: [2]f32 = {
		la.round(get_glyph_info(&editor.font, 0).x_advance),
		la.round((f32(editor.font.ascender) - f32(editor.font.descender)) * editor.font.scale),
	}
	line_height := cell_size.y

	width, x, y, indentation: f32

	position := position + { 0, la.round(f32(editor.font.ascender) * editor.font.scale), }

	root := cm.parse_document(raw_data(content), len(content), cm.DEFAULT_OPTIONS)
	defer cm.node_free(root)
	iter := cm.iter_new(root)
	defer cm.iter_free(iter)

	for {
		ev_type := cm.iter_next(iter)
		if ev_type == .Done {
			break
		}
		cur := cm.iter_get_node(iter)

		text := string(cur.data[:cur.len])

		switch cur.type {
		case .None:
		case .Document:
		case .Block_Quote:
			x += draw_text(&editor.font, commands, "Block_Quote", editor.config.theme[.Operator].fg, { x, y, } + position)

			width = max(width, x)
			y    += line_height
			x     = indentation
		case .List:
			if ev_type == .Exit {
				width = max(width, x)
				y    += line_height
				x     = indentation
			}
		case .Item:
			if ev_type == .Enter {
				RADIUS :: 2
				draw_rect(commands, { cell_size.x - RADIUS, y - FONT_HEIGHT / 2 - RADIUS, } + position, RADIUS * 2, editor.config.theme[.Ui_Text].fg, border_radius = RADIUS)
				x           += cell_size.x * 2
				indentation += cell_size.x * 2
			} else if ev_type == .Exit {
				indentation -= cell_size.x * 2
				x            = indentation
			}
		case .Code_Block:
			rect_index := len(commands)
			append(commands, nil)

			y -= la.round(f32(editor.font.ascender) * editor.font.scale)

			language := Language(cur.as.code.info)
			if language == "" {
				language = editor.buffer.language
			}

			pad: f32 = 4
			code_block_size := code_block_render(editor, commands, position + { x, y, } + pad, strings.trim_right(text, "\n"), language, highlight)

			commands[rect_index] = Draw_Command_Rect {
				rect          = {
					min = position + { 0, y, },
					max = position + { 0, y, } + code_block_size + pad * 2,
				},
				color         = editor.config.theme[.Ui_Code].fg,
				border_radius = 4,
				border_color  = editor.config.theme[.Selection].bg,
				border_width  = 2,
			}

			width = max(width, code_block_size.x + pad * 2)
			y    += code_block_size.y + la.round(f32(editor.font.ascender) * editor.font.scale) + pad * 2
			x     = indentation
		case .HTML_Block:
			x += draw_text(&editor.font, commands, "HTML_Block",     editor.config.theme[.Operator].fg, { x, y, } + position)

			width = max(width, x)
			y    += line_height
			x     = indentation
		case .Custom_Block:
			x += draw_text(&editor.font, commands, "Custom_Block",   editor.config.theme[.Operator].fg, { x, y, } + position)

			width = max(width, x)
			y    += line_height
			x     = indentation
		case .Paragraph:
			if ev_type == .Exit {
				width = max(width, x)
				y    += line_height
				x     = indentation
			}
		case .Heading:
			width = max(width, x)
			y    += line_height

			if ev_type == .Exit {
				draw_rect(commands, { 0, y - FONT_HEIGHT, } + position, { x, 1, }, editor.config.theme[.Ui_Text].fg)
				y += line_height
			}

			x = indentation
		case .Thematic_Break:
			draw_rect(commands, { 0, y - FONT_HEIGHT / 2 - 1, } + position, { container_width - editor.config.padding * 2, 1, }, editor.config.theme[.Ui_Text].fg)

			width = max(width, x)
			y    += line_height
			x     = indentation
		case .Soft_Break, .Line_Break:
			width = max(width, x)
			y    += line_height
			x     = indentation
		case .Text:
			x += draw_text(&editor.font, commands, text, editor.config.theme[.Ui_Text].fg,  { x, y, } + position)
		case .Code:
			rect_index := len(commands)
			append(commands, nil)

			y -= la.round(f32(editor.font.ascender) * editor.font.scale)

			pad: [2]f32 = { 3, 0, }
			code_block_size := code_block_render(editor, commands, position + { x, y, } + pad, strings.trim_right(text, "\n"), Language(cur.as.code.info), highlight)

			commands[rect_index] = Draw_Command_Rect {
				rect          = {
					min = position + { x, y, },
					max = position + { x, y, } + code_block_size + pad * 2,
				},
				color         = editor.config.theme[.Ui_Code].fg,
				border_radius = 4,
				border_color  = editor.config.theme[.Selection].bg,
				border_width  = 2,
			}

			y += la.round(f32(editor.font.ascender) * editor.font.scale)
			x += code_block_size.x + pad.x * 2
		case .HTML_Inline:
			x += draw_text(&editor.font, commands, text, editor.config.theme[.Ui_Text].fg,  { x, y, } + position)
		case .Custom_Inline:
			x += draw_text(&editor.font, commands, text, editor.config.theme[.Ui_Text].fg,  { x, y, } + position)
		case .Emph:
			x += draw_text(&editor.font, commands, text, editor.config.theme[.Keyword].fg,  { x, y, } + position)
		case .Strong:
			x += draw_text(&editor.font, commands, text, editor.config.theme[.Operator].fg, { x, y, } + position)
		case .Link:
			x += draw_text(&editor.font, commands, text, editor.config.theme[.String].fg,   { x, y, } + position)
		case .Image:
			x += draw_text(&editor.font, commands, text, editor.config.theme[.Ui_Text].fg,  { x, y, } + position)
		}
	}

	return { width, y, }
}

popup_render :: proc(
	editor:     ^Editor,
	popup:      ^Popup,
	commands:   ^[dynamic]Draw_Command,
	delta_time: f32,
	position:   [2]f32,
	location:   Popup_Location,
) {
	cell_size: [2]f32 = {
		la.round(get_glyph_info(&editor.font, 0).x_advance),
		la.round((f32(editor.font.ascender) - f32(editor.font.descender)) * editor.font.scale),
	}

	popup_rect     := animation_update(&popup.rect, delta_time, editor.config.popup_animation_speed)
	popup_rect.min += position
	popup_rect.max += position

	draw_rect(commands,
		offset        = popup_rect.min,
		size          = rect_size(popup_rect),
		color         = editor.config.theme[.Popup_Background].fg,
		border_color  = editor.config.theme[.Popup_Border].fg,
		border_radius = 8,
		border_width  = 2,
		shadow_width  = 16,

		blur_radius   = f32(editor.config.blur_strength),
	)

	text_base := popup_rect.min + editor.config.padding

	text := strings.to_string(popup.text)

	size: [2]f32
	switch popup.content_type {
	case .Markdown:
		size = markdown_render(editor, commands, text_base, text, popup.highlight, popup_rect.max.x - popup_rect.min.x)
	case .Code:
		size = code_block_render(editor, commands, text_base, text, editor.buffer.language, popup.highlight)
	case .Text:
	}

	rect_base: [2]f32
	switch location {
	case .Right:
		rect_base.x += cell_size.x
		rect_base.y -= cell_size.y
	case .Above:
		rect_base.y -= size.y + cell_size.y + editor.config.padding
	case .Below:
	}

	target := Rect {
		min = rect_base,
		max = rect_base + size + editor.config.padding * 2,
	}

	if size == 0 {
		center    := rect_center(target)
		target.min = center
		target.max = center
	}
	animation_set_target(&popup.rect, target)
}

buffer_render :: proc(
	editor:         ^Editor,
	buffer:         ^Buffer_View,
	commands:       ^[dynamic]Draw_Command,
	popup_commands: ^[dynamic]Draw_Command,
	delta_time:     f32,
	rect:           Rect,
) {
	if rect.max.x <= rect.min.x || rect.max.y <= rect.min.y {
		return
	}

	active := buffer == editor.buffer

	text_commands := make([dynamic]Draw_Command, context.temp_allocator)

	append(commands, Draw_Command_Clip(rect))
	defer append(commands, DRAW_COMMAND_CLIP_DISABLE)

	height := rect.max.y - rect.min.y

	cell_size: [2]f32 = {
		la.round(get_glyph_info(&editor.font, 0).x_advance),
		la.round((f32(editor.font.ascender) - f32(editor.font.descender)) * editor.font.scale),
	}

	line_digits  := int(la.ceil(la.log10(1 + f32(buffer.btree.lines))))
	lines_width  := cell_size.x * f32(line_digits) + editor.config.padding
	gutter_width := lines_width + editor.config.padding + 1 + editor.config.padding

	buffer.visible_lines = max(1, int(la.floor(height / cell_size.y)))

	scroll := animation_update(&buffer.scroll_anim, delta_time, editor.config.scroll_animation_speed)

	primary          := buffer.selections[buffer.primary]
	primary_position := btree_index_to_position(&buffer.btree, primary.cursor, editor.config.tab_width)

	first_visble_line := int(la.floor(scroll))
	last_visible_line := min(int(buffer.btree.lines), first_visble_line + buffer.visible_lines + 3)

	position: Position = {
		line = first_visble_line,
	}
	start_index := btree_position_to_index(&buffer.btree, position,                      editor.config.tab_width)
	end_index   := btree_position_to_index(&buffer.btree, { line = last_visible_line, }, editor.config.tab_width)

	b := strings.builder_make(context.temp_allocator)
	btree_to_string(&buffer.btree, &b, start_index, end_index)
	text := strings.to_string(b)

	primary_match: Index = -1
	find_primary_match: {
		iter  := btree_iterator(&buffer.btree, index = primary.cursor)
		start := btree_iter(&iter) or_break find_primary_match

		back := false
		delim: rune
		switch start {
		case '{':
			delim = '}'
		case '[':
			delim = ']'
		case '(':
			delim = ')'

		case '}':
			delim = '{'
			back  = true
		case ']':
			delim = '['
			back  = true
		case ')':
			delim = '('
			back  = true
		case:
			break find_primary_match
		}

		balance := 0 if back else 1
		for r in btree_iter(&iter, back = back) {
			if iter.index < start_index || iter.index > end_index {
				break
			}
			if r == delim {
				balance -= 1
			} else if r == start {
				balance += 1
			}
			if balance == 0 {
				primary_match = iter.index
				break
			}
		}
	}

	highlighter := highlighter_create(text, editor.config.languages[buffer.language], context.temp_allocator)

	cursors := make(map[Index]int, context.temp_allocator)
	if active {
		for selection, i in buffer.selections {
			cursors[selection.cursor] = i
		}
	}

	line_diagnostic: Maybe(Diagnostic)

	if color := editor.config.theme[.Gutter].bg; color != 0 && active {
		draw_rect(commands,
			offset = { 0, cell_size.y * (f32(position.line) - scroll), } + rect.min,
			size   = { gutter_width - cell_size.x, cell_size.y * f32(last_visible_line - first_visble_line), },
			color  = color,
		)
	}

	render_text: for {
		index       := highlighter.index + start_index
		text, style := highlighter_advance(&highlighter)
		if style == .Invalid {
			break
		}

		start_column := position.column

		for char, sub_offset in text {
			defer index   += 1
			defer position = position_after(position, char, editor.config.tab_width)

			draw_gutter: if position.column == 0 {
				y := cell_size.y * (f32(position.line) - scroll) + la.round(f32(editor.font.ascender) * editor.font.scale)

				if y < 0 {
					break draw_gutter
				}

				text_color := editor.config.theme[.Gutter].fg
				line       := position.line

				if primary_position.line == position.line {
					text_color = editor.config.theme[.Cursor].bg
				} else if editor.config.relative_line_numbers && active {
					line = abs(primary_position.line - position.line) - 1
				}

				@(static)
				line_number_buf: [32]byte
				str := strconv.write_int(line_number_buf[:], i64(line + 1), base = 10)
				w   := measure_text(&editor.font, str)
				draw_text(&editor.font, commands, str, text_color, { lines_width - w, y, } + rect.min)

				draw_rect(commands,
					offset = {
						gutter_width - cell_size.x,
						cell_size.y * (f32(position.line) - scroll),
					} + rect.min,
					size   = { 1, cell_size.y, },
					color  = editor.config.theme[.Gutter].fg,
				)
			}

			style := style
			if id, ok := cursors[index]; ok {
				if id == buffer.primary {
					style = .Cursor
				} else {
					style = .Cursor_Secondary
				}
			}

			next_column := position_after(position, char, editor.config.tab_width).column
			for selection in buffer.selections {
				if !selection_contains(selection, index) {
					continue
				}

				draw_rect(commands,
					offset = {
						f32(position.column) * cell_size.x + gutter_width,
						cell_size.y * (f32(position.line) - scroll),
					} + rect.min,
					size   = cell_size * { f32(max(1, next_column - position.column)), 1, },
					color  = editor.config.theme[.Selection].bg,
				)
			}

			for diagnostic in buffer.diagnostics {
				if !selection_contains({ cursor = diagnostic.start, anchor = diagnostic.end, }, index) {
					continue
				}

				line_diagnostic = diagnostic

				style: Style_Key
				switch diagnostic.severity {
				case .Error:
					style = .Error
				case .Warning:
					style = .Warning
				case .Information:
					style = .Information
				case .Hint:
					style = .Hint
				}

				draw_rect(commands,
					offset = {
						f32(position.column) * cell_size.x + gutter_width,
						cell_size.y * (1 + f32(position.line) - scroll),
					} + rect.min,
					size   = { cell_size.x * f32(max(1, next_column - position.column)), 1, },
					color  = editor.config.theme[style].fg,
				)
			}

			if index == primary_match {
				draw_rect(commands,
					offset = {
						f32(position.column) * cell_size.x + gutter_width,
						cell_size.y * (f32(position.line) - scroll) + la.round(f32(editor.font.ascender - editor.font.descender) * editor.font.scale) - 1,
					} + rect.min,
					size   = { cell_size.x * f32(max(1, next_column - position.column)), 1, },
					color  = editor.config.theme[.Cursor].bg,
				)
			}

			if char == '\n' {
				if diagnostic, ok := line_diagnostic.?; ok {
					x := f32(position.column + 2) * cell_size.x + gutter_width
					y := cell_size.y * (f32(position.line) - scroll) + la.round(f32(editor.font.ascender) * editor.font.scale)
					x += draw_text(&editor.font, &text_commands, diagnostic.message, editor.config.theme[.Error].fg, { x, y, } + rect.min)
				}
				line_diagnostic = nil
				continue
			}

			if unicode.is_space(char) {
				continue
			}

			x := f32(position.column) * cell_size.x + gutter_width
			y := cell_size.y * (f32(position.line) - scroll) + la.round(f32(editor.font.ascender) * editor.font.scale)

			append(&text_commands, Draw_Command_Char {
				position = { x, y, } + rect.min,
				color    = editor.config.theme[style].fg,
				char     = char,
			})

			// TODO: line wrapping
		}

		if editor.config.theme[style].bg != 0 {
			draw_rect(commands,
				offset = {
					f32(start_column) * cell_size.x + gutter_width,
					cell_size.y * (f32(position.line) - scroll),
				} + rect.min,
				size   = { f32(position.column - start_column) * cell_size.x, cell_size.y, },
				color  = editor.config.theme[style].bg,

				border_radius = 2,
			)
		}
	}

	primary_render_position: [2]f32
	for &selection, i in buffer.selections {
		p := btree_index_to_position(&buffer.btree, selection.cursor, editor.config.tab_width)
		r := btree_get_rune(buffer.btree, selection.cursor)

		width := 1
		if r == '\t' {
			width = next_column_after_tab(p.column, editor.config.tab_width) - p.column
		}

		offset := [2]f32 {
			f32(p.column) * cell_size.x + gutter_width,
			cell_size.y * f32(p.line),
		}

		size   := cell_size
		size.x *= f32(width)

		target := Rect{ min = offset, max = offset + size, }

		if selection.anim == {} {
			center                    := rect_center(target)
			selection.anim.current.min = center
			selection.anim.current.max = center
		}

		animation_set_target(&selection.anim, target)

		cursor_rect := animation_update(&selection.anim, delta_time, editor.config.cursor_animation_speed)

		render_position := cursor_rect.min - { 0, scroll * cell_size.y, } + rect.min

		style := Style_Key.Cursor_Secondary
		if i == buffer.primary {
			style                   = .Cursor
			primary_render_position = render_position
		}

		if active {
			draw_rect(commands,
				offset        = render_position,
				size          = rect_size(cursor_rect),
				color         = editor.config.theme[style].bg,
				border_radius = 2,
			)
		} else {
			draw_rect(commands,
				offset        = render_position,
				size          = rect_size(cursor_rect),
				color         = 0,
				border_color  = editor.config.theme[style].bg,
				border_radius = 2,
				border_width  = 1,
			)
		}
	}

	append(commands, ..text_commands[:])

	if active {
		for &popup, location in editor.popups {
			popup_render(
				editor,
				&popup,
				popup_commands,
				delta_time,
				primary_render_position + { 0, cell_size.y, },
				location,
			)
		}
	} else {
		w := measure_text(&editor.font, buffer.path)
		draw_rect(
			commands,
			rect.max - { w, FONT_HEIGHT, } - editor.config.padding * 2,
			{ w, FONT_HEIGHT, } + editor.config.padding * 2,
			editor.config.theme[.Popup_Background].fg,
			border_radius = 4,
			border_width  = 2,
			border_color  = editor.config.theme[.Popup_Border].fg,
			blur_radius   = f32(editor.config.blur_strength),
		)
		draw_text(
			&editor.font,
			commands,
			buffer.path,
			editor.config.theme[.Ui_Text].fg,
			rect.max - { w, 0, } - editor.config.padding,
		)
	}
}

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
		&editor.font,
		commands,
		text[:input.cursor],
		editor.config.theme[.Ui_Text].fg,
		position,
	)
	animation_set_target(&input.cursor_anim, width)
	anim   := animation_update(&input.cursor_anim, delta_time, editor.config.cursor_animation_speed)
	height := (f32(editor.font.ascender) - f32(editor.font.descender)) * editor.font.scale
	draw_rect(commands,
		offset = position + { anim, -(height + f32(editor.font.descender) * editor.font.scale), },
		size   = { 1, height, },
		color  = editor.config.theme[.Ui_Text].fg,
	)
	width += draw_text(
		&editor.font,
		commands,
		text[input.cursor:],
		editor.config.theme[.Ui_Text].fg,
		position + { width, 0, },
	)

	return
}

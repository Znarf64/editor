package editor

Event :: union {
	Event_Window_Close,
	Event_Window_Resize,
	
	Event_Input_Key,
	Event_Input_Codepoint,
	Event_Input_Mouse_Move,
	Event_Input_Mouse_Button,
	Event_Input_Scroll,
}

Event_Window_Close :: struct {}

Event_Window_Resize :: struct {
	size: [2]int,
}

Event_Input_Codepoint :: struct {
	codepoint: rune,
}

Action :: enum {
	Up,
	Down,
	Repeat,
}

Event_Input_Key :: struct {
	action:    Action,
	key:       Key,
	scancode:  int,
	modifiers: Modifiers,
}

Event_Input_Mouse_Move :: struct {
	position: [2]int,
}

Event_Input_Mouse_Button :: struct {
	index:  int,
	action: Action,
}

Event_Input_Scroll :: struct {
	delta: [2]f32,
}

Backend :: struct {
	poll_events: proc(backend: ^Backend) -> []Event,
	draw:        proc(backend: ^Backend, instances: []Instance),
	set_title:   proc(backend: ^Backend, title: string),
	destroy:     proc(backend: ^Backend),
	_events:     [dynamic]Event,
}

@(require_results)
backend_init :: proc() -> (backend: ^Backend) {
	when ODIN_OS == .Linux && false {
		backend = backend_init_wayland()
		if backend != nil {
			return
		}
	}
	return backend_init_glfw()
}

package editor

import "base:runtime"

import strings "core:strings"

import gl   "vendor:OpenGL"
import glfw "vendor:glfw"

Backend_Glfw :: struct {
	using base:        Backend,
	window:            glfw.WindowHandle,
	current_key_event: int,
}

@(require_results)
backend_init_glfw :: proc() -> ^Backend {
	backend := new(Backend_Glfw)
	if _backend_init_glfw(backend) {
		return backend
	} else {
		free(backend)
		return nil
	}
}

@(require_results)
_backend_init_glfw :: proc(backend: ^Backend_Glfw) -> (ok: bool) {
	glfw.Init() or_return
	defer if !ok {
		glfw.Terminate()
	}

	backend.window = glfw.CreateWindow(900, 600, "", nil, nil)
	(backend.window != nil) or_return

	glfw.MakeContextCurrent(backend.window)

	gl.load_up_to(4, 6, glfw.gl_set_proc_address)

	backend.poll_events = proc(backend: ^Backend_Glfw) -> []Event {
		glfw.PollEvents()
		events := backend._events[:]
		clear(&backend._events)
		return events
	}
	backend.draw = proc(backend: ^Backend_Glfw, instances: []Instance) {
		glfw.SwapBuffers(backend.window)
	}
	backend.set_title = proc(backend: ^Backend_Glfw, title: string) {
		glfw.SetWindowTitle(backend.window, strings.clone_to_cstring(title, context.temp_allocator))
	}
	backend.destroy = proc(backend: ^Backend_Glfw) {
		glfw.DestroyWindow(backend.window)
		glfw.Terminate()
		free(backend)
	}

	glfw.SetWindowUserPointer(backend.window, backend)

	glfw.SetFramebufferSizeCallback(backend.window, proc "c" (window: glfw.WindowHandle, width, height: i32) {
		context = runtime.default_context()

		backend := cast(^Backend)glfw.GetWindowUserPointer(window)
		append(&backend._events, Event_Window_Resize {
			size = { int(width), int(height), },
		})
	})

	glfw.SetWindowCloseCallback(backend.window, proc "c" (window: glfw.WindowHandle) {
		context = runtime.default_context()

		backend := cast(^Backend)glfw.GetWindowUserPointer(window)
		append(&backend._events, Event_Window_Close {})
	})

	glfw.SetScrollCallback(backend.window, proc "c" (window: glfw.WindowHandle, xoffset, yoffset: f64) {
		context = runtime.default_context()

		backend := cast(^Backend)glfw.GetWindowUserPointer(window)
		append(&backend._events, Event_Input_Scroll {
			delta = { f32(xoffset), f32(yoffset), },
		})
	})

	glfw.SetCharCallback(backend.window, proc "c" (window: glfw.WindowHandle, codepoint: rune) {
		context = runtime.default_context()

		backend := cast(^Backend_Glfw)glfw.GetWindowUserPointer(window)
		append(&backend._events, Event_Input_Codepoint {
			source    = backend.current_key_event,
			codepoint = codepoint,
		})
	})

	glfw.SetKeyCallback(backend.window, proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: i32) {
		context = runtime.default_context()

		backend := cast(^Backend_Glfw)glfw.GetWindowUserPointer(window)

		backend.current_key_event += 1

		event: Event_Input_Key = {
			id       = backend.current_key_event,
			scancode = int(scancode),
		}

		switch key {
		case glfw.KEY_0 ..= glfw.KEY_9:
			event.key = ._0 + Key(key - glfw.KEY_0)
		case glfw.KEY_A ..= glfw.KEY_Z:
			event.key = .A + Key(key - glfw.KEY_A)
		case glfw.KEY_ESCAPE:
			event.key = .Escape
		case glfw.KEY_ENTER:
			event.key = .Enter
		case glfw.KEY_SPACE:
			event.key = .Space
		case:
			return
		}

		switch action {
		case glfw.PRESS:
			event.action = .Down
		case glfw.RELEASE:
			event.action = .Up
		case glfw.REPEAT:
			event.action = .Repeat
		}

		if glfw.MOD_SHIFT & mods != 0 {
			event.modifiers |= { .Shift, }
		}
		if glfw.MOD_CONTROL & mods != 0 {
			event.modifiers |= { .Control, }
		}
		if glfw.MOD_ALT & mods != 0 {
			event.modifiers |= { .Alt, }
		}

		append(&backend._events, event)
	})

	glfw.SetCursorPosCallback(backend.window, proc "c" (window: glfw.WindowHandle, xpos, ypos: f64) {
		context = runtime.default_context()

		backend := cast(^Backend)glfw.GetWindowUserPointer(window)
		append(&backend._events, Event_Input_Mouse_Move {
			position = { int(xpos), int(ypos), },
		})
	})

	glfw.SetMouseButtonCallback(backend.window, proc "c" (window: glfw.WindowHandle, button, action, mods: i32) {
		context = runtime.default_context()

		backend := cast(^Backend)glfw.GetWindowUserPointer(window)

		event: Event_Input_Mouse_Button = {
			index = int(button),
		}
		switch action {
		case glfw.PRESS:
			event.action = .Down
		case glfw.RELEASE:
			event.action = .Up
		case glfw.REPEAT:
			event.action = .Repeat
		}
		append(&backend._events, event)
	})

	return true
}

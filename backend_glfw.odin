package editor

import "base:runtime"

import strings "core:strings"

import gl   "vendor:OpenGL"
import glfw "vendor:glfw"

@(require_results)
backend_init_glfw :: proc(backend: ^Backend) -> (ok: bool) {
	Backend_Glfw :: struct {
		window: glfw.WindowHandle,
	}

	data        := new(Backend_Glfw)
	backend.data = data

	glfw.Init() or_return
	defer if !ok {
		glfw.Terminate()
	}

	data.window = glfw.CreateWindow(900, 600, "Editor", nil, nil)
	(data.window != nil) or_return

	glfw.MakeContextCurrent(data.window)

	gl.load_up_to(4, 6, glfw.gl_set_proc_address)

	backend.poll_events = proc(backend: ^Backend) -> []Event {
		glfw.PollEvents()
		events := backend._events[:]
		clear(&backend._events)
		return events
	}
	backend.draw = proc(backend: ^Backend, instances: []Instance) {
		data := (^Backend_Glfw)(backend.data)
		glfw.SwapBuffers(data.window)
	}
	backend.set_title = proc(backend: ^Backend, title: string) {
		data := (^Backend_Glfw)(backend.data)
		glfw.SetWindowTitle(data.window, strings.clone_to_cstring(title, context.temp_allocator))
	}
	backend.destroy = proc(backend: ^Backend) {
		data := (^Backend_Glfw)(backend.data)
		glfw.DestroyWindow(data.window)
		glfw.Terminate()
	}

	glfw.SetWindowUserPointer(data.window, backend)

	glfw.SetFramebufferSizeCallback(data.window, proc "c" (window: glfw.WindowHandle, width, height: i32) {
		context = runtime.default_context()

		backend := cast(^Backend)glfw.GetWindowUserPointer(window)
		append(&backend._events, Event_Window_Resize {
			size = { int(width), int(height), },
		})
	})

	glfw.SetWindowCloseCallback(data.window, proc "c" (window: glfw.WindowHandle) {
		context = runtime.default_context()

		backend := cast(^Backend)glfw.GetWindowUserPointer(window)
		append(&backend._events, Event_Window_Close {})
	})

	glfw.SetScrollCallback(data.window, proc "c" (window: glfw.WindowHandle, xoffset, yoffset: f64) {
		context = runtime.default_context()

		backend := cast(^Backend)glfw.GetWindowUserPointer(window)
		append(&backend._events, Event_Input_Scroll {
			delta = { f32(xoffset), f32(yoffset), },
		})
	})

	glfw.SetCharCallback(data.window, proc "c" (window: glfw.WindowHandle, codepoint: rune) {
		context = runtime.default_context()

		backend := cast(^Backend)glfw.GetWindowUserPointer(window)
		append(&backend._events, Event_Input_Codepoint {
			codepoint = codepoint,
		})
	})

	glfw.SetKeyCallback(data.window, proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: i32) {
		context = runtime.default_context()

		backend := cast(^Backend)glfw.GetWindowUserPointer(window)

		event: Event_Input_Key = {
			scancode  = int(scancode),
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

	glfw.SetCursorPosCallback(data.window, proc "c" (window: glfw.WindowHandle, xpos, ypos: f64) {
		context = runtime.default_context()

		backend := cast(^Backend)glfw.GetWindowUserPointer(window)
		append(&backend._events, Event_Input_Mouse_Move {
			position = { int(xpos), int(ypos), },
		})
	})

	glfw.SetMouseButtonCallback(data.window, proc "c" (window: glfw.WindowHandle, button, action, mods: i32) {
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

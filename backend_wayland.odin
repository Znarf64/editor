#+build linux
package editor

import "base:runtime"

import "core:fmt"
import "core:strings"
import "core:sys/linux"

import gl "vendor:OpenGL"

import wl  "vendor/odin-wayland"
import xdg "vendor/odin-wayland/xdg"

import egl "vendor/egl"
import xkb "vendor/odin-xkbcommon"

Backend_Wayland :: struct {
	using base:          Backend,

	display:            ^wl.display,
	registry:           ^wl.registry,
	compositor:         ^wl.compositor,
	wl_surface:         ^wl.surface,

	wm_base:            ^xdg.wm_base,
	xdg_surface:        ^xdg.surface,
	toplevel:           ^xdg.toplevel,

	width, height:       int,

	configured:          bool,
	egl_initialized:     bool,

	egl_display:         egl.Display,
	egl_config:          egl.Config,
	egl_window:         ^wl.egl_window,
	egl_surface:         egl.Surface,
	egl_context:         egl.Context,

	xkb_context:        ^xkb.ctx,
	xkb_keymap:         ^xkb.keymap,
	xkb_state:          ^xkb.state,
}

@(require_results)
backend_init_wayland :: proc() -> (backend: ^Backend) {
	b  := new(Backend_Wayland)
	if _backend_init_wayland(b) {
		return b
	} else {
		free(b)
		return nil
	}
}

@(require_results)
_backend_init_wayland :: proc(backend: ^Backend_Wayland) -> (ok: bool) {
	backend.xkb_context = xkb.context_new({})

	backend.display = wl.display_connect(nil)
	(backend.display != nil) or_return
	defer if !ok {
		wl.display_disconnect(backend.display)
	}

	backend.registry = wl.display_get_registry(backend.display)
	defer if !ok {
		wl.registry_destroy(backend.registry)
	}

	@(static)
	pointer_listener: wl.pointer_listener = {
		enter = proc "c" (
			data:      rawptr,
			pointer:  ^wl.pointer,
			serial:    uint,
			surface:  ^wl.surface,
			surface_x: wl.fixed_t,
			surface_y: wl.fixed_t,
		) {
			data   := (^Backend_Wayland)(data)
			context = runtime.default_context()

			append(&data._events, Event_Input_Mouse_Move {
				position = { int(surface_x >> 8), int(surface_y >> 8), },
			})
		},
		leave = proc "c" (
			data:     rawptr,
			pointer: ^wl.pointer,
			serial:   uint,
			surface: ^wl.surface,
		) {},
		motion = proc "c" (
			data:      rawptr,
			pointer:  ^wl.pointer,
			time:      uint,
			surface_x: wl.fixed_t,
			surface_y: wl.fixed_t,
		) {
			data   := (^Backend_Wayland)(data)
			context = runtime.default_context()

			append(&data._events, Event_Input_Mouse_Move {
				position = { int(surface_x >> 8), int(surface_y >> 8), },
			})
		},
		axis = proc "c" (
			data:     rawptr,
			pointer: ^wl.pointer,
			time:     uint,
			axis:     wl.pointer_axis,
			value:    wl.fixed_t,
		) {
			data   := (^Backend_Wayland)(data)
			context = runtime.default_context()

			switch axis {
			case .vertical_scroll:
				append(&data._events, Event_Input_Scroll {
					delta = { 0, -f32(value) / (10 << 8), },
				})
			case .horizontal_scroll:
				append(&data._events, Event_Input_Scroll {
					delta = { f32(value) / (10 << 8), 0, },
				})
			}
		},
		button = proc "c" (
			data:     rawptr,
			pointer: ^wl.pointer,
			serial:   uint,
			time:     uint,
			button:   uint,
			state:    wl.pointer_button_state,
		) {
			data   := (^Backend_Wayland)(data)
			context = runtime.default_context()

			event: Event_Input_Mouse_Button = {
				index = int(button),
			}

			switch state {
			case .released:
				event.action = .Up
			case .pressed:
				event.action = .Down
			}

			append(&data._events, event)
		},
	}

	@(static)
	keyboard_listener: wl.keyboard_listener = {
		keymap = proc "c" (
			data:      rawptr,
			keyboard: ^wl.keyboard,
			format_:   wl.keyboard_keymap_format,
			fd:        int,
			size:      uint,
		) {
			data   := (^Backend_Wayland)(data)
			context = runtime.default_context()

			addr, err := linux.mmap(0, size, { .READ, }, { .PRIVATE, }, linux.Fd(fd))
			assert(err == nil)
			defer linux.munmap(addr, size)

			xkb.state_unref(data.xkb_state)
			xkb.keymap_unref(data.xkb_keymap)

			data.xkb_keymap = xkb.keymap_new_from_string(data.xkb_context, cstring(addr), .Text_V1, {})
			data.xkb_state  = xkb.state_new(data.xkb_keymap)
		},
		enter = proc "c" (
			data:      rawptr,
			keyboard: ^wl.keyboard,
			serial:    uint,
			surface:  ^wl.surface,
			keys:      wl.array,
		) {
			
		},
		leave = proc "c" (data: rawptr, keyboard: ^wl.keyboard, serial: uint, surface: ^wl.surface) {
			
		},
		key = proc "c" (
			data:      rawptr,
			keyboard: ^wl.keyboard,
			serial:    uint,
			time:      uint,
			key:       uint,
			state:     wl.keyboard_key_state,
		) {
			data   := (^Backend_Wayland)(data)
			context = runtime.default_context()

			key := xkb.keycode_t(key + 8)

			syms: ^xkb.keysym_t
			n_syms := xkb.state_key_get_syms(data.xkb_state, key, &syms)
			for sym in ([^]xkb.keysym_t)(syms)[:n_syms] {
				event: Event_Input_Key = {
					scancode = int(key),
				}
				switch state {
				case .released:
					event.action = .Up
				case .pressed:
					event.action = .Down
				case .repeated:
					event.action = .Repeat
				}
				switch sym {
				case xkb.KEY_0 ..= xkb.KEY_9:
					event.key = ._0 + Key(sym - xkb.KEY_0)
				case xkb.KEY_a ..= xkb.KEY_z:
					event.key = .A + Key(sym - xkb.KEY_a)
				case xkb.KEY_Escape:
					event.key = .Escape
				case xkb.KEY_Return:
					event.key = .Enter
				}
				append(&data._events, event)
			}

			switch state {
			case .released:
				xkb.state_update_key(data.xkb_state, key, .Up)
				return
			case .repeated:
				if xkb.keymap_key_repeats(data.xkb_keymap, key) == 0 {
					break
				}
			case .pressed:
				xkb.state_update_key(data.xkb_state, key, .Down)
			}

			if codepoint := xkb.state_key_get_utf32(data.xkb_state, key); codepoint != 0 {
				append(&data._events, Event_Input_Codepoint {
					codepoint = rune(codepoint),
				})
			} else {
				buf: [256]i8
				n := xkb.state_key_get_utf8(data.xkb_state, key, &buf[0], size_of(buf))
				for r in transmute(string)buf[:n] {
					append(&data._events, Event_Input_Codepoint {
						codepoint = r,
					})
				}
			}
		},
		modifiers = proc "c" (
			data:           rawptr,
			keyboard:      ^wl.keyboard,
			serial:         uint,
			mods_depressed: uint,
			mods_latched:   uint,
			mods_locked:    uint,
			group:          uint,
		) {
			data := (^Backend_Wayland)(data)
			xkb.state_update_mask(
				data.xkb_state,
				i32(mods_depressed),
				i32(mods_latched),
				i32(mods_locked),
				0,
				0,
				i32(group),
			)
		},
		repeat_info = proc "c" (data: rawptr, keyboard: ^wl.keyboard, rate: int, delay: int) {
			
		},
	}

	@(static)
	seat_listener: wl.seat_listener = {
		capabilities = proc "c" (data: rawptr, seat: ^wl.seat, capabilities: wl.seat_capability) {
			if capabilities & .pointer != nil {
				pointer := wl.seat_get_pointer(seat)
				wl.pointer_add_listener(pointer, &pointer_listener, data)
			}
			if capabilities & .keyboard != nil {
				keyboard := wl.seat_get_keyboard(seat)
				wl.keyboard_add_listener(keyboard, &keyboard_listener, data)
			}
		},
	}

	@(static)
	wm_base_listener: xdg.wm_base_listener = {
		ping = proc "c" (data: rawptr, wm_base: ^xdg.wm_base, serial: uint) {
			xdg.wm_base_pong(wm_base, serial)
		},
	}

	@(static)
	registry_listener: wl.registry_listener = {
		global = proc "c" (
			data:      rawptr,
			registry: ^wl.registry,
			name:      uint,
			interface: cstring,
			version:   uint,
		) {
			data := (^Backend_Wayland)(data)

			switch interface {
			case "xdg_wm_base":
				data.wm_base = cast(^xdg.wm_base)wl.registry_bind(registry, name, &xdg.wm_base_interface, 1)
				xdg.wm_base_add_listener(data.wm_base, &wm_base_listener, data)
			case "wl_compositor":
				data.compositor = cast(^wl.compositor)wl.registry_bind(registry, name, &wl.compositor_interface, 1)
			case "wl_seat":
				seat := cast(^wl.seat)wl.registry_bind(registry, name, &wl.seat_interface, 1)
				wl.seat_add_listener(seat, &seat_listener, data)
			}
		},
		global_remove = proc "c" (data: rawptr, registry: ^wl.registry, name: uint) {
			// data := (^Backend_Wayland)(data)
		},
	}
	wl.registry_add_listener(backend.registry, &registry_listener, backend)

	wl.display_roundtrip(backend.display)

	if backend.compositor == nil {
		fmt.eprintln("no compositor")
		return false
	}

	if backend.wm_base == nil {
		fmt.eprintln("no wm_base")
		return false
	}

	backend.wl_surface  = wl.compositor_create_surface(backend.compositor)
	backend.xdg_surface = xdg.wm_base_get_xdg_surface(backend.wm_base, backend.wl_surface)

	@(static)
	xdg_surface_listener: xdg.surface_listener = {
		configure = proc "c" (data: rawptr, surface: ^xdg.surface, serial: uint) {
			data := (^Backend_Wayland)(data)

			xdg.surface_ack_configure(data.xdg_surface, serial)
			wl.surface_commit(data.wl_surface)

			data.configured = true
		},
	}
	xdg.surface_add_listener(backend.xdg_surface, &xdg_surface_listener, backend)

	backend.toplevel = xdg.surface_get_toplevel(backend.xdg_surface)

	@(static)
	toplevel_listener: xdg.toplevel_listener = {
		configure = proc "c" (
			data:      rawptr,
			toplevel: ^xdg.toplevel,
			width:     int,
			height:    int,
			states:    wl.array,
		) {
			data   := (^Backend_Wayland)(data)
			context = runtime.default_context()

			width  := max(width, 1)
			height := max(height, 1)

			if width == data.width || height == data.height {
				return
			}

			if data.egl_initialized {
				wl.egl_window_resize(data.egl_window, width, height, 0, 0)
			}

			append(&data._events, Event_Window_Resize {
				size = { width, height },
			})

			data.width  = width
			data.height = height
		},
		close = proc "c" (data: rawptr, toplevel: ^xdg.toplevel) {
			data   := (^Backend_Wayland)(data)
			context = runtime.default_context()

			append(&data._events, Event_Window_Close {})
		},
	}
	xdg.toplevel_add_listener(backend.toplevel, &toplevel_listener, backend)

	wl.surface_commit(backend.wl_surface)

	wl.display_roundtrip(backend.display)

	if !backend.configured {
		fmt.eprintln("surface not configured")
		return false
	}

	init_egl :: proc(backend: ^Backend_Wayland) -> bool {
		backend.egl_display = egl.GetDisplay(cast(egl.NativeDisplayType)backend.display)
		if backend.egl_display == nil {
			fmt.println("[!] eglGetDisplay: failed to create EGL display")
			return false
		}

		major, minor: i32
		if !egl.Initialize(backend.egl_display, &major, &minor) {
			fmt.println("[!] eglGetDisplay: failed to initialize EGL display")
			return false
		}

		if !egl.BindAPI(egl.OPENGL_API) {
			fmt.println("[!] eglBindAPI: failed to bind OpenGL API")
			return false
		}

		num_configs: i32
		if !egl.GetConfigs(backend.egl_display, nil, 0, &num_configs) {
			fmt.println("[!] eglGetConfigs: failed to get number of EGL configs")
			return false
		}

		config_attribs := [?]i32{
			egl.SURFACE_TYPE,    egl.WINDOW_BIT,
			egl.RENDERABLE_TYPE, egl.OPENGL_BIT,
			egl.RED_SIZE,        8,
			egl.GREEN_SIZE,      8,
			egl.BLUE_SIZE,       8,
			egl.NONE,
		}

		if !egl.ChooseConfig(backend.egl_display, &config_attribs[0], &backend.egl_config, 1, &num_configs) {
			fmt.println("[!] eglChooseConfig: failed to get EGL config")
			return false
		}

		backend.egl_window  = wl.egl_window_create(backend.wl_surface, backend.width, backend.height)
		backend.egl_surface = egl.CreateWindowSurface(backend.egl_display, backend.egl_config, cast(egl.NativeWindowType)backend.egl_window, nil)

		context_attribs := [?]i32{
			egl.CONTEXT_MAJOR_VERSION, 4,
			egl.CONTEXT_MINOR_VERSION, 6,
			egl.CONTEXT_OPENGL_PROFILE_MASK, egl.CONTEXT_OPENGL_CORE_PROFILE_BIT,
			egl.NONE,
		}

		backend.egl_context = egl.CreateContext(backend.egl_display, backend.egl_config, egl.NO_CONTEXT, &context_attribs[0])
		if backend.egl_context == nil {
			fmt.println("[!] eglCreateContext: failed to create EGL context")
			return false
		}

		if !egl.MakeCurrent(backend.egl_display, backend.egl_surface, backend.egl_surface, backend.egl_context) {
			fmt.println("[!] eglMakeCurrent: failed to activate EGL context")
			return false
		}

		gl.load_up_to(4, 6, egl.gl_set_proc_address)

		backend.egl_initialized = true

		return true
	}

	init_egl(backend) or_return

	backend.poll_events = proc(backend: ^Backend_Wayland) -> []Event {
		wl.display_flush(backend.display)
		wl.display_dispatch_pending(backend.display)

		events := backend._events[:]
		clear(&backend._events)
		return events
	}
	backend.draw = proc(backend: ^Backend_Wayland, instances: []Instance) {
		egl.SwapBuffers(backend.egl_display, backend.egl_surface)
	}
	backend.set_title = proc(backend: ^Backend_Wayland, title: string) {
		xdg.toplevel_set_title(backend.toplevel, strings.clone_to_cstring(title, context.temp_allocator))
	}
	backend.destroy = proc(backend: ^Backend_Wayland) {
		xkb.state_unref(backend.xkb_state)
		xkb.keymap_unref(backend.xkb_keymap)
		xkb.context_unref(backend.xkb_context)
		free(backend)
	}

	return true
}

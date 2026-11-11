package editor

import la "core:math/linalg"

Multi_Window :: struct {
	children: [dynamic]Window,
	focused:  int,
	vertical: bool,
}

Window :: union {
	Multi_Window,
	Buffer_View,
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
					position = la.round(origin),
					size     = size,
					color    = editor.config.theme[.Gutter].fg,
				)
			}
			window_render(editor, commands, popup_commands, &w, delta_time, { min = origin, max = origin + extent, })
			origin[axis] += per_window + gap
		}
	case Buffer_View:
		buffer_render(editor, &w, commands, popup_commands, delta_time, rect_round(rect))
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
				editor.should_close = true
				return
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

package editor

import runtime "base:runtime"

import unicode "core:unicode"
import utf8    "core:unicode/utf8"

Highlighter_Kind :: enum {
	Text,
	C_Like,
}

Highlighter :: struct {
	index:    Index,
	_text:    string,
	keywords: map[string]Style_Key,

	kind:     Highlighter_Kind,
}

@(require_results)
highlighter_create :: proc(text: string, config: Language_Config, allocator: runtime.Allocator) -> (highlighter: Highlighter) {
	highlighter._text = text

	highlighter.kind = .C_Like

	highlighter.keywords = make(map[string]Style_Key, allocator)

	for k in config.keywords {
		highlighter.keywords[k] = .Keyword
	}
	for c in config.constants {
		highlighter.keywords[c] = .Constant
	}
	for t in config.types {
		highlighter.keywords[t] = .Type
	}

	if len(highlighter.keywords) == 0 {
		highlighter.kind = .Text
	}

	return
}

@(require_results)
highlighter_advance :: proc(h: ^Highlighter) -> (text: string, style: Style_Key) {
	text  = h._text
	style = _highlighter_advance(h)
	text  = text[:uintptr(raw_data(h._text)) - uintptr(raw_data(text))]
	return
}

@(require_results)
_highlighter_advance :: proc(h: ^Highlighter) -> Style_Key {
	if h._text == "" {
		return nil
	}

	if h.kind == .Text {
		h._text = h._text[len(h._text):]
		return .Ident
	}

	@(require_results)
	peek_rune :: proc(h: ^Highlighter) -> (r: rune, ok: bool) {
		r, _ = utf8.decode_rune(h._text)
		return r, r != utf8.RUNE_ERROR
	}

	advance_rune :: proc(h: ^Highlighter) -> (r: rune, ok: bool) {
		n: int
		r, n     = utf8.decode_rune(h._text)
		h._text  = h._text[n:]
		h.index += 1
		return r, r != utf8.RUNE_ERROR
	}

	advance_token :: proc(h: ^Highlighter) -> Style_Key {
		text := h._text

		has_upper, has_lower: bool
		for r in peek_rune(h) {
			switch r {
			case '0' ..= '9', '_':
				advance_rune(h)
				continue
			case 'a' ..= 'z':
				has_lower = true
				advance_rune(h)
				continue
			case 'A' ..= 'Z':
				has_upper = true
				advance_rune(h)
				continue
			}

			if unicode.is_digit(r) {
				advance_rune(h)
				continue
			}

			if unicode.is_upper(r) {
				advance_rune(h)
				has_upper = true
				continue
			}

			if unicode.is_lower(r) {
				advance_rune(h)
				has_lower = true
				continue
			}

			break
		}

		text = text[:uintptr(raw_data(h._text)) - uintptr(raw_data(text))]

		for r in peek_rune(h) {
			switch r {
			case ' ', '\t':
				advance_rune(h)
				continue
			}
			break
		}

		if r, _ := peek_rune(h); r == '(' {
			return .Function
		}

		if style, ok := h.keywords[text]; ok {
			return style
		}

		if has_upper && has_lower {
			return .Type
		}

		if has_upper {
			return .Constant
		}

		return .Ident
	}

	r, ok := peek_rune(h)
	if !ok {
		return .Ident
	}

	switch r {
	case '0' ..= '9':
		advance_token(h)
		return .Number
	case '#':
		advance_rune(h)
		advance_token(h)
		return .Directive
	case 'a' ..= 'z', '_':
		return advance_token(h)
	case 'A' ..= 'Z':
		return advance_token(h)
	case '/':
		advance_rune(h)
		if r, _ := peek_rune(h); r == '/' {
			for r in peek_rune(h) {
				if r == '\n' {
					break
				} else {
					advance_rune(h)
				}
			}
			return .Comment
		}

		return .Operator
	case ':':
		advance_rune(h)

		switch r, _ := peek_rune(h); r {
		case ':', '=':
			advance_rune(h)
			return .Operator
		}

		return .Ident
	case '+', '*', '=', '~', '&', '|', '^', '@', '>', '<', '!', '%':
		advance_rune(h)
		return .Operator
	case '-':
		advance_rune(h)

		if r, _ := peek_rune(h); r == '>' {
			advance_rune(h)
			return .Ident
		}

		return .Operator
	case '.':
		advance_rune(h)
		switch r, _ := peek_rune(h); r {
		case '0' ..= '9':
			advance_token(h)
			return .Number
		case '.', '?':
			advance_rune(h)

			if r, _ := peek_rune(h); r == '.' {
				advance_rune(h)
			}
			if r, _ := peek_rune(h); r == '.' {
				advance_rune(h)
			}

			return .Operator
		}

		return .Ident

	case '"':
		advance_rune(h)
		parse_string: for r in peek_rune(h) {
			switch r {
			case '\\':
				advance_rune(h)
				advance_rune(h)
			case '"':
				advance_rune(h)
				break parse_string
			case '\n':
				break parse_string
			case:
				advance_rune(h)
			}
		}
		return .String
	case '`':
		advance_rune(h)
		for r in peek_rune(h) {
			defer advance_rune(h)
			if r == '`' {
				break
			}
		}
		return .String
	case '\'':
		advance_rune(h)
		parse_string_single_quote: for r in peek_rune(h) {
			switch r {
			case '\\':
				advance_rune(h)
				advance_rune(h)
			case '\'':
				advance_rune(h)
				break parse_string_single_quote
			case '\n':
				break parse_string_single_quote
			case:
				advance_rune(h)
			}
		}
		return .String
	case:
		if unicode.is_letter(r) {
			return advance_token(h)
		}
		if unicode.is_digit(r) {
			advance_token(h)
			return .Number
		}
		advance_rune(h)
		return .Ident
	}
}

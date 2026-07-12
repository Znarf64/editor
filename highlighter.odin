package editor

import unicode "core:unicode"
import utf8    "core:unicode/utf8"

Highlighter :: struct {
	pos:      int,
	text:     string,
	keywords: map[string]Style_Key,
}

@(require_results)
highlighter_advance :: proc(h: ^Highlighter) -> Style_Key {
	if h.pos >= len(h.text) {
		return nil
	}

	advance_token :: proc(h: ^Highlighter) -> Style_Key {
		start := h.pos

		has_upper, has_lower: bool
		for r in h.text[h.pos:] {
			switch r {
			case '0' ..= '9', '_':
				h.pos += 1
				continue
			case 'a' ..= 'z':
				has_lower = true
				h.pos    += 1
				continue
			case 'A' ..= 'Z':
				has_upper = true
				h.pos    += 1
				continue
			}

			if unicode.is_digit(r) {
				_, n  := utf8.encode_rune(r)
				h.pos += n
				continue
			}

			if unicode.is_upper(r) {
				_, n     := utf8.encode_rune(r)
				h.pos    += n
				has_upper = true
				continue
			}

			if unicode.is_lower(r) {
				_, n     := utf8.encode_rune(r)
				h.pos    += n
				has_lower = true
				continue
			}

			break
		}

		if style, ok := h.keywords[h.text[start:h.pos]]; ok {
			return style
		}

		for h.pos < len(h.text) {
			switch h.text[h.pos] {
			case ' ', '\t':
				h.pos += 1
				continue
			}
			break
		}

		if h.pos < len(h.text) {
			if h.text[h.pos] == '(' {
				return .Function
			}
		}

		if has_upper && has_lower {
			return .Type
		}

		if has_upper {
			return .Constant
		}

		return .Ident
	}

	r, n := utf8.decode_rune(h.text[h.pos:])
	switch r {
	case '0' ..= '9':
		advance_token(h)
		return .Number
	case '#':
		h.pos += 1
		advance_token(h)
		return .Directive
	case 'a' ..= 'z', '_':
		return advance_token(h)
	case 'A' ..= 'Z':
		return advance_token(h)
	case '/':
		h.pos += 1
		if h.pos >= len(h.text) {
			return .Operator
		}

		if h.text[h.pos] == '/' {
			for h.pos < len(h.text) {
				if h.text[h.pos] == '\n' {
					break
				} else {
					h.pos += 1
				}
			}
			return .Comment
		}

		return .Operator
	case ':':
		h.pos += 1
		if h.pos >= len(h.text) {
			return .Ident
		}

		switch h.text[h.pos] {
		case ':', '=':
			h.pos += 1
			return .Operator
		}

		return .Ident
	case '+', '*', '=', '~', '&', '|', '^', '@', '>', '<', '!', '%':
		h.pos += 1
		return .Operator
	case '-':
		h.pos += 1
		if h.pos >= len(h.text) {
			return .Operator
		}

		if h.text[h.pos] == '>' {
			h.pos += 1
			return .Ident
		}

		return .Operator
	case '.':
		h.pos += 1
		if h.pos >= len(h.text) {
			return .Ident
		}

		switch h.text[h.pos] {
		case '0' ..= '9':
			advance_token(h)
			return .Number
		case '.', '?':
			h.pos += 1
			return .Operator
		}

		return .Ident

	case '"':
		h.pos += 1
		parse_string: for h.pos < len(h.text) {
			defer h.pos += 1
			switch h.text[h.pos] {
			case '\\':
				h.pos += 1
			case '"':
				break parse_string
			case '\n':
				h.pos -= 1
				break parse_string
			}
		}
		return .String
	case '\'':
		h.pos += 1
		parse_string_single_quote: for h.pos < len(h.text) {
			defer h.pos += 1
			switch h.text[h.pos] {
			case '\\':
				h.pos += 1
			case '\'':
				break parse_string_single_quote
			case '\n':
				h.pos -= 1
				break parse_string_single_quote
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
		h.pos += n
		return .Ident
	}
}

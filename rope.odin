package editor

import runtime "base:runtime"

import bytes   "core:bytes"
import fmt     "core:fmt"
import strings "core:strings"
import utf8    "core:unicode/utf8"

Rope_Index :: bit_field int {
	index: int  | size_of(int) * 8 - 1,
	leaf:  bool | 1,
}

Rope_Node :: struct {
	weight: int,
	lines:  int,
	l, r:   Rope_Index,
	parent: int,
}

ROPE_LEAF_SIZE :: 16
Rope_Leaf      :: [ROPE_LEAF_SIZE]u8

Rope :: struct {
	root:      Rope_Index,
	len:       int,
	lines:     int,
	tab_width: int,
	nodes:     [dynamic]Rope_Node,
	leaves:    [dynamic]Rope_Leaf,
}

@(require_results)
rope_to_string :: proc(rope: Rope, allocator: runtime.Allocator) -> string {
	b := strings.builder_make(0, rope.len, allocator)

	_rope_to_string :: proc(b: ^strings.Builder, rope: Rope, index: Rope_Index) {
		if index.leaf {
			leaf := rope.leaves[index.index]
			str  := string(leaf[:])
			strings.write_string(b, strings.truncate_to_byte(str, 0))
		} else {
			node := rope.nodes[index.index]
			_rope_to_string(b, rope, node.l)
			_rope_to_string(b, rope, node.r)
		}
	}

	_rope_to_string(&b, rope, rope.root)

	return strings.to_string(b)
}

@(require_results)
rope_build :: proc(leaves: []Rope_Leaf, allocator: runtime.Allocator, tab_width: int) -> (rope: Rope) {
	rope.tab_width                  = tab_width
	rope.nodes.allocator            = allocator
	rope.leaves.allocator           = allocator
	rope.root, rope.len, rope.lines = _rope_build(&rope, leaves)
	return
}

@(require_results)
_rope_build :: proc(rope: ^Rope, leaves: []Rope_Leaf) -> (index: Rope_Index, weight, lines: int) {
	switch len(leaves) {
	case 0:
		return
	case 1:
		leaf := leaves[0]

		str   := strings.truncate_to_byte(string(leaf[:]), 0)
		weight = len(str)
		lines  = strings.count(str, "\n")

		index.leaf  = true
		index.index = int(len(rope.leaves))
		append(&rope.leaves, leaf)
	case:
		mid := len(leaves) / 2

		li, lw, ll := _rope_build(rope, leaves[:mid])
		ri, rw, rl := _rope_build(rope, leaves[mid:])

		weight = lw + rw
		lines  = ll + rl

		append(&rope.nodes, Rope_Node {
			weight = lw,
			lines  = ll,
			l      = li,
			r      = ri,
		})
		index.leaf  = false
		index.index = int(len(rope.nodes)) - 1
	}

	return
}

@(require_results)
rope_from_string :: proc(str: string, allocator: runtime.Allocator, tab_width: int) -> (rope: Rope, ok: bool) {
	buf: Rope_Leaf
	buf_len: int

	leaves := make([dynamic]Rope_Leaf, context.temp_allocator)

	str := str
	for len(str) != 0 {
		_, n := utf8.decode_rune(str)
		if n == 0 {
			return
		}
		if n > len(buf) - buf_len {
			append(&leaves, buf)
			buf     = 0
			buf_len = 0
		}

		copy(buf[buf_len:], str[:n])
		buf_len += n
		str      = str[n:]
	}

	if buf_len > 0 {
		append(&leaves, buf)
	}

	return rope_build(leaves[:], allocator, tab_width), true
}

@(require_results)
rope_index :: proc(rope: Rope, offset: int, stack: ^[dynamic]Rope_Index, reverse: bool) -> (leaf_index: int, leaf_offset: int) {
	offset := offset
	index  := rope.root
	for !index.leaf {
		node := rope.nodes[index.index]
		if offset > node.weight {
			index   = node.r
			offset -= node.weight

			if reverse {
				append(stack, node.l)
			}
		} else {
			index = node.l

			if !reverse {
				append(stack, node.r)
			}
		}
	}
	return index.index, offset
}

@(require_results)
rope_index_line :: proc(rope: Rope, line: int, stack: ^[dynamic]Rope_Index, reverse: bool) -> (leaf_index: int, leaf_offset: int) {
	line  := line
	index := rope.root
	for !index.leaf {
		node := rope.nodes[index.index]
		if line > node.lines {
			index = node.r
			line -= node.lines

			if reverse {
				append(stack, node.l)
			}
		} else {
			index = node.l

			if !reverse {
				append(stack, node.r)
			}
		}
	}

	if line == 0 {
		return index.index, 0
	}

	leaf := &rope.leaves[index.index]
	for &char, i in leaf {
		if char == '\n' {
			line -= 1
		}
		if line == 0 {
			return index.index, i + 1
		}
	}

	unreachable()
}

// @(require_results)
// rope_line_to_offset :: proc(rope: Rope, line, column: int) -> int {
// 	line   := line
// 	index  := rope.root
// 	offset := 0
// 	for !index.leaf {
// 		node := rope.nodes[index.index]
// 		if line > node.lines {
// 			index   = node.r
// 			line   -= node.lines
// 			offset += node.weight
// 		} else {
// 			index   = node.l
// 		}
// 	}

// 	if line == 0 {
// 		return offset
// 	}

// 	leaf := &rope.leaves[index.index]
// 	for &char, i in leaf {
// 		if char == '\n' {
// 			line -= 1
// 		}
// 		if line == 0 {
// 			return index.index, i + 1
// 		}
// 	}

// 	unreachable()
// }

@(require_results)
rope_get_rune :: proc(rope: Rope, offset: int) -> rune {
	offset := offset
	index  := rope.root
	for !index.leaf {
		node := rope.nodes[index.index]
		if offset > node.weight {
			index   = node.r
			offset -= node.weight
		} else {
			index = node.l
		}
	}
	leaf := bytes.truncate_to_byte(rope.leaves[index.index][:], 0)
	r, n := utf8.decode_rune(leaf[offset:])
	assert(n > 0)
	return r
}

rope_destroy :: proc(rope: Rope) {
	delete(rope.nodes)
	delete(rope.leaves)
}

Rope_Iterator :: struct {
	rope:          ^Rope,
	stack:          [dynamic]Rope_Index,
	leaf:           []u8,
	using position: Position,
	last:           rune,
	reverse:        bool,
}

@(require_results)
rope_iterator :: proc(rope: ^Rope, offset: int = -1, line: int = -1, column: int = -1, reverse: bool = false, allocator := context.temp_allocator) -> (iter: Rope_Iterator) {
	assert(offset == -1 || line   == -1)
	assert(column == -1 || line   != -1)
	assert(column == -1 || offset == -1)
	assert(column == -1 || !reverse)

	iter.reverse = reverse
	iter.rope    = rope
	iter.stack   = make([dynamic]Rope_Index, allocator)

	if offset != -1 {
		if offset > rope.len {
			return
		}
		leaf_index, leaf_offset := rope_index(rope^, offset, &iter.stack, reverse)
		leaf                    := bytes.truncate_to_byte(rope.leaves[leaf_index][:], 0)
		if reverse {
			iter.leaf = leaf[:leaf_offset]
		} else {
			iter.leaf = leaf[leaf_offset:]
		}
		return
	}

	if line != -1 {
		if line > rope.lines {
			return
		}
		leaf_index, leaf_offset := rope_index_line(rope^, line, &iter.stack, reverse)
		leaf                    := bytes.truncate_to_byte(rope.leaves[leaf_index][:], 0)
		if reverse {
			iter.leaf = leaf[:leaf_offset]
		} else {
			iter.leaf = leaf[leaf_offset:]
		}
		iter.line   = line
		iter.column = 0

		if column != -1 {
			for r in rope_iter(&iter) {
				if iter.column == column {
					return
				}
				if r == '\t' && iter.column <= column && column < next_column_after_tab(iter.column, rope.tab_width) {
					return
				}
			}
			panic("")
		}

		return
	}

	append(&iter.stack, rope.root)
	return
}

@(require_results)
rope_iter :: proc(iter: ^Rope_Iterator) -> (r: rune, cond: bool) {
	switch iter.last {
	case 0:
	case '\n':
		iter.line  += 1
		iter.column = 0
	case '\t':
		iter.column = next_column_after_tab(iter.column, iter.rope.tab_width)
	case:
		iter.column += 1
	}

	@(require_results)
	leaf_advance :: proc(iter: ^Rope_Iterator) -> (r: rune, cond: bool) {
		assert(len(iter.leaf) != 0)

		n: int
		if iter.reverse {
			r, n = utf8.decode_last_rune(iter.leaf)
			(n != 0) or_return
			iter.leaf = iter.leaf[:len(iter.leaf) - n]
		} else {
			r, n = utf8.decode_rune(iter.leaf)
			(n != 0) or_return
			iter.leaf = iter.leaf[n:]
			iter.last = r
		}

		cond = true
		return
	}

	if len(iter.leaf) != 0 {
		return leaf_advance(iter)
	}

	for {
		index := pop_safe(&iter.stack) or_return

		if index.leaf {
			iter.leaf = bytes.truncate_to_byte(iter.rope.leaves[index.index][:], 0)
			return leaf_advance(iter)
		} else {
			node := iter.rope.nodes[index.index]
			if iter.reverse {
				append(&iter.stack, node.l)
				append(&iter.stack, node.r)
			} else {
				append(&iter.stack, node.r)
				append(&iter.stack, node.l)
			}
		}
	}

	return
}

import testing "core:testing"

@(test)
rope_test_round_trip :: proc(t: ^testing.T) {
	data := #load(#file, string)

	rope, ok := rope_from_string(data, context.allocator, 4)
	assert(ok)
	defer rope_destroy(rope)

	decoded := rope_to_string(rope, context.allocator)
	defer delete(decoded)

	assert(decoded == data)
}

@(test)
rope_test_iter :: proc(t: ^testing.T) {
	data := #load(#file, string)

	rope, ok := rope_from_string(data, context.allocator, 4)
	assert(ok)
	defer rope_destroy(rope)

	b := strings.builder_make(context.temp_allocator)

	iter := rope_iterator(&rope)
	for r in rope_iter(&iter) {
		strings.write_rune(&b, r)
	}

	assert(strings.to_string(b) == data)
}

@(test)
rope_test_iter_reverse :: proc(t: ^testing.T) {
	data := #load(#file, string)

	rope, ok := rope_from_string(data, context.allocator, 4)
	assert(ok)
	defer rope_destroy(rope)

	b := strings.builder_make(context.temp_allocator)

	iter := rope_iterator(&rope, offset = len(data), reverse = true)
	for r in rope_iter(&iter) {
		strings.write_rune(&b, r)
	}

	assert(strings.reverse(strings.to_string(b), context.temp_allocator) == data)
}

rope_position_to_offset :: proc(rope: ^Rope, line, column: int) -> int {
	unimplemented()
}

rope_insert :: proc(rope: ^Rope, offset: int, codepoint: rune) {
	unimplemented()
}

rope_remove_range :: proc(rope: ^Rope, begin, end: int) {
	unimplemented()
}

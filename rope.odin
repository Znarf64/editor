package editor

import "base:runtime"

import "core:strings"
import "core:unicode/utf8"

Rope_Index :: bit_field i64 {
	index: i64  | 63,
	leaf:  bool | 1,
}

Rope_Node :: struct {
	weight: i64,
	l, r:   Rope_Index,
}

ROPE_LEAF_SIZE :: 16
Rope_Leaf      :: [16]u8

Dynamic_Pool :: struct (E: typeid) where size_of(E) > size_of(i32) {
	data: [dynamic]E,
	free: i32,
}

Rope :: struct {
	root:   Rope_Index,
	nodes:  [dynamic]Rope_Node,
	leaves: [dynamic]Rope_Leaf,
}

@(require_results)
rope_to_string :: proc(rope: Rope, allocator: runtime.Allocator) -> string {
	b := strings.builder_make(allocator)

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
rope_build :: proc(leaves: []Rope_Leaf, allocator: runtime.Allocator) -> (rope: Rope) {
	rope.nodes.allocator  = allocator
	rope.leaves.allocator = allocator
	rope.root             = _rope_build(&rope, leaves)
	return
}

@(require_results)
_rope_build :: proc(rope: ^Rope, leaves: []Rope_Leaf) -> (index: Rope_Index) {
	switch len(leaves) {
	case 0:
		return
	case 1:
		index.leaf  = true
		index.index = i64(len(rope.leaves))
		append(&rope.leaves, leaves[0])
	case:
		mid := len(leaves) / 2

		append(&rope.nodes, Rope_Node {
			l = _rope_build(rope, leaves[:mid]),
			r = _rope_build(rope, leaves[mid:]),
		})
		index.leaf  = false
		index.index = i64(len(rope.nodes)) - 1
	}

	return
}

@(require_results)
rope_from_string :: proc(str: string, allocator: runtime.Allocator) -> (rope: Rope, ok: bool) {
	buf: Rope_Leaf
	buf_len: int

	leaves := make([dynamic]Rope_Leaf, allocator)

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

	return rope_build(leaves[:], allocator), true
}

rope_split :: proc(rope: ^Rope, index: int) {
	
}

import "core:testing"

@(test)
rope_test_round_trip :: proc(t: ^testing.T) {
	data := #load(#file, string)
	rope, ok := rope_from_string(data, context.temp_allocator)
	assert(ok)
	decoded := rope_to_string(rope, context.temp_allocator)
	assert(decoded == data)
}

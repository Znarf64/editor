package editor

import runtime "base:runtime"

import bytes   "core:bytes"
import fmt     "core:fmt"
import utf8    "core:unicode/utf8"
import strings "core:strings"
import testing "core:testing"

BTREE_LEAF_SIZE :: 64 - size_of(i32) * 2
BTREE_MAX_NODES :: 16
BTREE_MIN_NODES :: (BTREE_MAX_NODES + 1) / 2

#assert(BTREE_LEAF_SIZE >= 4)

BTree :: struct {
	using info: BTree_Info,
	tab_width:  int,
	root:       BTree_Index,
	nodes:      [dynamic]BTree_Node,
	leaves:     [dynamic]BTree_Leaf,
}

BTree_Index :: bit_field i32 {
	index: i32  | 31,
	leaf:  bool | 1,
}

BTree_Info :: struct {
	lines: i32,
	chars: i32,
	bytes: i32,
}

BTree_Node :: struct {
	infos:    [BTREE_MAX_NODES - 1]BTree_Info,
	children: [BTREE_MAX_NODES    ]BTree_Index,
}

BTree_Leaf :: struct {
	data: [BTREE_LEAF_SIZE]u8 `fmt:"s,0"`,
	next: i32,
	prev: i32,
}

@(require_results)
btree_build :: proc(data: string, allocator: runtime.Allocator, tab_width: int) -> (btree: BTree) {
	leaf_count := 1

	btree.tab_width = tab_width
	btree.nodes     = make([dynamic]BTree_Node, allocator)
	btree.leaves    = make([dynamic]BTree_Leaf, allocator)

	depth := 0
	for leaf_count * (BTREE_LEAF_SIZE - 3 /* we don't want to split codepoints across leaves */) < len(data) {
		leaf_count *= BTREE_MAX_NODES
		depth      += 1
	}

	per_leaf := (len(data) + leaf_count - 1) / leaf_count
	assert(per_leaf <= BTREE_LEAF_SIZE - 3)

	offset := 0
	for offset < len(data) {
		leaf := BTree_Leaf {
			prev = i32(len(btree.leaves) - 1),
			next = i32(len(btree.leaves) + 1),
		}
		n := copy(leaf.data[:per_leaf], data[offset:])

		// Add bytes until the we have a full codepoint at the end, this could be better
		for {
			r, _ := utf8.decode_last_rune(leaf.data[:n])
			if r != utf8.RUNE_ERROR {
				break
			}

			leaf.data[n] = data[offset + n]
			n           += 1
		}
		offset += n

		append(&btree.leaves, leaf)
	}

	btree.leaves[len(btree.leaves) - 1].next = -1

	@(require_results)
	get_leaf_info :: proc(leaf: BTree_Leaf) -> (info: BTree_Info) {
		leaf := leaf
		str  := strings.truncate_to_byte(string(leaf.data[:]), 0)

		info.bytes = i32(len(str))

		for r in str {
			info.chars += 1
			if r == '\n' {
				info.lines += 1
			}
		}

		return
	}

	@(require_results)
	build :: proc(btree: ^BTree, start, end: i32) -> (index: BTree_Index, info: BTree_Info) {
		if end - start == 1 {
			return { index = start, leaf = true, }, get_leaf_info(btree.leaves[start])
		}
		if start >= end {
			return {}, {}
		}

		per_child := (end - start + BTREE_MAX_NODES - 1) / BTREE_MAX_NODES
		start     := start

		node: BTree_Node

		i: int
		for start < end {
			next := min(start + per_child, end)

			child, child_info := build(btree, start, next)
			if i != BTREE_MAX_NODES - 1 {
				node.infos[i] = child_info
			}
			node.children[i] = child

			info  = btree_info_add(info, child_info)
			start = next
			i    += 1
		}

		index.index = i32(len(btree.nodes))
		index.leaf  = false
		append(&btree.nodes, node)

		return
	}

	btree.root, btree.info = build(&btree, 0, i32(len(btree.leaves)))

	return
}

btree_insert :: proc {
	btree_insert_string,
	btree_insert_rune,
}

btree_insert_string :: proc(btree: ^BTree, offset: int, data: string) -> (n: int) {
	#reverse for r in data {
		n += btree_insert_rune(btree, offset, r)
	}
	return n
}

@(require_results)
btree_info_add :: proc(a, b: BTree_Info) -> BTree_Info {
	return {
		lines = a.lines + b.lines,
		chars = a.chars + b.chars,
		bytes = a.bytes + b.bytes,
	}
}

btree_insert_rune :: proc(btree: ^BTree, offset: int, r: rune) -> int {
	@(require_results)
	insert :: proc(btree: ^BTree, index: BTree_Index, offset: int, data: []u8, info: BTree_Info) -> (new_info: BTree_Info, new_node: BTree_Index, new: bool) {
		if index.leaf {
			leaf  := &btree.leaves[index.index]
			space := BTREE_LEAF_SIZE - len(bytes.truncate_to_byte(leaf.data[:], 0))

			if len(data) <= space {
				copy(leaf.data[offset + len(data):], leaf.data[offset:])
				copy(leaf.data[offset:], data)

				return
			} else {
				leaf := BTree_Leaf {
					prev = index.index,
					next = leaf.next,
				}
				copy(leaf.data[:], data)

				new_info = info
				new_node = { index = i32(len(btree.leaves)), leaf = true, }
				new      = true
				return
			}
		}

		offset := offset

		node    := &btree.nodes[index.index]
		n_nodes := 0
		for &node_info, i in node.infos {
			n_nodes += 1
			if node_info.bytes == 0 {
				break
			}

			if int(node_info.bytes) > offset {
				node_info               = btree_info_add(node_info, info)
				child_info, child_node := insert(btree, node.children[i], offset, data, info) or_return // if there is no new node we are done
				unimplemented()
			}

			offset -= int(node_info.bytes)
		}

		child_info, child_node := insert(btree, node.children[n_nodes], offset, data, info) or_return
		unimplemented()
	}

	buf, n := utf8.encode_rune(r)
	data   := buf[:n]
	info   := BTree_Info {
		lines = i32(bytes.count(data, { '\n', })),
		bytes = i32(len(data)),
		chars = 1,
	}

	new_info, new_node, new := insert(btree, btree.root, offset, data, info)

	btree.info = btree_info_add(btree.info, info)

	if new {
		btree.root = new_node
		assert(new_info == btree.info)
	}

	return n
}

@(require_results)
btree_line_to_offset :: proc(btree: ^BTree, line: int) -> (offset: int) {
	index := btree.root
	line  := line

	find_leaf: for !index.leaf {
		node := btree.nodes[index.index]
		n    := 0
		for info, i in node.infos {
			if info.bytes == 0 {
				break
			}
			n += 1

			if int(info.lines) >= line {
				index = node.children[i]
				continue find_leaf
			}
			offset += int(info.bytes)
			line   -= int(info.lines)
		}
		index = node.children[n]
	}

	leaf := btree.leaves[index.index]
	data := strings.truncate_to_byte(string(leaf.data[:]), 0)

	for {
		if line == 0 {
			return
		}

		r, n   := utf8.decode_rune(data)
		data    = data[n:]
		offset += n
		if r == '\n' {
			line -= 1
		}
	}

	return
}

@(require_results)
btree_offset_to_line :: proc(btree: ^BTree, offset: int) -> (line: int) {
	index  := btree.root
	offset := offset

	find_leaf: for !index.leaf {
		node := btree.nodes[index.index]
		n    := 0
		for info, i in node.infos {
			if info.bytes == 0 {
				break
			}
			n += 1

			if int(info.bytes) >= offset {
				index = node.children[i]
				continue find_leaf
			}
			line   += int(info.lines)
			offset -= int(info.bytes)
		}
		index = node.children[n]
	}

	leaf := btree.leaves[index.index]
	data := strings.truncate_to_byte(string(leaf.data[:]), 0)

	for r in data[:offset] {
		if r == '\n' {
			line += 1
		}
	}

	if offset > 0 && data[offset - 1] == '\n' {
		line -= 1
	}

	return
}

@(require_results)
btree_offset_to_position :: proc(btree: ^BTree, offset: int) -> (position: Position) {
	line := btree_offset_to_line(btree, offset)
	iter := btree_iterator(btree, line = line)

	for iter.offset != offset {
		_ = btree_iter(&iter) or_else panic("offset out of range")
	}

	return iter.position
}

@(require_results)
btree_position_to_offset :: proc(btree: ^BTree, position: Position) -> (offset: int) {
	iter := btree_iterator(btree, line = position.line, column = position.column)
	_, _  = btree_iter(&iter)
	return iter.offset
}

btree_remove_range :: proc(btree: ^BTree, start, end: int) {
	unimplemented()
}

@(require_results)
btree_find_leaf :: proc(btree: BTree, offset: int) -> (leaf_index: int, leaf_offset: int) {
	index  := btree.root
	offset := offset

	find_leaf: for !index.leaf {
		node := btree.nodes[index.index]
		n    := 0
		for info, i in node.infos {
			if info.bytes == 0 {
				break
			}
			n += 1

			if int(info.bytes) > offset {
				index = node.children[i]
				continue find_leaf
			}
			offset -= int(info.bytes)
		}
		index = node.children[n]
	}

	return int(index.index), offset
}

btree_destroy :: proc(btree: BTree) {
	delete(btree.nodes)
	delete(btree.leaves)
}

BTree_Iterator :: struct {
	btree:         ^BTree,
	leaf:           int,
	leaf_offset:    int,

	last:           rune,

	next_offset:    int,
	offset:         int,
	using position: Position,
}

@(require_results)
btree_iterator :: proc(btree: ^BTree, offset := -1, line := -1, column := -1) -> (iter: BTree_Iterator) {
	assert(offset == -1 || line == -1)
	assert(column == -1 || line != -1)

	offset := offset

	if line != -1 {
		offset    = btree_line_to_offset(btree, line)
		iter.line = line
	}

	if offset == -1 {
		offset = 0
	}

	iter.btree                  = btree
	iter.leaf, iter.leaf_offset = btree_find_leaf(btree^, offset)
	iter.offset                 = -1
	iter.next_offset            = offset

	if column != -1 && iter.column < column {
		for {
			r := btree_iter(&iter) or_break
			if position_after(iter.position, r, btree.tab_width).column >= column {
				break
			}
		}
	}

	return
}

@(require_results)
btree_get_rune :: proc(btree: BTree, offset: int) -> rune {
	index, offset := btree_find_leaf(btree, offset)
	leaf          := btree.leaves[index]
	r, _          := utf8.decode_rune(leaf.data[offset:])
	return r
}

@(require_results)
btree_iter :: proc(iter: ^BTree_Iterator, back := false) -> (r: rune, cond: bool) {
	iter.position = position_after(iter.position, iter.last, iter.btree.tab_width)
	defer iter.last = r

	iter.offset = iter.next_offset

	defer if ODIN_DEBUG && cond {
		assert(btree_get_rune(iter.btree^, iter.offset) == r)
	}

	for {
		if iter.leaf < 0 {
			return
		}

		leaf := iter.btree.leaves[iter.leaf]

		if back {
			data            := bytes.truncate_to_byte(leaf.data[:], 0)
			iter.leaf_offset = min(iter.leaf_offset, len(data))
			data             = data[:iter.leaf_offset]

			if len(data) == 0 {
				iter.leaf        = int(leaf.prev)
				iter.leaf_offset = BTREE_LEAF_SIZE
				continue
			}

			n: int
			r, n = utf8.decode_last_rune(data)
			assert(r != utf8.RUNE_ERROR, "failed to decode utf8 rune")

			iter.next_offset  = iter.offset - n
			iter.leaf_offset -= n
			iter.offset       = iter.next_offset
			assert(iter.leaf_offset >= 0)
		} else {
			data := bytes.truncate_to_byte(leaf.data[iter.leaf_offset:], 0)

			if len(data) == 0 {
				iter.leaf        = int(leaf.next)
				iter.leaf_offset = 0
				continue
			}

			n: int
			r, n = utf8.decode_rune(data)
			assert(r != utf8.RUNE_ERROR, "failed to decode utf8 rune")

			iter.next_offset  = iter.offset + n
			iter.leaf_offset += n
		}

		return r, true
	}
}

@(require_results)
graph_dot :: proc(btree: BTree, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)

	_graph_dot :: proc(b: ^strings.Builder, btree: BTree, index, parent: BTree_Index) {
		if index.leaf {
			fmt.sbprintfln(b, "\ti%v -> l%v;", parent.index, index.index)
			return
		} else {
			if index != parent {
				fmt.sbprintfln(b, "\ti%v -> i%v;", parent.index, index.index)
			}
		}

		node := btree.nodes[index.index]

		for i in 0 ..< BTREE_MAX_NODES {
			if node.infos[i] == {} {
				break
			}

			_graph_dot(b, btree, node.children[i], index)
		}
	}

	fmt.sbprintln(&b, "digraph {")

	_graph_dot(&b, btree, btree.root, btree.root)

	fmt.sbprintln(&b, "}")

	return strings.to_string(b)
}

@(test)
btree_test_iter :: proc(t: ^testing.T) {
	// some utf8 encoded text for the tests: öäöäöäöäöäöäöüüüüüüßßßßßaâââ

	data  := #load(#file, string)
	btree := btree_build(data, context.temp_allocator, 4)

	iter := btree_iterator(&btree, len(data) / 2)

	b := strings.builder_make(context.temp_allocator)
	for r in btree_iter(&iter) {
		strings.write_rune(&b, r)
	}

	assert(strings.to_string(b) == data[len(data) / 2:])
}

@(test)
btree_test_lines :: proc(t: ^testing.T) {
	data  :=
`LINE 0
LINE 1
LINE 2
LINE 3
LINE 4
LINE 5
LINE 6
LINE 7
LINE 8
`
	btree := btree_build(data, context.temp_allocator, 4)

	iter := btree_iterator(&btree, line = 6)

	b := strings.builder_make(context.temp_allocator)
	for r in btree_iter(&iter) {
		strings.write_rune(&b, r)
	}

	// assert(strings.to_string(b) == )
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

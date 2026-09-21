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

Index :: distinct i32

_Offset :: distinct i32

BTree :: struct {
	using info: BTree_Info,
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
	chars: Index,
	bytes: _Offset,
}

BTree_Node :: struct {
	infos:    [BTREE_MAX_NODES - 1]BTree_Info,
	children: [BTREE_MAX_NODES    ]BTree_Index,
}

BTree_Leaf :: struct {
	data: [BTREE_LEAF_SIZE]u8 `fmt:"x,0"`,
	next: i32,
	prev: i32,
}

@(require_results)
btree_build :: proc(data: string, allocator: runtime.Allocator) -> (btree: BTree) {
	leaf_count := 1

	btree.nodes  = make([dynamic]BTree_Node, allocator)
	btree.leaves = make([dynamic]BTree_Leaf, allocator)

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

		info.bytes = _Offset(len(str))

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

btree_insert_string :: proc(btree: ^BTree, index: Index, data: string) -> (runes: Index, bytes: _Offset) {
	#reverse for r in data {
		bytes += btree_insert_rune(btree, index, r)
		runes += 1
	}
	return
}

@(require_results)
btree_info_add :: proc(a, b: BTree_Info) -> BTree_Info {
	return {
		lines = a.lines + b.lines,
		chars = a.chars + b.chars,
		bytes = a.bytes + b.bytes,
	}
}

btree_insert_rune :: proc(btree: ^BTree, index: Index, r: rune) -> _Offset {
	@(require_results)
	insert :: proc(btree: ^BTree, index: BTree_Index, offset: _Offset, data: []u8, info: BTree_Info) -> (new_info: BTree_Info, new_node: BTree_Index, new: bool) {
		if index.leaf {
			leaf  := &btree.leaves[index.index]
			space := BTREE_LEAF_SIZE - len(bytes.truncate_to_byte(leaf.data[:], 0))

			if len(data) <= space {
				copy(leaf.data[offset + _Offset(len(data)):], leaf.data[offset:])
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

			if node_info.bytes > offset {
				node_info               = btree_info_add(node_info, info)
				child_info, child_node := insert(btree, node.children[i], offset, data, info) or_return // if there is no new node we are done
				unimplemented()
			}

			offset -= node_info.bytes
		}

		child_info, child_node := insert(btree, node.children[n_nodes], offset, data, info) or_return
		unimplemented()
	}

	buf, n := utf8.encode_rune(r)
	data   := buf[:n]
	info   := BTree_Info {
		lines = i32(bytes.count(data, { '\n', })),
		bytes = _Offset(len(data)),
		chars = 1,
	}

	offset := btree_index_to_offset(btree, index)

	new_info, new_node, new := insert(btree, btree.root, offset, data, info)

	btree.info = btree_info_add(btree.info, info)

	if new {
		btree.root = new_node
		assert(new_info == btree.info)
	}

	return _Offset(n)
}

@(require_results)
btree_line_to_index :: proc(btree: ^BTree, line: int) -> (index: Index) {
	node_index := btree.root
	line       := line

	find_leaf: for !node_index.leaf {
		node := btree.nodes[node_index.index]
		n    := 0
		for info, i in node.infos {
			if info.bytes == 0 {
				break
			}
			n += 1

			if int(info.lines) >= line {
				node_index = node.children[i]
				continue find_leaf
			}
			index += info.chars
			line  -= int(info.lines)
		}
		node_index = node.children[n]
	}

	leaf := btree.leaves[node_index.index]
	data := strings.truncate_to_byte(string(leaf.data[:]), 0)

	for r in data {
		if line == 0 {
			return
		}
		index += 1
		if r == '\n' {
			line -= 1
		}
	}

	return
}

@(require_results)
btree_index_to_line :: proc(btree: ^BTree, index: Index) -> (line: int) {
	index      := index
	node_index := btree.root

	find_leaf: for !node_index.leaf {
		node := btree.nodes[node_index.index]
		n    := 0
		for info, i in node.infos {
			if info.bytes == 0 {
				break
			}
			n += 1

			if info.chars > index {
				node_index = node.children[i]
				continue find_leaf
			}
			index -= info.chars
			line  += int(info.lines)
		}
		node_index = node.children[n]
	}

	leaf := btree.leaves[node_index.index]
	data := strings.truncate_to_byte(string(leaf.data[:]), 0)

	for r in data {
		if index == 0 {
			break
		}
		index -= 1
		if r == '\n' {
			line += 1
		}
	}

	return
}

@(require_results)
btree_index_to_position :: proc(btree: ^BTree, index: Index, tab_width: int) -> (position: Position) {
	position.line = btree_index_to_line(btree, index)
	line_start   := btree_line_to_index(btree, position.line)
	assert(line_start <= index)
	iter         := btree_iterator(btree, line_start)

	p: Position = { line = position.line, }
	for iter.index != index {
		_, position = btree_iter(&iter, &p, tab_width) or_else panic("offset out of range")
	}

	return
}

@(require_results)
btree_position_to_index :: proc(btree: ^BTree, position: Position, tab_width: int) -> (index: Index) {
	line_start := btree_line_to_index(btree, position.line)
	iter       := btree_iterator(btree, line_start)
	p: Position
	for {
		_, pos := btree_iter(&iter, &p, tab_width) or_break
		if pos.line > position.line {
			panic("Position out of bounds")
		}
		if pos.column >= position.column {
			return iter.index
		}
	}
	return btree.chars
}

btree_remove_range :: proc(btree: ^BTree, start, end: Index) {
	unimplemented()
}

btree_find_leaf :: proc {
	btree_find_leaf_by_index,
}

@(require_results)
btree_find_leaf_by_index :: proc(btree: BTree, index: Index) -> (leaf_index: i32, leaf_offset: _Offset) {
	node_index := btree.root
	index      := index

	find_leaf: for !node_index.leaf {
		node := btree.nodes[node_index.index]
		n    := 0
		for info, i in node.infos {
			if info.bytes == 0 {
				break
			}
			n += 1

			if info.chars > index {
				node_index = node.children[i]
				continue find_leaf
			}
			index -= info.chars
		}
		node_index = node.children[n]
	}

	data := string(btree.leaves[node_index.index].data[:])
	data  = strings.truncate_to_byte(data, 0)
	for _, offset in data {
		if index == 0 {
			return node_index.index, _Offset(offset)
		}
		index -= 1
	}

	return node_index.index, _Offset(len(data))
}

btree_destroy :: proc(btree: BTree) {
	delete(btree.nodes)
	delete(btree.leaves)
}

BTree_Iterator :: struct {
	btree:      ^BTree,
	leaf:        i32,
	leaf_offset: _Offset,
	index:       Index,
	next_index:  Index,
}

@(require_results)
btree_iterator :: proc(
	btree: ^BTree,
	index: Index,
	// line: int = -1,
) -> (iter: BTree_Iterator) {
	// if line != -1 {
	// 	index     = btree_line_to_index(btree, line)
	// 	iter.line = line
	// }

	iter.btree                  = btree
	iter.leaf, iter.leaf_offset = btree_find_leaf(btree^, index)
	iter.index                  = -1
	iter.next_index             = index

	return
}

btree_get_rune :: proc {
	btree_get_rune_at_index,
}

@(require_results)
btree_get_rune_at_index :: proc(btree: BTree, index: Index) -> rune {
	index, offset := btree_find_leaf(btree, index)
	leaf          := btree.leaves[index]
	r, _          := utf8.decode_rune(leaf.data[offset:])
	return r
}

btree_iter :: proc {
	btree_iter_simple,
	btree_iter_with_position,
}

@(require_results)
btree_iter_with_position :: proc(
	iter:     ^BTree_Iterator,
	position: ^Position,
	tab_width: int,
) -> (
	r:    rune,
	p:    Position,
	cond: bool,
) {
	r, cond   = btree_iter(iter)
	p         = position^
	position^ = position_after(p, r, tab_width)
	return
}

@(require_results)
btree_iter_simple :: proc(iter: ^BTree_Iterator, back := false) -> (r: rune, cond: bool) {
	iter.index = iter.next_index

	defer if ODIN_DEBUG && cond {
		assert(btree_get_rune(iter.btree^, iter.index) == r)
	}

	for {
		if iter.leaf < 0 {
			return
		}

		leaf := iter.btree.leaves[iter.leaf]

		if back {
			data            := bytes.truncate_to_byte(leaf.data[:], 0)
			iter.leaf_offset = min(iter.leaf_offset, _Offset(len(data)))
			data             = data[:iter.leaf_offset]

			if len(data) == 0 {
				iter.leaf        = leaf.prev
				iter.leaf_offset = BTREE_LEAF_SIZE
				continue
			}

			n: int
			r, n = utf8.decode_last_rune(data)
			assert(r != utf8.RUNE_ERROR, "failed to decode utf8 rune")

			iter.next_index   = iter.index - 1
			iter.leaf_offset -= _Offset(n)
			iter.index        = iter.next_index
			assert(iter.leaf_offset >= 0)
		} else {
			data := bytes.truncate_to_byte(leaf.data[iter.leaf_offset:], 0)

			if len(data) == 0 {
				iter.leaf        = leaf.next
				iter.leaf_offset = 0
				continue
			}

			n: int
			r, n = utf8.decode_rune(data)
			assert(r != utf8.RUNE_ERROR, "failed to decode utf8 rune")

			iter.next_index  = iter.index + 1
			iter.leaf_offset += _Offset(n)
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

btree_to_string :: proc(
	btree: ^BTree,
	b:     ^strings.Builder,
	start: Index = 0,
	end:   Index = -1,
	reverse := false,
) {
	if reverse {
		// TODO: make this faster
		rb := strings.builder_make(context.temp_allocator)
		btree_to_string(btree, &rb, start, end)
		strings.write_string(b, strings.reverse(strings.to_string(rb), context.temp_allocator))
		return
	}

	end_offset := btree.bytes
	if end != -1 {
		end_offset = btree_index_to_offset(btree, end)
	}

	offset := btree_index_to_offset(btree, start)
	leaf_index, leaf_offset := btree_find_leaf(btree^, start)

	strings.builder_grow(b, strings.builder_len(b^) + int(end_offset) - int(offset))
	p := raw_data(b.buf)

	for offset < end_offset {
		leaf       := btree.leaves[leaf_index]
		data       := strings.truncate_to_byte(string(leaf.data[leaf_offset:]), 0)
		n          := min(end_offset - offset, _Offset(len(data)))
		strings.write_string(b, data[:n])
		offset     += n
		leaf_index  = leaf.next
		leaf_offset = 0
	}
	assert(offset == end_offset)
	assert(p      == raw_data(b.buf))
}

@(require_results)
btree_offset_to_index :: proc(btree: ^BTree, offset: _Offset, base: Index = 0) -> (index: Index) {
	if base != 0 {
		return btree_offset_to_index(btree, offset + btree_index_to_offset(btree, base))
	}

	offset     := offset
	node_index := btree.root

	find_leaf: for !node_index.leaf {
		node := btree.nodes[node_index.index]
		n    := 0
		for info, i in node.infos {
			if info.bytes == 0 {
				break
			}
			n += 1

			if info.bytes > offset {
				node_index = node.children[i]
				continue find_leaf
			}
			offset -= info.bytes
			index  += info.chars
		}
		node_index = node.children[n]
	}

	leaf := btree.leaves[node_index.index]
	data := strings.truncate_to_byte(string(leaf.data[:]), 0)
	return index + Index(strings.rune_count(data[:offset]))
}

@(require_results)
btree_index_to_offset :: proc(btree: ^BTree, index: Index) -> (offset: _Offset) {
	index      := index
	node_index := btree.root

	find_leaf: for !node_index.leaf {
		node := btree.nodes[node_index.index]
		n    := 0
		for info, i in node.infos {
			if info.bytes == 0 {
				break
			}
			n += 1

			if info.chars > index {
				node_index = node.children[i]
				continue find_leaf
			}
			index  -= info.chars
			offset += info.bytes
		}
		node_index = node.children[n]
	}

	leaf := btree.leaves[node_index.index]
	data := strings.truncate_to_byte(string(leaf.data[:]), 0)

	for r, sub_offset in data {
		if index == 0 {
			return offset + _Offset(sub_offset)
		}
		index -= 1
	}

	return offset + _Offset(len(data))
}

@(test)
btree_test_iter :: proc(t: ^testing.T) {
	// some utf8 encoded text for the tests: öäöäöäöäöäöäöüüüüüüßßßßßaâââ

	data  := #load(#file, string)
	btree := btree_build(data, context.allocator)
	defer btree_destroy(btree)

	iter := btree_iterator(&btree, 0)

	b := strings.builder_make(context.temp_allocator)
	for r in btree_iter(&iter) {
		strings.write_rune(&b, r)
	}

	assert(strings.to_string(b) == data)
}

@(test)
btree_test_lines :: proc(t: ^testing.T) {
	A :: 
`0
1
2
3

`

	B ::
`5
6
7
8
9
`

	btree := btree_build(A + B, context.allocator)
	defer btree_destroy(btree)

	line_start := btree_line_to_index(&btree, 5)
	iter       := btree_iterator(&btree, line_start)

	b := strings.builder_make(context.temp_allocator)
	for r in btree_iter(&iter) {
		strings.write_rune(&b, r)
	}

	assert(strings.to_string(b) == B)

	iter = btree_iterator(&btree, line_start)
	b    = strings.builder_make(context.temp_allocator)
	for r in btree_iter(&iter, back = true) {
		strings.write_rune(&b, r)
	}

	assert(strings.to_string(b) == strings.reverse(A, context.temp_allocator))
}

@(test)
btree_test_to_string :: proc(t: ^testing.T) {
	data  := #load(#file, string)
	btree := btree_build(data, context.allocator)
	defer btree_destroy(btree)

	b := strings.builder_make(context.temp_allocator)
	btree_to_string(&btree, &b)

	assert(strings.to_string(b) == data)
}

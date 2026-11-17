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

// The most bytes a single call to `btree_insert_bytes` accepts. A leaf split
// has to be able to hold `BTREE_LEAF_SIZE + BTREE_MAX_INSERT` bytes temporarily.
BTREE_MAX_INSERT :: BTREE_LEAF_SIZE / 2

#assert(BTREE_LEAF_SIZE >= 4)
#assert(BTREE_MAX_INSERT >= 4) // must fit one full utf8 codepoint

Index :: distinct i32

_Offset :: distinct i32

// Invariants:
//
// - Leaves hold utf8 text, terminated by the first 0 byte (so the text itself
//   must not contain NUL). Every byte after the terminator is 0.
// - A node with `k` children stores the infos of its first `k - 1` children only
//   (`infos[k - 1 ..]` are zero), the info of the last child is implied by the
//   info of the node itself. This means every child except the last one must be
//   non-empty, in practice every child except the root leaf is non-empty.
// - All leaves are at the same depth.
// - `leaf.prev` / `leaf.next` form a doubly linked list of the leaves in text
//   order, `-1` terminates it.
// - The tree always has at least one leaf, an empty text is a single empty leaf.
// - Removed nodes and leaves are put on a free list (`free_node` / `free_leaf`).
BTree :: struct {
	using info: BTree_Info,
	root:       BTree_Index,
	nodes:      [dynamic]BTree_Node,
	leaves:     [dynamic]BTree_Leaf,
	free_node:  i32,
	free_leaf:  i32,
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

// A child together with its (explicit) info, used as working representation
// while modifying nodes.
BTree_Child :: struct {
	index: BTree_Index,
	info:  BTree_Info,
}

////////////////////////////////////////////////////////////////////////////////
// Info helpers
////////////////////////////////////////////////////////////////////////////////

@(require_results)
btree_info_add :: proc(a, b: BTree_Info) -> BTree_Info {
	return {
		lines = a.lines + b.lines,
		chars = a.chars + b.chars,
		bytes = a.bytes + b.bytes,
	}
}

@(require_results)
btree_info_sub :: proc(a, b: BTree_Info) -> BTree_Info {
	return {
		lines = a.lines - b.lines,
		chars = a.chars - b.chars,
		bytes = a.bytes - b.bytes,
	}
}

@(require_results)
btree_bytes_info :: proc(data: []u8) -> (info: BTree_Info) {
	info.bytes = _Offset(len(data))
	for r in string(data) {
		info.chars += 1
		if r == '\n' {
			info.lines += 1
		}
	}
	return
}

@(require_results)
btree_children_info :: proc(children: []BTree_Child) -> (info: BTree_Info) {
	for child in children {
		info = btree_info_add(info, child.info)
	}
	return
}

////////////////////////////////////////////////////////////////////////////////
// Node / leaf storage helpers
////////////////////////////////////////////////////////////////////////////////

@(require_results)
btree_alloc_leaf :: proc(btree: ^BTree, leaf: BTree_Leaf) -> i32 {
	if btree.free_leaf >= 0 {
		index          := btree.free_leaf
		btree.free_leaf = btree.leaves[index].next
		btree.leaves[index] = leaf
		return index
	}
	append(&btree.leaves, leaf)
	return i32(len(btree.leaves) - 1)
}

// Unlinks the leaf from the leaf list and puts it on the free list.
btree_free_leaf :: proc(btree: ^BTree, index: i32) {
	leaf := &btree.leaves[index]
	if leaf.prev >= 0 {
		btree.leaves[leaf.prev].next = leaf.next
	}
	if leaf.next >= 0 {
		btree.leaves[leaf.next].prev = leaf.prev
	}
	leaf^           = { prev = -1, next = btree.free_leaf, }
	btree.free_leaf = index
}

@(require_results)
btree_alloc_node :: proc(btree: ^BTree, node: BTree_Node) -> i32 {
	if btree.free_node >= 0 {
		index          := btree.free_node
		btree.free_node = btree.nodes[index].infos[0].lines
		btree.nodes[index] = node
		return index
	}
	append(&btree.nodes, node)
	return i32(len(btree.nodes) - 1)
}

btree_free_node :: proc(btree: ^BTree, index: i32) {
	btree.nodes[index]                = {}
	btree.nodes[index].infos[0].lines = btree.free_node
	btree.free_node                   = index
}

// Frees only the node / leaf itself, not its descendants.
btree_free_single :: proc(btree: ^BTree, index: BTree_Index) {
	if index.leaf {
		btree_free_leaf(btree, index.index)
	} else {
		btree_free_node(btree, index.index)
	}
}

// Frees the node / leaf and everything below it.
btree_free_subtree :: proc(btree: ^BTree, index: BTree_Index) {
	if !index.leaf {
		node  := btree.nodes[index.index]
		count := btree_node_count(&node)
		for i in 0 ..< count {
			btree_free_subtree(btree, node.children[i])
		}
	}
	btree_free_single(btree, index)
}

// Number of children of a node.
@(require_results)
btree_node_count :: proc(node: ^BTree_Node) -> (count: int) {
	for info in node.infos {
		if info.bytes == 0 {
			break
		}
		count += 1
	}
	return count + 1
}

// Expands a node into an array with an explicit info for every child, `total`
// is the info of the whole node (needed for the implicit last child). The array
// has room for one more child than a node can hold so that it can be used to
// split nodes.
@(require_results)
btree_node_children :: proc(node: ^BTree_Node, total: BTree_Info) -> (children: [BTREE_MAX_NODES + 1]BTree_Child, count: int) {
	rest := total
	for info, i in node.infos {
		if info.bytes == 0 {
			break
		}
		children[i] = { index = node.children[i], info = info, }
		rest        = btree_info_sub(rest, info)
		count      += 1
	}
	children[count] = { index = node.children[count], info = rest, }
	count          += 1
	return
}

// Inverse of `btree_node_children`.
btree_node_set :: proc(node: ^BTree_Node, children: []BTree_Child) {
	assert(0 < len(children) && len(children) <= BTREE_MAX_NODES)
	node^ = {}
	for child, i in children {
		node.children[i] = child.index
		if i != len(children) - 1 {
			assert(child.info.bytes > 0, "only the last child of a node may be empty")
			node.infos[i] = child.info
		}
	}
}

@(require_results)
btree_new_node :: proc(btree: ^BTree, children: []BTree_Child) -> (child: BTree_Child) {
	node: BTree_Node
	btree_node_set(&node, children)

	child.index.index = btree_alloc_node(btree, node)
	child.index.leaf  = false
	child.info        = btree_children_info(children)
	return
}

////////////////////////////////////////////////////////////////////////////////
// Build
////////////////////////////////////////////////////////////////////////////////

// Builds a balanced tree. `leaf_fill` is how many bytes (at least, a codepoint
// is never split) go into every leaf, the default leaves some room for edits.
// A small `leaf_fill` is mostly useful for testing.
@(require_results)
btree_build :: proc(data: string, allocator: runtime.Allocator, leaf_fill := BTREE_LEAF_SIZE * 3 / 4) -> (btree: BTree) {
	assert(1 <= leaf_fill && leaf_fill <= BTREE_LEAF_SIZE - 3)

	btree.nodes     = make([dynamic]BTree_Node, allocator)
	btree.leaves    = make([dynamic]BTree_Leaf, allocator)
	btree.free_node = -1
	btree.free_leaf = -1

	level := make([dynamic]BTree_Child, context.temp_allocator)

	offset := 0
	for offset < len(data) {
		n := min(leaf_fill, len(data) - offset)

		// we don't want to split codepoints across leaves
		for offset + n < len(data) && n < BTREE_LEAF_SIZE && (data[offset + n] & 0xC0) == 0x80 {
			n += 1
		}

		leaf := BTree_Leaf {
			prev = i32(len(btree.leaves)) - 1,
			next = i32(len(btree.leaves)) + 1,
		}
		copy(leaf.data[:], data[offset:offset + n])
		offset += n

		append(&btree.leaves, leaf)
		append(&level, BTree_Child {
			index = { index = i32(len(btree.leaves) - 1), leaf = true, },
			info  = btree_bytes_info(leaf.data[:n]),
		})
	}

	if len(btree.leaves) == 0 {
		append(&btree.leaves, BTree_Leaf { prev = -1, next = -1, })
		append(&level,        BTree_Child { index = { index = 0, leaf = true, }, })
	}

	btree.leaves[len(btree.leaves) - 1].next = -1

	// Build the tree bottom up, every level is split into evenly sized groups.
	for len(level) > 1 {
		groups := (len(level) + BTREE_MAX_NODES - 1) / BTREE_MAX_NODES
		next   := make([dynamic]BTree_Child, 0, groups, context.temp_allocator)
		start  := 0
		for group in 0 ..< groups {
			count := len(level) / groups + (1 if group < len(level) % groups else 0)
			append(&next, btree_new_node(&btree, level[start:start + count]))
			start += count
		}
		level = next
	}

	btree.root = level[0].index
	btree.info = level[0].info

	return
}

btree_destroy :: proc(btree: BTree) {
	delete(btree.nodes)
	delete(btree.leaves)
}

////////////////////////////////////////////////////////////////////////////////
// Insert
////////////////////////////////////////////////////////////////////////////////

btree_insert :: proc {
	btree_insert_string,
	btree_insert_rune,
}

// Inserts `data` before the rune at `index`. Returns the amount of runes and
// bytes that were inserted.
btree_insert_string :: proc(btree: ^BTree, index: Index, data: string) -> (runes: Index, bytes: _Offset) {
	index := index
	rest  := data
	for len(rest) > 0 {
		n := min(len(rest), BTREE_MAX_INSERT)

		// Don't cut a codepoint in half.
		for n > 1 && n < len(rest) && (rest[n] & 0xC0) == 0x80 {
			n -= 1
		}

		chunk := rest[:n]
		info  := btree_insert_bytes(btree, index, transmute([]u8)chunk)

		runes += info.chars
		bytes += info.bytes
		index += info.chars
		rest   = rest[n:]
	}
	return
}

btree_insert_rune :: proc(btree: ^BTree, index: Index, r: rune) -> _Offset {
	buf, n := utf8.encode_rune(r)
	btree_insert_bytes(btree, index, buf[:n])
	return _Offset(n)
}

// Inserts at most `BTREE_MAX_INSERT` bytes of valid utf8 (without NUL bytes) at
// the rune `index`.
btree_insert_bytes :: proc(btree: ^BTree, index: Index, data: []u8) -> (info: BTree_Info) {
	assert(0 <= index && index <= btree.chars, "index out of range")
	assert(len(data) <= BTREE_MAX_INSERT)
	for b in data {
		assert(b != 0, "NUL bytes are not supported")
	}

	if len(data) == 0 {
		return
	}

	info = btree_bytes_info(data)

	offset := btree_index_to_offset(btree, index)

	left, right, split := btree_insert_at_offset(btree, btree.root, btree.info, offset, data, info)

	btree.info = btree_info_add(btree.info, info)

	if split {
		root := btree_new_node(btree, []BTree_Child {
			{ index = btree.root, info = left, },
			right,
		})
		btree.root = root.index
		assert(root.info == btree.info)
	}

	return
}

// Inserts `data` at the byte `offset` of the subtree `index`, `total` is the
// info of that subtree before the insertion and `info` the info of `data`.
//
// If the subtree had to be split `split` is true, the subtree then only holds
// the left part (with info `left`) and `right` is a new sibling that has to be
// put directly after it. If it was not split the caller is responsible for
// adding `info` to the info of the subtree.
btree_insert_at_offset :: proc(
	btree:  ^BTree,
	index:  BTree_Index,
	total:  BTree_Info,
	offset: _Offset,
	data:   []u8,
	info:   BTree_Info,
) -> (left: BTree_Info, right: BTree_Child, split: bool) {
	if index.leaf {
		_ = total

		off     := int(offset)
		content := bytes.truncate_to_byte(btree.leaves[index.index].data[:], 0)
		size    := len(content)
		assert(off <= size)

		if size + len(data) <= BTREE_LEAF_SIZE {
			leaf := &btree.leaves[index.index]
			copy(leaf.data[off + len(data):], leaf.data[off:size])
			copy(leaf.data[off:],             data)
			return
		}

		// Leaf is full: merge the old content and the new data and spread it
		// over two leaves.
		buf: [BTREE_LEAF_SIZE + BTREE_MAX_INSERT]u8
		n := size + len(data)
		copy(buf[:off],             content[:off])
		copy(buf[off:],             data)
		copy(buf[off + len(data):], content[off:])

		mid := n / 2
		for mid < n && (buf[mid] & 0xC0) == 0x80 {
			mid += 1
		}
		assert(0 < mid && mid < n)

		right_leaf := BTree_Leaf { prev = index.index, next = btree.leaves[index.index].next, }
		copy(right_leaf.data[:], buf[mid:n])
		right_index := btree_alloc_leaf(btree, right_leaf) // might move `btree.leaves`

		leaf := &btree.leaves[index.index]
		if leaf.next >= 0 {
			btree.leaves[leaf.next].prev = right_index
		}
		leaf.next = right_index
		leaf.data = {}
		copy(leaf.data[:], buf[:mid])

		left  = btree_bytes_info(buf[:mid])
		right = {
			index = { index = right_index, leaf = true, },
			info  = btree_bytes_info(buf[mid:n]),
		}
		split = true
		return
	}

	children, count := btree_node_children(&btree.nodes[index.index], total)

	// Find the child. At the border between two children we prefer the end of
	// the left one, that makes appending cheap.
	child_i      := count - 1
	child_offset := offset
	for i in 0 ..< count - 1 {
		if child_offset <= children[i].info.bytes {
			child_i = i
			break
		}
		child_offset -= children[i].info.bytes
	}

	child := children[child_i]
	child_left, child_right, child_split := btree_insert_at_offset(btree, child.index, child.info, child_offset, data, info)

	if child_split {
		children[child_i].info = child_left
		copy(children[child_i + 2:count + 1], children[child_i + 1:count])
		children[child_i + 1] = child_right
		count += 1
	} else {
		children[child_i].info = btree_info_add(child.info, info)
	}

	if count <= BTREE_MAX_NODES {
		btree_node_set(&btree.nodes[index.index], children[:count])
		return
	}

	// Node overflowed (17 children), split it in two.
	mid  := (count + 1) / 2
	right = btree_new_node(btree, children[mid:count]) // might move `btree.nodes`
	btree_node_set(&btree.nodes[index.index], children[:mid])
	left  = btree_children_info(children[:mid])
	split = true
	return
}

////////////////////////////////////////////////////////////////////////////////
// Remove
////////////////////////////////////////////////////////////////////////////////

// Removes the runes in `start ..< end`.
//
// Deletion is lazy: emptied leaves and nodes are removed (and recycled), the
// root is collapsed if it ends up with a single child, but nodes and leaves
// that merely become small are not merged with their neighbours. The tree stays
// balanced and correct, it just might have a few sparse nodes after a lot of
// scattered deletes.
btree_remove_range :: proc(btree: ^BTree, start, end: Index) {
	assert(0 <= start && start <= end && end <= btree.chars, "range out of bounds")
	if start == end {
		return
	}

	start_offset := btree_index_to_offset(btree, start)
	end_offset   := btree_index_to_offset(btree, end)

	btree.info = btree_remove_at_offset(btree, btree.root, btree.info, start_offset, end_offset)

	// The whole text got removed and a node is left over: replace it by an
	// empty leaf.
	if btree.bytes == 0 && !btree.root.leaf {
		btree_free_node(btree, btree.root.index)
		btree.root = { index = btree_alloc_leaf(btree, { prev = -1, next = -1, }), leaf = true, }
	}

	// Collapse a root with only a single child.
	for !btree.root.leaf {
		node := &btree.nodes[btree.root.index]
		if btree_node_count(node) != 1 {
			break
		}
		child := node.children[0]
		btree_free_node(btree, btree.root.index)
		btree.root = child
	}
}

// Removes the bytes `start ..< end` (relative to the subtree) from the subtree
// `index` whose info before the removal is `total`, returns the new info.
//
// All descendants that became empty are freed. If the returned info is empty
// the subtree itself is still allocated and must be freed by the caller.
btree_remove_at_offset :: proc(btree: ^BTree, index: BTree_Index, total: BTree_Info, start, end: _Offset) -> BTree_Info {
	assert(0 <= start && start < end)

	if index.leaf {
		_ = total

		leaf   := &btree.leaves[index.index]
		size   := len(bytes.truncate_to_byte(leaf.data[:], 0))
		lo, hi := int(start), int(end)
		assert(hi <= size)

		copy(leaf.data[lo:], leaf.data[hi:size])
		for i in size - (hi - lo) ..< size {
			leaf.data[i] = 0
		}

		return btree_bytes_info(bytes.truncate_to_byte(leaf.data[:], 0))
	}

	children, count := btree_node_children(&btree.nodes[index.index], total)

	kept: [BTREE_MAX_NODES]BTree_Child
	n:    int
	pos:  _Offset

	for i in 0 ..< count {
		child       := children[i]
		child_start := pos
		child_end   := pos + child.info.bytes
		pos          = child_end

		// no overlap
		if end <= child_start || child_end <= start {
			kept[n] = child
			n      += 1
			continue
		}

		lo := max(start, child_start) - child_start
		hi := min(end,   child_end)   - child_start

		// child is removed completely
		if lo == 0 && hi == child.info.bytes {
			btree_free_subtree(btree, child.index)
			continue
		}

		child.info = btree_remove_at_offset(btree, child.index, child.info, lo, hi)
		if child.info.bytes == 0 {
			btree_free_single(btree, child.index)
			continue
		}

		kept[n] = child
		n      += 1
	}

	if n == 0 {
		return {}
	}

	btree_node_set(&btree.nodes[index.index], kept[:n])
	return btree_children_info(kept[:n])
}

////////////////////////////////////////////////////////////////////////////////
// Queries
////////////////////////////////////////////////////////////////////////////////

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

////////////////////////////////////////////////////////////////////////////////
// Iteration
////////////////////////////////////////////////////////////////////////////////

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

////////////////////////////////////////////////////////////////////////////////
// Conversion / debugging
////////////////////////////////////////////////////////////////////////////////

@(require_results)
graph_dot :: proc(btree: BTree, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)

	_graph_dot :: proc(b: ^strings.Builder, btree: BTree, index, parent: BTree_Index) {
		if index.leaf {
			if index != parent {
				fmt.sbprintfln(b, "\ti%v -> l%v;", parent.index, index.index)
			}
			return
		} else {
			if index != parent {
				fmt.sbprintfln(b, "\ti%v -> i%v;", parent.index, index.index)
			}
		}

		node  := btree.nodes[index.index]
		count := btree_node_count(&node)

		for i in 0 ..< count {
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
btree_offset_to_index :: proc(btree: ^BTree, offset: _Offset) -> (index: Index) {
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

	for _, sub_offset in data {
		if index == 0 {
			return offset + _Offset(sub_offset)
		}
		index -= 1
	}

	return offset + _Offset(len(data))
}

// Asserts all the invariants of the tree (see `BTree`), returns the depth of
// the leaves (0 if the root is a leaf). Meant for tests and debugging, it walks
// the whole tree.
btree_check :: proc(btree: ^BTree) -> (depth: int) {
	leaves     := make([dynamic]i32, context.temp_allocator)
	leaf_depth := -1

	check :: proc(btree: ^BTree, index: BTree_Index, expected: BTree_Info, depth: int, leaf_depth: ^int, leaves: ^[dynamic]i32) {
		if index.leaf {
			leaf    := &btree.leaves[index.index]
			content := bytes.truncate_to_byte(leaf.data[:], 0)

			for b in leaf.data[len(content):] {
				assert(b == 0, "stray bytes after leaf terminator")
			}
			assert(utf8.valid_string(string(content)),   "leaf holds invalid utf8")
			assert(btree_bytes_info(content) == expected, "leaf info does not match its content")

			if leaf_depth^ < 0 {
				leaf_depth^ = depth
			} else {
				assert(leaf_depth^ == depth, "leaves are at different depths")
			}

			append(leaves, index.index)
			return
		}

		node            := btree.nodes[index.index]
		children, count := btree_node_children(&node, expected)
		assert(count <= BTREE_MAX_NODES)

		for i in 0 ..< count {
			assert(children[i].info.bytes > 0, "empty child")
			check(btree, children[i].index, children[i].info, depth + 1, leaf_depth, leaves)
		}
	}

	check(btree, btree.root, btree.info, 0, &leaf_depth, &leaves)

	// the leaf list has to match the tree order
	for leaf, i in leaves {
		prev := i32(-1)
		next := i32(-1)
		if i > 0 {
			prev = leaves[i - 1]
		}
		if i + 1 < len(leaves) {
			next = leaves[i + 1]
		}
		assert(btree.leaves[leaf].prev == prev, "broken leaf list (prev)")
		assert(btree.leaves[leaf].next == next, "broken leaf list (next)")
	}

	return leaf_depth
}

////////////////////////////////////////////////////////////////////////////////
// Test helpers
////////////////////////////////////////////////////////////////////////////////

@(private = "file")
_test_text :: proc(btree: ^BTree) -> string {
	b := strings.builder_make(context.temp_allocator)
	btree_to_string(btree, &b)
	return strings.to_string(b)
}

@(private = "file")
_test_runes_to_string :: proc(runes: []rune) -> string {
	b := strings.builder_make(context.temp_allocator)
	for r in runes {
		strings.write_rune(&b, r)
	}
	return strings.to_string(b)
}

// `s` without the bytes `lo ..< hi`
@(private = "file")
_test_cut :: proc(s: string, lo, hi: int) -> string {
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, s[:lo])
	strings.write_string(&b, s[hi:])
	return strings.to_string(b)
}

@(private = "file")
_test_rand :: proc(state: ^u64, n: int) -> int {
	x := state^
	x ~= x << 13
	x ~= x >> 7
	x ~= x << 17
	state^ = x
	return int(x % u64(n))
}

// Checks the invariants and that the tree holds exactly `expected`.
@(private = "file")
_test_expect_tree :: proc(t: ^testing.T, btree: ^BTree, expected: string, loc := #caller_location) {
	btree_check(btree)
	testing.expect_value(t, _test_text(btree),                    expected,                          loc = loc)
	testing.expect_value(t, int(btree.chars),                     strings.rune_count(expected),      loc = loc)
	testing.expect_value(t, int(btree.lines),                     strings.count(expected, "\n"),     loc = loc)
	testing.expect_value(t, int(btree.bytes),                     len(expected),                     loc = loc)
}

// Compares the tree against a reference model (a slice of runes), also checks
// the line queries and the iterators.
@(private = "file")
_test_verify :: proc(t: ^testing.T, btree: ^BTree, ref: []rune, state: ^u64) {
	_test_expect_tree(t, btree, _test_runes_to_string(ref))

	lines := 0
	for r in ref {
		if r == '\n' {
			lines += 1
		}
	}

	// line -> index
	line       := _test_rand(state, lines + 1)
	start, seen := 0, 0
	for seen < line {
		if ref[start] == '\n' {
			seen += 1
		}
		start += 1
	}
	testing.expect_value(t, int(btree_line_to_index(btree, line)), start)

	// index -> line
	idx           := _test_rand(state, len(ref) + 1)
	expected_line := 0
	for r in ref[:idx] {
		if r == '\n' {
			expected_line += 1
		}
	}
	testing.expect_value(t, btree_index_to_line(btree, Index(idx)), expected_line)

	// index <-> offset
	testing.expect_value(t, btree_offset_to_index(btree, btree_index_to_offset(btree, Index(idx))), Index(idx))

	// forwards
	iter := btree_iterator(btree, 0)
	i    := 0
	for r in btree_iter(&iter) {
		if i >= len(ref) || r != ref[i] {
			testing.expect(t, false, "forward iteration differs from reference")
			break
		}
		i += 1
	}
	testing.expect_value(t, i, len(ref))

	// backwards
	iter = btree_iterator(btree, btree.chars)
	i    = len(ref)
	for r in btree_iter(&iter, back = true) {
		i -= 1
		if i < 0 || r != ref[i] {
			testing.expect(t, false, "backward iteration differs from reference")
			break
		}
	}
	testing.expect_value(t, i, 0)
}

////////////////////////////////////////////////////////////////////////////////
// Tests
////////////////////////////////////////////////////////////////////////////////

@(test)
btree_test_iter :: proc(t: ^testing.T) {
	// some utf8 encoded text for the tests: öäöäöäöäöäöäöüüüüüüßßßßßaâââ

	data  := #load(#file, string)

	fills := [?]int { 1, 7, BTREE_LEAF_SIZE * 3 / 4 }
	for fill in fills {
		btree := btree_build(data, context.allocator, fill)
		defer btree_destroy(btree)

		iter := btree_iterator(&btree, 0)

		b := strings.builder_make(context.temp_allocator)
		for r in btree_iter(&iter) {
			strings.write_rune(&b, r)
		}

		assert(strings.to_string(b) == data)
	}
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

	fills := [?]int { 1, 2, 3, BTREE_LEAF_SIZE * 3 / 4 }
	for fill in fills {
		btree := btree_build(A + B, context.allocator, fill)
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
}

@(test)
btree_test_to_string :: proc(t: ^testing.T) {
	data  := #load(#file, string)

	fills := [?]int { 1, 7, BTREE_LEAF_SIZE * 3 / 4 }
	for fill in fills {
		btree := btree_build(data, context.allocator, fill)
		defer btree_destroy(btree)

		b := strings.builder_make(context.temp_allocator)
		btree_to_string(&btree, &b)

		assert(strings.to_string(b) == data)
	}
}

@(test)
btree_test_build_edge_cases :: proc(t: ^testing.T) {
	texts := [?]string { "", "a", "ö", "日本語", "line\n", "\n\n\n", "😀x😀y😀", "no newline at all, but long enough to need a few leaves" }
	fills := [?]int    { 1, 4, BTREE_LEAF_SIZE - 3 }

	for fill in fills {
		for text in texts {
			btree := btree_build(text, context.allocator, fill)
			_test_expect_tree(t, &btree, text)
			btree_destroy(btree)
		}
	}
}

@(test)
btree_test_insert_basic :: proc(t: ^testing.T) {
	fills := [?]int { 1, 3, BTREE_LEAF_SIZE * 3 / 4 }
	for fill in fills {
		btree := btree_build("hello world", context.allocator, fill)
		defer btree_destroy(btree)

		btree_insert(&btree, 0, "[")
		btree_insert(&btree, btree.chars, "]")
		btree_insert(&btree, 6, ",")
		_test_expect_tree(t, &btree, "[hello, world]")

		btree_insert(&btree, 7, 'X')
		_test_expect_tree(t, &btree, "[hello,X world]")

		runes, written := btree_insert_string(&btree, 0, "ö日")
		testing.expect_value(t, int(runes),   2)
		testing.expect_value(t, int(written), 5)
		_test_expect_tree(t, &btree, "ö日[hello,X world]")

		btree_insert(&btree, 3, "\n\n")
		_test_expect_tree(t, &btree, "ö日[\n\nhello,X world]")
	}
}

@(test)
btree_test_insert_into_empty :: proc(t: ^testing.T) {
	btree := btree_build("", context.allocator)
	defer btree_destroy(btree)

	_test_expect_tree(t, &btree, "")

	btree_insert(&btree, 0, "")
	_test_expect_tree(t, &btree, "")

	btree_insert(&btree, 0, "abc")
	_test_expect_tree(t, &btree, "abc")
}

@(test)
btree_test_insert_large_string :: proc(t: ^testing.T) {
	b := strings.builder_make(context.temp_allocator)
	for i in 0 ..< 500 {
		fmt.sbprintf(&b, "line %d: öäü 日本語\n", i)
	}
	text := strings.to_string(b)

	btree := btree_build("", context.allocator)
	defer btree_destroy(btree)

	runes, written := btree_insert_string(&btree, 0, text)
	testing.expect_value(t, int(runes),   strings.rune_count(text))
	testing.expect_value(t, int(written), len(text))
	_test_expect_tree(t, &btree, text)

	// into the middle (at the start of a line)
	insert := "<<inserted\nin the middle>>"
	at     := strings.index(text, "line 250:")
	btree_insert(&btree, Index(strings.rune_count(text[:at])), insert)

	eb := strings.builder_make(context.temp_allocator)
	strings.write_string(&eb, text[:at])
	strings.write_string(&eb, insert)
	strings.write_string(&eb, text[at:])
	_test_expect_tree(t, &btree, strings.to_string(eb))
}

// Typing at the end of the document, this grows the tree to a depth of at least
// 3 which exercises splitting of nodes and of the root.
@(test)
btree_test_typing_append :: proc(t: ^testing.T) {
	btree := btree_build("", context.allocator)
	defer btree_destroy(btree)

	ref := make([dynamic]u8)
	defer delete(ref)

	N :: 20000
	for i in 0 ..< N {
		c := rune(u8('a' + i % 26))
		if i % 40 == 39 {
			c = '\n'
		}
		btree_insert(&btree, btree.chars, c)
		append(&ref, u8(c))

		if i % 997 == 0 {
			btree_check(&btree)
		}
	}

	depth := btree_check(&btree)
	testing.expect(t, depth >= 3, "expected the tree to have grown to at least 3 levels")
	_test_expect_tree(t, &btree, string(ref[:]))
}

// Typing at the start of the document.
@(test)
btree_test_typing_prepend :: proc(t: ^testing.T) {
	btree := btree_build("", context.allocator)
	defer btree_destroy(btree)

	typed := make([dynamic]u8)
	defer delete(typed)

	N :: 5000
	for i in 0 ..< N {
		c := rune(u8('a' + i % 26))
		if i % 40 == 39 {
			c = '\n'
		}
		btree_insert(&btree, 0, c)
		append(&typed, u8(c))
	}

	b := strings.builder_make(context.temp_allocator)
	for i := len(typed) - 1; i >= 0; i -= 1 {
		strings.write_byte(&b, typed[i])
	}
	_test_expect_tree(t, &btree, strings.to_string(b))
}

@(test)
btree_test_remove_ascii :: proc(t: ^testing.T) {
	text := "The quick brown fox\njumps over\nthe lazy dog\nand runs away\n"
	n    := len(text)

	Range :: struct { lo, hi: int, }
	ranges := [?]Range {
		{ 0, 0 }, { 0, 1 }, { 0, 7 }, { 3, 4 }, { 5, 25 }, { 19, 20 }, { 18, 21 },
		{ n - 1, n }, { n - 5, n }, { 10, n - 10 }, { 0, n }, { 1, n - 1 },
	}
	fills := [?]int { 1, 2, 5, 20, BTREE_LEAF_SIZE - 3 }

	for fill in fills {
		for r in ranges {
			btree := btree_build(text, context.allocator, fill)
			btree_remove_range(&btree, Index(r.lo), Index(r.hi))
			_test_expect_tree(t, &btree, _test_cut(text, r.lo, r.hi))
			btree_destroy(btree)
		}
	}
}

@(test)
btree_test_remove_unicode :: proc(t: ^testing.T) {
	text  := "aö日😀b\nößß日\n😀😀"
	runes := make([dynamic]rune, context.temp_allocator)
	for r in text {
		append(&runes, r)
	}
	testing.expect_value(t, len(runes), 13)

	Range :: struct { lo, hi: int, }
	ranges := [?]Range { { 1, 3 }, { 0, 2 }, { 3, 6 }, { 5, 6 }, { 9, 13 }, { 0, 13 }, { 12, 13 }, { 2, 11 } }
	fills  := [?]int   { 1, 2, 5, BTREE_LEAF_SIZE - 3 }

	for fill in fills {
		for r in ranges {
			btree := btree_build(text, context.allocator, fill)

			kept := make([dynamic]rune, context.temp_allocator)
			append(&kept, ..runes[:r.lo])
			append(&kept, ..runes[r.hi:])

			btree_remove_range(&btree, Index(r.lo), Index(r.hi))
			_test_expect_tree(t, &btree, _test_runes_to_string(kept[:]))
			btree_destroy(btree)
		}
	}
}

@(test)
btree_test_remove_one_by_one :: proc(t: ^testing.T) {
	text  := "The quick brown fox\njumps over\nthe lazy dog\nand runs away\nand then some more text to fill a few more leaves\n"
	fills := [?]int { 1, 4, BTREE_LEAF_SIZE - 3 }

	for fill in fills {
		// from the front
		{
			btree := btree_build(text, context.allocator, fill)
			defer btree_destroy(btree)

			expected := text
			for btree.chars > 0 {
				btree_remove_range(&btree, 0, 1)
				expected = expected[1:]
				_test_expect_tree(t, &btree, expected)
			}

			// an emptied tree is still usable
			btree_insert(&btree, 0, "again")
			_test_expect_tree(t, &btree, "again")
		}

		// from the back
		{
			btree := btree_build(text, context.allocator, fill)
			defer btree_destroy(btree)

			expected := text
			for btree.chars > 0 {
				btree_remove_range(&btree, btree.chars - 1, btree.chars)
				expected = expected[:len(expected) - 1]
				_test_expect_tree(t, &btree, expected)
			}

			btree_insert(&btree, 0, "again")
			_test_expect_tree(t, &btree, "again")
		}
	}
}

// Removed leaves / nodes are recycled, repeatedly emptying and refilling must
// not make the storage grow.
@(test)
btree_test_storage_reuse :: proc(t: ^testing.T) {
	b := strings.builder_make(context.temp_allocator)
	for i in 0 ..< 200 {
		fmt.sbprintf(&b, "line %d of the text\n", i)
	}
	text := strings.to_string(b)

	btree := btree_build(text, context.allocator)
	defer btree_destroy(btree)

	leaves_after_second, nodes_after_second: int

	for cycle in 0 ..< 20 {
		btree_remove_range(&btree, 0, btree.chars)
		_test_expect_tree(t, &btree, "")

		btree_insert_string(&btree, 0, text)
		_test_expect_tree(t, &btree, text)

		if cycle == 1 {
			leaves_after_second = len(btree.leaves)
			nodes_after_second  = len(btree.nodes)
		}
	}

	testing.expect(t, len(btree.leaves) <= leaves_after_second, "leaves are not being reused")
	testing.expect(t, len(btree.nodes)  <= nodes_after_second,  "nodes are not being reused")
}

// Random inserts and removes checked against a simple model, with leaves of
// different sizes. Covers leaf splits, node splits, removal of whole subtrees,
// root collapsing, multi-byte runes and the leaf list.
@(test)
btree_test_random_edits :: proc(t: ^testing.T) {
	fills := [?]int { 1, 7, BTREE_LEAF_SIZE * 3 / 4 }
	for fill, i in fills {
		_test_random_edits(t, fill, u64(0x9E3779B97F4A7C15) + u64(i))
	}
}

@(private = "file")
_test_random_edits :: proc(t: ^testing.T, fill: int, seed: u64) {
	alphabet := [?]rune { 'a', 'b', 'c', ' ', '\n', '\n', 'ö', 'ß', '日', '本', '😀' }
	state    := seed

	initial := "seed text\nfor the\ntree"

	btree := btree_build(initial, context.allocator, fill)
	defer btree_destroy(btree)

	ref := make([dynamic]rune)
	defer delete(ref)
	for r in initial {
		append(&ref, r)
	}

	scratch: [dynamic]rune
	defer delete(scratch)

	OPS :: 1500
	for op in 0 ..< OPS {
		insert_chance := 70 if op < OPS / 2 else 35
		do_insert     := len(ref) == 0 || _test_rand(&state, 100) < insert_chance

		if do_insert {
			at    := _test_rand(&state, len(ref) + 1)
			count := _test_rand(&state, 70) + 1
			if _test_rand(&state, 20) == 0 {
				count *= 5
			}

			clear(&scratch)
			b := strings.builder_make(context.temp_allocator)
			for _ in 0 ..< count {
				r := alphabet[_test_rand(&state, len(alphabet))]
				append(&scratch, r)
				strings.write_rune(&b, r)
			}
			text := strings.to_string(b)

			runes, written := btree_insert_string(&btree, Index(at), text)
			testing.expect_value(t, int(runes),   count)
			testing.expect_value(t, int(written), len(text))

			old := len(ref)
			resize(&ref, old + count)
			copy(ref[at + count:], ref[at:old])
			copy(ref[at:],         scratch[:])
		} else {
			lo   := _test_rand(&state, len(ref) + 1)
			span := _test_rand(&state, min(len(ref) - lo, 90) + 1)
			if op % 500 == 499 { // now and then remove everything
				lo   = 0
				span = len(ref)
			}
			hi := lo + span

			btree_remove_range(&btree, Index(lo), Index(hi))
			copy(ref[lo:], ref[hi:])
			resize(&ref, len(ref) - span)
		}

		if op % 5 == 0 || op > OPS - 20 {
			_test_verify(t, &btree, ref[:], &state)
		}
		free_all(context.temp_allocator)
	}

	_test_verify(t, &btree, ref[:], &state)
}

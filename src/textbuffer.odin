// TODO: cursor is fucked, FIX PLZ
package main

import "core:container/intrusive/list"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strings"
import "core:unicode/utf8"
import t "termcl"

// padding between bottom and top edges for cursor scrolling
SPACE_FROM_EDGES :: 5
// width for the line numbering column
LINE_WIDTH :: 7

TextBuffer_Row :: struct {
	node: list.Node,
	str:  string,
}

TextBuffer :: struct {
	filepath:             string,
	win:                  t.Window,
	linewin:              t.Window,
	rows:                 list.List,
	curr_row:             ^list.Node,
	rowlen:               uint,
	view_start, view_end: uint,
	col, row:             uint,
}

textbuffer_new :: proc(filepath: string) -> (tb: TextBuffer, success: bool) {
	// -- convert text file into rows
	file_contents: []string
	filepath := filepath
	if filepath != "" && os.exists(filepath) {
		data := os.read_entire_file(filepath) or_return
		file_contents = strings.split(string(data), "\n")
	}

	// -- initialize struct fields
	termsize := t.get_term_size()
	rows: list.List
	rowlen: uint
	if len(file_contents) != 0 {
		for row in file_contents {
			newrow := new(TextBuffer_Row)
			newrow^ = TextBuffer_Row {
				str = row,
			}
			list.push_back(&rows, &newrow.node)
			rowlen += 1
		}
	} else {
		newrow := new(TextBuffer_Row)
		newrow^ = TextBuffer_Row {
			str = "",
		}
		list.push_back(&rows, &newrow.node)
		rowlen += 1
	}

	// -- create a text view that fits the window
	return TextBuffer {
			filepath = filepath,
			rows = rows,
			rowlen = rowlen,
			win = t.init_window(0, LINE_WIDTH, termsize.h - 1, termsize.w - LINE_WIDTH),
			linewin = t.init_window(0, 0, termsize.h - 1, LINE_WIDTH),
			curr_row = rows.head,
			view_end = termsize.h,
		},
		true
}

textbuffer_free :: proc(tb: ^TextBuffer) -> bool {
	t.destroy_window(&tb.win)
	t.destroy_window(&tb.linewin)
	for !list.is_empty(&tb.rows) {
		// row := 
		list.pop_front(&tb.rows)
		// if delete(row.str) != .None do return false
	}

	return true
}

// updates the text_view and makes sure that the cursor is still visible on the window
// cur_y: cursor coordinates relative to view buffer
@(private)
textbuffer_view_update :: proc(tb: ^TextBuffer, cur_y: uint) {
	winsize := t.get_window_size(&tb.win)

	// -- make sure the cursor is still inside the view
	if cur_y >= winsize.h {
		tb.view_start = tb.row - winsize.h + SPACE_FROM_EDGES
	} else if cur_y < 0 {
		tb.view_start = tb.row - winsize.h - SPACE_FROM_EDGES
	} else if tb.view_start < winsize.h {
		tb.view_start = tb.row - winsize.h + SPACE_FROM_EDGES
	}
	if tb.view_start < 0 do tb.view_start = 0


	tb.view_end = tb.view_start + winsize.h
	if tb.view_end >= tb.rowlen do tb.view_end = tb.rowlen - 1
}


textbuffer_fit_newsize :: proc(tb: ^TextBuffer) {
	termsize := t.get_term_size()
	termsize.h -= 1
	t.resize_window(&tb.win, termsize.h, termsize.w)
	t.resize_window(&tb.linewin, termsize.h, LINE_WIDTH)

	cur_y, _ := textbuffer_get_cursor_coordinates(tb)
	textbuffer_view_update(tb, cur_y)
}

textbuffer_save_to_file :: proc(tb: TextBuffer) -> bool {
	if tb.filepath == "" do return false
	file, err := os.open(tb.filepath, os.O_CREATE | os.O_WRONLY, 0o644)
	if err != os.ERROR_NONE do return false
	defer os.close(file)

	sb := strings.builder_make()
	defer strings.builder_destroy(&sb)

	iter := list.iterator_head(tb.rows, TextBuffer_Row, "node")
	for row in list.iterate_next(&iter) {
		strings.write_string(&sb, row.str)
		strings.write_rune(&sb, '\n')
	}

	file_content := strings.to_string(sb)
	_, err = os.write_string(file, file_content)
	return err == os.ERROR_NONE
}

textbuffer_row_at :: proc(tb: ^TextBuffer, idx: uint) -> ^TextBuffer_Row {
	curr_row: ^TextBuffer_Row
	count: uint
	switch {
	case idx == tb.row:
		curr_iter := list.iterator_from_node(tb.curr_row, TextBuffer_Row, "node")
		curr_row, _ = list.iterate_next(&curr_iter)

	case tb.rowlen / 2 < idx:
		tail := list.iterator_tail(tb.rows, TextBuffer_Row, "node")
		count = tb.rowlen
		for row in list.iterate_prev(&tail) {
			if count == idx {
				curr_row = row
				break
			}
			count -= 1
		}

	case:
		head := list.iterator_head(tb.rows, TextBuffer_Row, "node")
		for row in list.iterate_next(&head) {
			if count == idx {
				curr_row = row
				break
			}
			count += 1
		}
	}

	return curr_row
}

// handles how cursor ought to move within the textbuffer and to prevent segfaults
textbuffer_cursor_move :: proc(tb: ^TextBuffer, dir: Direction) {
	winsize := t.get_window_size(&tb.win)
	cur_y, _ := textbuffer_get_cursor_coordinates(tb)

	scroll_up_if_on_edge :: #force_inline proc(tb: ^TextBuffer, cur_y: uint) {
		if cur_y <= SPACE_FROM_EDGES do textbuffer_view_move(tb, .Up)
	}

	scroll_down_if_on_edge :: #force_inline proc(tb: ^TextBuffer, cur_y: uint, maxy: uint) {
		if cur_y >= maxy - 1 - SPACE_FROM_EDGES do textbuffer_view_move(tb, .Down)
	}

	switch dir {
	case .Up:
		if tb.row > 0 {
			tb.row -= 1
			tb.curr_row = tb.curr_row.prev
		}
		scroll_up_if_on_edge(tb, cur_y)

	case .Down:
		if tb.row < tb.rowlen - 1 {
			tb.row += 1
			tb.curr_row = tb.curr_row.next
		}
		scroll_down_if_on_edge(tb, cur_y, winsize.h)

	case .Left:
		if tb.col > 0 {
			tb.col -= 1
			// wrap around to previous line
		} else if tb.row > 0 {
			tb.row -= 1
			tb.curr_row = tb.curr_row.prev
			tb.col = len(textbuffer_row_at(tb, tb.row).str)
			scroll_up_if_on_edge(tb, cur_y)
		}

	case .Right:
		if int(tb.col) < len(textbuffer_row_at(tb, tb.row).str) {
			tb.col += 1
			// wrap around to next line
		} else if tb.row < tb.rowlen - 1 {
			tb.row += 1
			tb.col = 0
			tb.curr_row = tb.curr_row.next
			scroll_down_if_on_edge(tb, cur_y, winsize.h)
		}
	}

	// -- prevent cursor from overflowing row
	collen: uint = len(textbuffer_row_at(tb, tb.row).str)
	if tb.col > collen {
		tb.col = collen if collen >= 0 else 0
	}
}

// inserts a new char into the current row and column in the textbuffer
textbuffer_append_char :: proc(tb: ^TextBuffer, char: rune) {
	curr_row := textbuffer_row_at(tb, tb.row)

	char_str := utf8.runes_to_string([]rune{char})
	defer delete(char_str)

	switch {
	// insert at the start
	case len(curr_row.str) == 0:
		curr_row.str = strings.clone(char_str)
	// insert in the middle
	case int(tb.col) == len(curr_row.str):
		curr_row.str = strings.join([]string{curr_row.str, char_str}, "")
	// insert at the end
	case int(tb.col) < len(curr_row.str):
		curr_row.str = strings.join(
			[]string{curr_row.str[:tb.col], char_str, curr_row.str[tb.col:]},
			"",
		)
	case:
		panic("unknown case found")
	}

	// go to next col after insertion is done
	textbuffer_cursor_move(tb, .Right)
}

// removes char in the current row and column
textbuffer_remove_char :: proc(tb: ^TextBuffer) {
	curr_row := textbuffer_row_at(tb, tb.row)
	if tb.col > 0 {
		curr_row.str = strings.join([]string{curr_row.str[:tb.col - 1], curr_row.str[tb.col:]}, "")
		textbuffer_cursor_move(tb, .Left)
	} else if tb.row > 0 {
		curr_row := textbuffer_row_at(tb, tb.row)
		prev_row := textbuffer_row_at(tb, tb.row - 1)
		// place cursor at the end of line before merge occurred
		// merge lines
		new_col: uint = len(prev_row.str)
		prev_row.str = strings.join([]string{prev_row.str, curr_row.str}, "")
		textbuffer_remove_row(tb)
		tb.col = new_col
	}
}

// inserts a new row and sets cursor to the start of that row
// TODO: fix inserting on end of file (aka tail) making program crash
textbuffer_insert_row :: proc(tb: ^TextBuffer) {
	new_row := new(TextBuffer_Row)
	new_row^ = TextBuffer_Row {
		str = "",
	}

	if tb.curr_row.next == nil {
		tb.curr_row.next = &new_row.node
		new_row.node.prev = tb.curr_row
	} else {
		tb.curr_row.next.prev = &new_row.node
		new_row.node.prev = tb.curr_row
		new_row.node.next = tb.curr_row.next
		tb.curr_row.next = &new_row.node
	}

	tb.rowlen += 1
	textbuffer_cursor_move(tb, .Down)
	tb.col = 0
}

textbuffer_breakline :: proc(tb: ^TextBuffer) {
	if tb.row < tb.rowlen {
		curr_row := textbuffer_row_at(tb, tb.row)
		first_chunk := curr_row.str[:tb.col]
		second_chunk := curr_row.str[tb.col:]
		curr_row.str = first_chunk

		textbuffer_insert_row(tb)
		new_row := textbuffer_row_at(tb, tb.row)
		new_row.str = strings.clone(second_chunk)
	} else {
		textbuffer_insert_row(tb)
	}
}

// removes row and sets cursor to the start of old previous row
textbuffer_remove_row :: proc(tb: ^TextBuffer) {
	// remove row
	new_curr_row := tb.curr_row.prev
	list.remove(&tb.rows, tb.curr_row)
	tb.row -= 1
	// make previous row the current row
	tb.curr_row = new_curr_row
	tb.rowlen -= 1
	tb.col = 0
}

// returns the cursor coordinates relative to the start of the view buffer
textbuffer_get_cursor_coordinates :: #force_inline proc(tb: ^TextBuffer) -> (y, x: uint) {
	return tb.row - tb.view_start, tb.col
}

Direction :: enum {
	Up,
	Down,
	Left,
	Right,
}

@(private)
textbuffer_draw_linenum :: proc(tb: ^TextBuffer) {
	t.clear(&tb.linewin, .Everything)
	defer t.blit(&tb.linewin)

	line_num_bytes: [20]u8
	linenum_end := tb.view_end if tb.view_end < tb.rowlen else tb.rowlen

	for n in tb.view_start ..< linenum_end {
		if n == tb.row {
			// TODO: change line to grey
			t.set_color_style(&tb.linewin, .Black, .White)

			cur_y, _ := textbuffer_get_cursor_coordinates(tb)
			t.move_cursor(&tb.linewin, cur_y, 0)
			t.clear_line(&tb.linewin, .Everything)
		} else {
			t.set_color_style(&tb.linewin, .White, nil)
		}
		defer t.reset_styles(&tb.linewin)


		mem.zero_slice(line_num_bytes[:])
		line_num := fmt.bprintf(line_num_bytes[:], "%d  ", n + 1)
		t.move_cursor(&tb.linewin, n - tb.view_start, LINE_WIDTH - len(line_num))
		t.write(&tb.linewin, line_num)
	}
}

// TODO: handle tabs
// TODO: scroll X axis when tb.col > win_width
textbuffer_draw :: proc(tb: ^TextBuffer) {
	t.clear(&tb.win, .Everything)

	// -- draw current line's highlight
	cur_y, _ := textbuffer_get_cursor_coordinates(tb)
	winsize := t.get_window_size(&tb.win)
	t.set_color_style(&tb.win, .Black, .White)
	t.move_cursor(&tb.win, cur_y, 0)
	t.clear_line(&tb.win, .Everything)
	t.reset_styles(&tb.win)

	// -- draw buffer content
	row_start := textbuffer_row_at(tb, tb.view_start)
	iter := list.iterator_from_node(&row_start.node, TextBuffer_Row, "node")
	row_idx: uint
	for row in list.iterate_next(&iter) {
		defer row_idx += 1
		if tb.view_start + row_idx > tb.view_end do break

		if &row.node == tb.curr_row {
			t.set_color_style(&tb.win, .Black, .White)
		} else {
			t.set_color_style(&tb.win, .Black, nil)
		}
		defer t.reset_styles(&tb.win)

		t.move_cursor(&tb.win, row_idx, 0)

		for char in row.str {
			if char == '\t' {
				t.write(&tb.win, ' ')
			} else {
				t.write(&tb.win, char)
			}
		}
	}

	// -- draw cursor
	t.set_text_style(&tb.win, {.Inverted})
	row := textbuffer_row_at(tb, tb.row).str
	r: byte
	switch {
	case tb.col > len(row) - 1:
		r = ' '
	case row[tb.col] == '\t':
		r = ' '
	case:
		r = row[tb.col]
	}

	t.move_cursor(&tb.win, cur_y, tb.col)
	t.write(&tb.win, cast(rune)r)
	t.reset_styles(&tb.win)
	textbuffer_draw_linenum(tb)
}

// creates a view slice with the contents that ought to be displayed for the current cursor position.
// only takes .Up and .Down as directions. Other directions will be ignored
@(private)
textbuffer_view_move :: proc(tb: ^TextBuffer, dir: Direction) {
	winsize := t.get_window_size(&tb.win)
	#partial switch dir {
	case .Up:
		if tb.view_start > 0 {tb.view_start -= 1} else {return}
	case .Down:
		if tb.view_start + winsize.h < tb.rowlen {tb.view_start += 1} else {return}
	case:
		return
	}

	tb.view_end = tb.view_start + winsize.h
	if tb.view_end > tb.rowlen do tb.view_end = tb.rowlen
}


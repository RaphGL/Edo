package main

import "core:c"
import "core:os"
import "core:slice"
import "core:strings"
import "core:unicode/utf8"
import nc "ncurses/src"

// padding between bottom and top edges for cursor scrolling
SPACE_FROM_EDGES :: 5

TextBuffer :: struct {
	filepath:    string,
	win:         ^nc.Window,
	linenum_win: ^nc.Window,
	rows:        [dynamic]string,
	start_view:  c.int, // the first row in view
	view:        []string,
	col, row:    c.int,
}

textbuffer_new :: proc(filepath: string) -> (tb: TextBuffer, success: bool) {
	// -- convert text file into rows
	file_contents: []string
	if filepath != "" {
		data := os.read_entire_file(filepath) or_return
		file_contents = strings.split(string(data), "\n")
	}

	// -- initialize struct fields
	h, w := nc.getmaxyx(nc.stdscr)
	bufwin := nc.newwin(h - 1, w, 0, 0)
	rows: [dynamic]string
	if len(file_contents) != 0 {
		rows = slice.clone_to_dynamic(file_contents)
	} else {
		rows = make([dynamic]string)
		append(&rows, "")
	}

	// -- create a text view that fits the window
	view := rows[:h] if len(rows) > int(h) else rows[:]
	return TextBuffer{filepath = filepath, rows = rows, win = bufwin, view = view}, true
}

textbuffer_free :: proc(tb: TextBuffer) -> bool {
	nc.werase(tb.win)
	nc.delwin(tb.win)
	for row in tb.rows {
		if delete(row) != .None do return false
	}

	return delete(tb.rows) == .None
}

textbuffer_fit_newsize :: proc(tb: ^TextBuffer) {
	win_h, win_w := nc.getmaxyx(nc.stdscr)
	win_h -= 1
	nc.wresize(tb.win, win_h, win_w)

	cur_y, _ := textbuffer_get_cursor_coordinates(tb^)
	textbuffer_view_update(tb, cur_y)
}

// TODO
textbuffer_save_to_file :: proc(tb: TextBuffer, filepath: string) -> bool

// inserts a new char into the current row and column in the textbuffer
textbuffer_append_char :: proc(tb: ^TextBuffer, char: rune) {
	curr_row := tb.rows[tb.row]

	char_str := utf8.runes_to_string([]rune{char})
	defer delete(char_str)

	switch {
	// insert at the start
	case len(curr_row) == 0:
		curr_row = strings.clone(char_str)
	// insert in the middle
	case int(tb.col) == len(curr_row):
		curr_row = strings.join([]string{curr_row, char_str}, "")
	// insert at the end
	case int(tb.col) < len(curr_row):
		curr_row = strings.join([]string{curr_row[:tb.col], char_str, curr_row[tb.col:]}, "")
	case:
		panic("unknown case found")
	}

	// go to next col after insertion is done
	tb.col += 1
	tb.rows[tb.row] = curr_row
}

// removes char in the current row and column
textbuffer_remove_char :: proc(tb: ^TextBuffer) {
	curr_row := tb.rows[tb.row]
	if tb.col > 0 {
		curr_row = strings.join([]string{curr_row[:tb.col - 1], curr_row[tb.col:]}, "")
		tb.col -= 1
	} else {
		// TODO: merge lines when chars are removed from the beginning of a row
		tb.row -= 1
		curr_row = tb.rows[tb.row]
		tb.col = c.int(len(curr_row))
	}

	tb.rows[tb.row] = curr_row
}

// TODO: insert a new row after the current row
textbuffer_insert_row :: proc(tb: ^TextBuffer)

// TODO: remove current row from textbuffer
textbuffer_remove_row :: proc(tb: ^TextBuffer)

textbuffer_get_cursor_coordinates :: #force_inline proc(tb: TextBuffer) -> (y, x: c.int) {
	return tb.row - tb.start_view, tb.col
}

Direction :: enum {
	Up,
	Down,
	Left,
	Right,
}

// TODO: handle tabs
// TODO: scroll X axis when tb.col > win_width
textbuffer_draw :: proc(tb: TextBuffer) {
	nc.werase(tb.win)
	defer nc.wrefresh(tb.win)

	// -- draw buffer content
	for row, col in tb.view {
		col := c.int(col)
		nc.wmove(tb.win, col, 0)
		for char in row {
			if char == '\t' {
				nc.waddch(tb.win, ' ')
			} else {
				nc.waddch(tb.win, c.uint(char))
			}
		}
	}

	// -- draw cursor
	nc.wattron(tb.win, nc.A_REVERSE)
	row := tb.rows[tb.row]
	ch: c.uint
	switch {
	case int(tb.col) > len(row) - 1:
		ch = ' '
	case row[tb.col] == '\t':
		ch = ' '
	case:
		ch = c.uint(row[tb.col])
	}

	cur_y, _ := textbuffer_get_cursor_coordinates(tb)
	nc.mvwaddch(tb.win, cur_y, tb.col, ch)
	nc.wattroff(tb.win, nc.A_REVERSE)
}

// creates a view slice with the contents that ought to be displayed for the current cursor position.
// only takes .Up and .Down as directions. Other directions will be ignored
@(private = "file")
textbuffer_view_move :: proc(tb: ^TextBuffer, dir: Direction) {
	h, w := nc.getmaxyx(tb.win)
	#partial switch dir {
	case .Up:
		if tb.start_view > 0 {tb.start_view -= 1} else {return}
	case .Down:
		if int(tb.start_view + h) < len(tb.rows) {tb.start_view += 1} else {return}
	case:
		return
	}

	view_bottom := tb.start_view + h
	rowlen := c.int(len(tb.rows))
	if view_bottom >= rowlen do view_bottom = rowlen
	tb.view = tb.rows[tb.start_view:view_bottom]
}

// updates the text_view to make sure that the cursor is still visible on the window
@(private = "file")
textbuffer_view_update :: proc(tb: ^TextBuffer, cur_y: c.int) {
	win_h, _ := nc.getmaxyx(tb.win)

	// -- make sure the cursor is still inside the view
	rowlen := c.int(len(tb.rows))
	if cur_y >= win_h {
		tb.start_view = tb.row - win_h + SPACE_FROM_EDGES
	} else if cur_y < 0 {
		tb.start_view = tb.row - win_h - SPACE_FROM_EDGES
	} else if len(tb.view) < int(win_h) {
		tb.start_view = tb.row - win_h + SPACE_FROM_EDGES
	}
	if tb.start_view < 0 do tb.start_view = 0


	view_bottom := tb.start_view + win_h
	if view_bottom >= c.int(len(tb.rows)) do view_bottom = c.int(len(tb.rows)) - 1

	tb.view = tb.rows[tb.start_view:view_bottom]
}

// handles how cursor ought to move within the textbuffer and to prevent segfaults
textbuffer_cursor_move :: proc(tb: ^TextBuffer, dir: Direction) {
	h, w := nc.getmaxyx(tb.win)
	cur_y, _ := textbuffer_get_cursor_coordinates(tb^)

	scroll_up_if_on_edge :: #force_inline proc(tb: ^TextBuffer, cur_y: c.int) {
		if cur_y == SPACE_FROM_EDGES do textbuffer_view_move(tb, .Up)
	}

	scroll_down_if_on_edge :: #force_inline proc(tb: ^TextBuffer, cur_y: c.int, maxx: c.int) {
		if cur_y == maxx - 1 - SPACE_FROM_EDGES do textbuffer_view_move(tb, .Down)
	}

	switch dir {
	case .Up:
		if tb.row > 0 do tb.row -= 1
		scroll_up_if_on_edge(tb, cur_y)

	case .Down:
		if int(tb.row) < len(tb.rows) - 1 do tb.row += 1
		scroll_down_if_on_edge(tb, cur_y, h)

	case .Left:
		if tb.col > 0 {
			tb.col -= 1
			// wrap around to previous line
		} else if int(tb.row) > 0 {
			tb.row -= 1
			tb.col = c.int(len(tb.rows[tb.row]))
			scroll_up_if_on_edge(tb, cur_y)
		}

	case .Right:
		if int(tb.col) < len(tb.rows[tb.row]) {
			tb.col += 1
			// wrap around to next line
		} else if int(tb.row) < len(tb.rows) - 1 {
			tb.row += 1
			tb.col = 0
			scroll_down_if_on_edge(tb, cur_y, h)
		}
	}

	// -- prevent cursor from overflowign row
	rowlen := c.int(len(tb.rows[tb.row]))
	if tb.col > rowlen {
		tb.col = rowlen if rowlen >= 0 else 0
	}
}

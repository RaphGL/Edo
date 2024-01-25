package main

import "core:c"
import "core:os"
import "core:slice"
import "core:strings"
import "core:unicode/utf8"
import nc "ncurses/src"

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
textbuffer_draw :: proc(tb: TextBuffer) {
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

	win_y, _ := textbuffer_get_cursor_coordinates(tb)
	nc.mvwaddch(tb.win, win_y, tb.col, ch)
	nc.wattroff(tb.win, nc.A_REVERSE)

	nc.wrefresh(tb.win)
}

// creates a slice of the size of the textbuffer window
@(private = "file")
textbuffer_view_move :: proc(tb: ^TextBuffer, dir: Direction) {
	h, w := nc.getmaxyx(tb.win)
	#partial switch dir {
	case .Up:
		if tb.start_view > 0 {tb.start_view -= 1} else {return}
	case .Down:
		if int(tb.start_view + h) < len(tb.rows) - 1 {tb.start_view += 1} else {return}
	case:
		panic("Other directions are not supported")
	}

	tb.view = tb.rows[tb.start_view:tb.start_view + h]
}

// handles how cursor ought to move within the textbuffer and to prevent segfaults
textbuffer_cursor_move :: proc(tb: ^TextBuffer, dir: Direction) {
	SPACE_FROM_EDGES :: 6
	h, w := nc.getmaxyx(tb.win)
	win_y, _ := textbuffer_get_cursor_coordinates(tb^)

	switch dir {
	case .Up:
		if tb.row > 0 do tb.row -= 1
		if win_y == SPACE_FROM_EDGES do textbuffer_view_move(tb, .Up)

	case .Down:
		if int(tb.row) < len(tb.rows) - 1 do tb.row += 1
		if win_y == h - SPACE_FROM_EDGES do textbuffer_view_move(tb, .Down)

	case .Left:
		if tb.col > 0 {
			tb.col -= 1
			// wrap around to previous line
		} else if int(tb.row) > 0 {
			tb.row -= 1
			tb.col = c.int(len(tb.rows[tb.row]))
		}

	case .Right:
		if int(tb.col) < len(tb.rows[tb.row]) {
			tb.col += 1
			// wrap around to next line
		} else if int(tb.row) < len(tb.rows) - 1 {
			tb.row += 1
			tb.col = 0
		}
	}

	// -- prevent cursor from overflowign row
	rowlen := c.int(len(tb.rows[tb.row]))
	if tb.col > rowlen {
		tb.col = rowlen if rowlen >= 0 else 0
	}
}

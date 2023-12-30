package main

import "core:c"
import "core:os"
import "core:slice"
import "core:strings"
import nc "ncurses/src"

TextBuffer :: struct {
	filepath:    string,
	win:         ^nc.Window,
	linenum_win: ^nc.Window, // todo: draw line numbers and create window
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
	rows := slice.clone_to_dynamic(file_contents)

	// -- create a text view that fits the window
	view: []string
	if len(rows) > int(h) {
		view = rows[:h]
	} else {
		view = rows[:]
	}
	return TextBuffer{filepath = filepath, rows = rows, win = bufwin, view = view}, true
}

textbuffer_free :: proc(tb: TextBuffer) -> bool {
	nc.werase(tb.win)
	nc.delwin(tb.win)
	return delete(tb.rows) == .None
}

textbuffer_get_cursor_coordinates :: #force_inline proc(tb: TextBuffer) -> (y, x: c.int) {
	return tb.row - tb.start_view, tb.col
}

Direction :: enum {
	Up,
	Down,
	Left,
	Right,
}

textbuffer_draw :: proc(tb: TextBuffer) {
	// -- draw buffer content
	for row, col in tb.view {
		col := c.int(col)
		nc.wmove(tb.win, col, 0)
		nc.wprintw(tb.win, "%s", row)
	}

	// -- draw cursor
	nc.wattron(tb.win, nc.A_REVERSE)
	row := tb.rows[tb.row]
	ch: c.uint
	if int(tb.col) > len(row) - 1 {
		ch = ' '
	} else {
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
		if tb.col > 0 do tb.col -= 1

	case .Right:
		if int(tb.col) < len(tb.rows[tb.row]) do tb.col += 1
	}

	rowlen := c.int(len(tb.rows[tb.row]))
	if tb.col > rowlen {
		tb.col = rowlen
	}
}

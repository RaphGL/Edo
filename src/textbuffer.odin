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
	row:         c.int, // the first row in view
	view:        []string,
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

Direction :: enum {
	Up,
	Down,
	Left,
	Right,
}

// creates a slice of the size of the textbuffer window
textbuffer_view_move :: proc(tb: ^TextBuffer, dir: Direction) {
	h, w := nc.getmaxyx(tb.win)
	#partial switch dir {
	case .Up:
		if tb.row > 0 {tb.row -= 1} else {return}
	case .Down:
		if int(tb.row + h) < len(tb.rows) - 1 {tb.row += 1} else {return}
	case:
		panic("Other directions are not supported")
	}

	tb.view = tb.rows[tb.row:tb.row + h]
}

textbuffer_draw :: proc(tb: TextBuffer) {
	for row, col in tb.view {
		col := c.int(col)
		nc.wmove(tb.win, col, 0)
		nc.wprintw(tb.win, "%s", row)
	}
}

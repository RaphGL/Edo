package main

import "core:c"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import nc "ncurses/src"

TextBuffer :: struct {
	win:  ^nc.Window,
	rows: [dynamic]string,
	row:  c.int, // the first row in view
	view: []string,
}

textbuffer_new :: proc(filepath: string) -> (tb: TextBuffer, success: bool) {
	file_contents: []string
	if filepath != "" {
		data := os.read_entire_file(filepath) or_return
		file_contents = strings.split(string(data), "\n")
	}

	h, w := nc.getmaxyx(nc.stdscr)
	bufwin := nc.newwin(h - 1, w, 0, 0)
	rows := slice.clone_to_dynamic(file_contents)
	view: []string
	if len(rows) > int(h) {
		view = rows[:h]
	} else {
		view = rows[:]
	}
	return TextBuffer{rows = rows, win = bufwin, view = view}, true
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
textbuffer_move :: proc(tb: ^TextBuffer, dir: Direction) {
	h, w := nc.getmaxyx(tb.win)
	#partial switch dir {
	case .Up:
		if tb.row > 0 do tb.row -= 1
	case .Down:
		if int(tb.row + h) < len(tb.rows) - 1 do tb.row += 1
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

main :: proc() {
	nc.initscr()
	nc.noecho()
	nc.curs_set(0)
	nc.cbreak()
	nc.refresh()
	defer nc.endwin()

	tb, success := textbuffer_new(os.args[1] if len(os.args) > 1 else "")
	if !success {
		nc.endwin()
		fmt.eprintln("Failed to load buffer from", os.args[1])
		return
	}
	defer textbuffer_free(tb)


	for {
		nc.werase(tb.win)
		textbuffer_draw(tb)

		nc.wrefresh(tb.win)
		nc.refresh()

		c := nc.wgetch(tb.win)
		switch c {
		case 'j':
			textbuffer_move(&tb, .Down)
		case 'k':
			textbuffer_move(&tb, .Up)
		}

	}
}

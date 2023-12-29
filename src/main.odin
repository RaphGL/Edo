package main

import "core:c"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import nc "ncurses/src"

TextBuffer :: struct {
	win:      ^nc.Window,
	rows:     [dynamic]string,
	col, row: c.int,
}

textbuffer_new :: proc(filepath: string) -> (tb: TextBuffer, success: bool) {
	file_contents: []string
	if filepath != "" {
		data := os.read_entire_file(filepath) or_return
		file_contents = strings.split(string(data), "\n")
	}

	h, w := nc.getmaxyx(nc.stdscr)
	bufwin := nc.newwin(h - 1, w, 0, 0)
	return TextBuffer{rows = slice.clone_to_dynamic(file_contents), win = bufwin}, true
}

textbuffer_free :: proc(tb: TextBuffer) -> bool {
	nc.werase(tb.win)
	nc.delwin(tb.win)
	return delete(tb.rows) == .None
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


		for row in tb.rows {
			nc.wprintw(tb.win, "%s\n", row)
		}

		nc.wrefresh(tb.win)
		nc.refresh()

	nc.wgetch(tb.win)
}

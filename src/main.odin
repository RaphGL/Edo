package main

import "core:c"
import "core:fmt"
import "core:os"
import nc "ncurses/src"

main :: proc() {
	nc.initscr()
	nc.noecho()
	nc.curs_set(0)
	nc.keypad(nc.stdscr, true)
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

	panel := panel_new(&tb)
	defer panel_delete(panel)

	for {
		defer nc.werase(tb.win)
		defer nc.refresh()

		textbuffer_draw(tb)
		panel_draw(panel)

		c := nc.getch()
		switch c {
		case nc.KEY_UP:
			textbuffer_cursor_move(&tb, .Up)
		case nc.KEY_DOWN:
			textbuffer_cursor_move(&tb, .Down)
		case nc.KEY_LEFT:
			textbuffer_cursor_move(&tb, .Left)
		case nc.KEY_RIGHT:
			textbuffer_cursor_move(&tb, .Right)
		case nc.KEY_BACKSPACE:
			textbuffer_remove_char(&tb)
		case nc.KEY_ENTER:
		// textbuffer_insert_row(&tb)
		case:
			textbuffer_append_char(&tb, rune(c))
		}
	}
}

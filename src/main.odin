package main

import "core:c"
import "core:fmt"
import "core:os"
import nc "ncurses/src"

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

	panel := panel_new(&tb)
	defer panel_delete(panel)

	for {
		nc.werase(tb.win)
		textbuffer_draw(tb)
		panel_draw(panel)

		nc.wrefresh(tb.win)
		nc.refresh()

		c := nc.getch()
		switch c {
		case 'j':
			textbuffer_view_move(&tb, .Down)
		case 'k':
			textbuffer_view_move(&tb, .Up)
		}

	}
}

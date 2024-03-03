package main

import nc "ncurses/src"
import "core:c"
import "core:fmt"

Panel :: struct {
	win:      ^nc.Window,
	txbuffer: ^TextBuffer,
}

panel_new :: proc(target_buffer: ^TextBuffer) -> Panel {
	h, w := nc.getmaxyx(nc.stdscr)
	win := nc.newwin(1, w, h - 1, 0)
	return Panel{win = win, txbuffer = target_buffer}
}

panel_delete :: proc(panel: Panel) {
	nc.delwin(panel.win)
}

panel_fit_newsize :: proc(panel: Panel) {
	h, w := nc.getmaxyx(nc.stdscr)
	nc.wresize(panel.win, 1, w)
	nc.mvwin(panel.win, h - 1, 0)
}

panel_draw :: proc(panel: Panel) {
	nc.werase(panel.win)
	defer nc.wrefresh(panel.win)
	nc.wattron(panel.win ,nc.COLOR_PAIR(Pair_Bar))
	defer nc.wattroff(panel.win, nc.COLOR_PAIR(Pair_Bar))

	_, w := nc.getmaxyx(panel.win)
	for i in 0 ..< w {
		nc.waddch(panel.win, ' ')
	}

	filename := panel.txbuffer.filepath if panel.txbuffer.filepath != "" else "DRAFT"
	nc.mvwprintw(panel.win, 0, 5, "%s", filename)
	line_info_bytes: [20]u8
	line_info := fmt.bprintf(line_info_bytes[:], "%d:%d", panel.txbuffer.row + 1, panel.txbuffer.col + 1)
	nc.mvwprintw(panel.win, 0, c.int(w) - 5 - c.int(len(line_info)), "%s", line_info)
	nc.wrefresh(panel.win)
}

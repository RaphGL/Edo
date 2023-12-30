package main

import nc "ncurses/src"

Panel :: struct {
	win:      ^nc.Window,
	txbuffer: ^TextBuffer,
}

panel_new :: proc(target_buffer: ^TextBuffer) -> Panel {
	h, w := nc.getmaxyx(nc.stdscr)
	win := nc.newwin(1, w, h - 1, 0)
	nc.wattron(win, nc.A_REVERSE | nc.A_BOLD)

	return Panel{win = win, txbuffer = target_buffer}
}

panel_delete :: proc(panel: Panel) {
	nc.delwin(panel.win)
}

panel_draw :: proc(panel: Panel) {
	_, w := nc.getmaxyx(panel.win)
	for i in 0 ..< w {
		nc.waddch(panel.win, ' ')
	}

	nc.mvwprintw(panel.win, 0, 5, "%s", panel.txbuffer.filepath)
	nc.wrefresh(panel.win)
}

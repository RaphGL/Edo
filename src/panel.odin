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
	line_info_bytes: [20]u8
	line_info := fmt.bprintf(line_info_bytes[:], "%d:%d", panel.txbuffer.row, panel.txbuffer.col)
	nc.mvwprintw(panel.win, 0, c.int(w) - 5 - c.int(len(line_info)), "%s", line_info)
	nc.wrefresh(panel.win)
}

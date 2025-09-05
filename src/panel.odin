package main

import "core:c"
import "core:fmt"
import t "termcl"

Panel :: struct {
	win:      t.Window,
	txbuffer: ^TextBuffer,
}

panel_new :: proc(target_buffer: ^TextBuffer) -> Panel {
	termsize := t.get_term_size()
	win := t.init_window(termsize.h - 1, 0, 1, termsize.w)
	return Panel{win = win, txbuffer = target_buffer}
}

panel_delete :: proc(panel: ^Panel) {
	t.destroy_window(&panel.win)
}

panel_fit_newsize :: proc(panel: ^Panel) {
	termsize := t.get_term_size()
	t.resize_window(&panel.win, 1, termsize.w)
	panel.win.y_offset = termsize.h - 1
	panel.win.x_offset = 0
}

panel_draw :: proc(panel: ^Panel) {
	t.clear(&panel.win, .Everything)
	defer t.blit(&panel.win)
	t.set_color_style(&panel.win, .Black, .White)
	defer t.reset_styles(&panel.win)

	filename := panel.txbuffer.filepath if panel.txbuffer.filepath != "" else "DRAFT"
	t.move_cursor(&panel.win, 0, 5)
	t.write(&panel.win, filename)
	line_info_bytes: [20]u8
	line_info := fmt.bprintf(
		line_info_bytes[:],
		"%d:%d",
		panel.txbuffer.row + 1,
		panel.txbuffer.col + 1,
	)

	winsize := t.get_window_size(&panel.win)
	t.move_cursor(&panel.win, 0, winsize.w - 5 - len(line_info))
	t.write(&panel.win, line_info)
}


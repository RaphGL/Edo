package main

import "core:c"
import "core:fmt"
import "core:os"
import nc "ncurses/src"

Pair_Foreground :: 1
Pair_Linenum :: 2
Pair_Active_Linenum :: 3
Pair_Bar :: 4

init_color_support :: proc() {
	if !nc.has_colors() do return
	nc.start_color()
	nc.use_default_colors()

	// ncurses uses 0-1000 instead of 0-255 for RGB
	to_ncurses_fmt :: #force_inline proc(color: c.short) -> c.short {
		return color * (1000 / 256)
	}

	Color_Foreground :: 1
	Color_Background :: 2
	Color_CurrentLine :: 3
	Color_Comment :: 4
	Color_Cyan :: 5
	Color_Green :: 6
	Color_Orange :: 7
	Color_Pink :: 8
	Color_Purple :: 9
	Color_Red :: 10
	Color_Yellow :: 11
	nc.init_color(
		Color_Foreground,
		to_ncurses_fmt(0xF8),
		to_ncurses_fmt(0xF8),
		to_ncurses_fmt(0xF2),
	)
	nc.init_color(
		Color_CurrentLine,
		to_ncurses_fmt(0x44),
		to_ncurses_fmt(0x47),
		to_ncurses_fmt(0x5A),
	)
	nc.init_color(
		Color_Background,
		to_ncurses_fmt(0x28),
		to_ncurses_fmt(0x2A),
		to_ncurses_fmt(0x36),
	)
	nc.init_color(Color_Comment, to_ncurses_fmt(0x62), to_ncurses_fmt(0x72), to_ncurses_fmt(0xA4))
	nc.init_color(Color_Cyan, to_ncurses_fmt(0x8B), to_ncurses_fmt(0xE9), to_ncurses_fmt(0xFD))
	nc.init_color(Color_Green, to_ncurses_fmt(0x50), to_ncurses_fmt(0xFA), to_ncurses_fmt(0x7B))
	nc.init_color(Color_Orange, to_ncurses_fmt(0xFF), to_ncurses_fmt(0xB8), to_ncurses_fmt(0x6C))
	nc.init_color(Color_Pink, to_ncurses_fmt(0xFF), to_ncurses_fmt(0x79), to_ncurses_fmt(0xC6))
	nc.init_color(Color_Purple, to_ncurses_fmt(0xBD), to_ncurses_fmt(0x93), to_ncurses_fmt(0xF9))
	nc.init_color(Color_Red, to_ncurses_fmt(0xFF), to_ncurses_fmt(0x55), to_ncurses_fmt(0x55))
	nc.init_color(Color_Yellow, to_ncurses_fmt(0xF1), to_ncurses_fmt(0xFA), to_ncurses_fmt(0x8C))

	nc.init_pair(Pair_Foreground, Color_Foreground, -1)
	nc.init_pair(Pair_Linenum, Color_Comment, -1)
	nc.init_pair(Pair_Active_Linenum, Color_Foreground, Color_CurrentLine)
	nc.init_pair(Pair_Bar, Color_Foreground, Color_Background)
}

main :: proc() {
	nc.initscr()
	init_color_support()
	nc.noecho()
	nc.curs_set(0)
	nc.keypad(nc.stdscr, true)
	nc.raw()
	nc.refresh()
	defer nc.endwin()

	tb, success := textbuffer_new(os.args[1] if len(os.args) > 1 else "")
	if !success {
		nc.endwin()
		fmt.eprintln("Failed to load buffer from", os.args[1])
		return
	}
	defer textbuffer_free(&tb)

	panel := panel_new(&tb)
	defer panel_delete(panel)

	for {
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

		case nc.KEY_ENTER, '\n':
			textbuffer_breakline(&tb)

		case nc.KEY_RESIZE:
			textbuffer_fit_newsize(&tb)
			panel_fit_newsize(panel)

		case:
			key_str := string(nc.keyname(c))
			// handle control combos
			if key_str[0] == '^' {switch key_str[1] {
				case 'S':
					textbuffer_save_to_file(tb)
				case 'Q':
					return
				}
			} else {
				// insert regular characters
				textbuffer_append_char(&tb, rune(c))
			}
		}
	}
}

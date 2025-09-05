package main

import "core:c"
import "core:fmt"
import "core:os"
import t "termcl"

main :: proc() {
	s := t.init_screen()
	defer t.destroy_screen(&s)
	t.set_term_mode(&s, .Raw)
	t.hide_cursor(true)

	tb, success := textbuffer_new(os.args[1] if len(os.args) > 1 else "")
	if !success {
		fmt.eprintln("Failed to load buffer from", os.args[1])
		return
	}
	defer textbuffer_free(&tb)

	panel := panel_new(&tb)
	defer panel_delete(&panel)

	for {
		defer t.clear(&s, .Everything)

		textbuffer_draw(&tb)
		panel_draw(&panel)

		input := t.read(&s) or_continue
		kb := t.parse_keyboard_input(input) or_continue

		#partial switch kb.key {
		case .Arrow_Up:
			textbuffer_cursor_move(&tb, .Up)

		case .Arrow_Down:
			textbuffer_cursor_move(&tb, .Down)

		case .Arrow_Left:
			textbuffer_cursor_move(&tb, .Left)

		case .Arrow_Right:
			textbuffer_cursor_move(&tb, .Right)

		case .Backspace:
			textbuffer_remove_char(&tb)

		case .Enter:
			textbuffer_breakline(&tb)

		// TODO
		// case nc.KEY_RESIZE:
		// 	textbuffer_fit_newsize(&tb)
		// 	panel_fit_newsize(panel)

		case:
			if kb.mod == .Ctrl {
				#partial switch kb.key {
				case .S:
					textbuffer_save_to_file(tb)
				case .Q:
					return
				}
			} else if len(input) == 1 {
				// insert regular characters
				textbuffer_append_char(&tb, cast(rune)input[0])
			}
		}
	}
}


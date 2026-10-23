extends "res://ui/upgrade_hover_menu.gdc"

# The original wrapper splits only at spaces. Japanese needs character breaks.
func wrap_to_width(text: String, font: Font, font_size: int, max_width: float) -> String:
	var lines: PackedStringArray = []
	var no_line_start: String = "、。，．！？：；)]）］｝〉》」』】ーぁぃぅぇぉっゃゅょァィゥェォッャュョ"
	for paragraph: String in text.split("\n"):
		var current_line: String = ""
		for character: String in paragraph:
			var candidate: String = current_line + character
			if not current_line.is_empty() and max_width > 0.0 and font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > max_width and not no_line_start.contains(character):
				lines.append(current_line)
				current_line = character
			else:
				current_line = candidate
		lines.append(current_line)
	return "\n".join(lines)

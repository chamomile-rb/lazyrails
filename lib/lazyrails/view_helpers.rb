# frozen_string_literal: true

module LazyRails
  module ViewHelpers
    def self.truncate(str, max)
      return str if max < 1 || str.length <= max

      "#{str[0..(max - 2)]}…"
    end

    def self.selected_style
      Chamomile::Style.new.bold.reverse
    end

    def self.classify_name(name)
      name.to_s.split("_").map(&:capitalize).join
    end

    # Composites a popup box on top of a base layout, centered.
    # Both are full terminal renders as strings. The popup lines replace
    # the corresponding base lines at the centered position.
    def self.overlay(base, popup_box, screen_width, screen_height)
      base_lines = base.split("\n", -1)
      box_lines = popup_box.split("\n", -1)

      # Remove trailing empty lines from box
      box_lines.pop while box_lines.last&.then { |l| Chamomile::ANSI.strip(l).strip.empty? }

      box_h = box_lines.size
      box_w = box_lines.map { |l| Chamomile::ANSI.printable_width(l) }.max || 0

      # Center position
      start_row = [(screen_height - box_h) / 2, 0].max
      start_col = [(screen_width - box_w) / 2, 0].max

      # Pad base to fill screen height
      base_lines << "" while base_lines.size < screen_height

      box_lines.each_with_index do |box_line, i|
        row = start_row + i
        break if row >= base_lines.size

        if start_col == 0
          base_lines[row] = box_line
        else
          left_pad = " " * start_col
          base_lines[row] = "#{left_pad}#{box_line}"
        end
      end

      base_lines[0, screen_height].join("\n")
    end

    # Injects a styled title into the first line of a bordered box.
    # Used by Renderer and MenuOverlay to add titles to Chamomile borders.
    def self.inject_title(top_line, styled_title, title_visible_len)
      stripped = Chamomile::ANSI.strip(top_line)
      return top_line if stripped.length <= title_visible_len + 2

      ansi_prefix = top_line[/\A((?:\e\[[0-9;]*m)*)/] || ""
      reset = "\e[0m"
      corner = stripped[0]
      rest = stripped[(1 + title_visible_len)..]

      "#{ansi_prefix}#{corner}#{reset}#{styled_title}#{ansi_prefix}#{rest}#{reset}"
    end
  end
end

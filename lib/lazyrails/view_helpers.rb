# frozen_string_literal: true

module LazyRails
  module ViewHelpers
    def self.truncate(str, max)
      return str if max < 1 || str.length <= max

      "#{str[0..(max - 2)]}…"
    end

    def self.classify_name(name)
      name.to_s.split("_").map(&:capitalize).join
    end

    # Injects a styled title into the first line of a bordered box.
    # Used by Renderer and MenuOverlay to add titles to Flourish borders.
    def self.inject_title(top_line, styled_title, title_visible_len)
      stripped = Flourish::ANSI.strip(top_line)
      return top_line if stripped.length <= title_visible_len + 2

      ansi_prefix = top_line[/\A((?:\e\[[0-9;]*m)*)/] || ""
      reset = "\e[0m"
      corner = stripped[0]
      rest = stripped[(1 + title_visible_len)..]

      "#{ansi_prefix}#{corner}#{reset}#{styled_title}#{ansi_prefix}#{rest}#{reset}"
    end
  end
end

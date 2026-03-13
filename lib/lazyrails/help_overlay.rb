# frozen_string_literal: true

module LazyRails
  class HelpOverlay
    SECTIONS = [
      { section: "Navigation", bindings: [
        ["Tab/Shift+Tab", "Cycle panels"],
        ["1-9", "Jump to panel"],
        ["j/k", "Scroll up/down"],
        ["Enter", "Select / expand"],
        ["q", "Quit"],
        ["?", "Toggle help"],
        ["R", "Refresh panel"],
        ["/", "Filter (where supported)"],
        ["L", "Toggle command log"],
        ["z", "Undo last action"],
        ["G", "Open generator menu"],
        ["x", "Panel action menu"]
      ] },
      { section: "Server", bindings: [
        ["s", "Start server"],
        ["S", "Stop server"],
        ["r", "Restart server"],
        ["p", "Change port"]
      ] },
      { section: "Database", bindings: [
        ["m", "Run db:migrate"],
        ["M", "Run db:rollback"],
        ["c", "Create migration"],
        ["d", "Migrate down version"],
        ["u", "Migrate up version"],
        ["t", "Browse table data"],
        ["s", "Seed database"],
        ["C", "Create database"],
        ["D", "Drop database"],
        ["r", "Reset database"]
      ] },
      { section: "Tests", bindings: [
        ["Enter", "Run selected test"],
        ["a", "Run all tests"],
        ["f", "Run failed only"]
      ] },
      { section: "Table Browser", bindings: [
        ["w", "Set WHERE clause"],
        ["o", "Set ORDER BY"],
        ["n/p", "Next/prev page"],
        ["c", "Clear filters"]
      ] },
      { section: "Jobs", bindings: [
        ["r", "Retry failed job"],
        ["d", "Discard failed job"],
        ["A", "Retry all failed"],
        ["e", "Dispatch scheduled now"],
        ["D", "Discard scheduled job"],
        ["f", "Cycle filter"],
        ["R", "Refresh"]
      ] },
      { section: "Gems", bindings: [
        ["Enter", "Show gem info"],
        ["u", "Update gem"],
        ["U", "Update all"],
        ["o", "Open homepage"]
      ] }
    ].freeze

    def initialize
      @visible = false
      @scroll = 0
      @lines = build_lines
    end

    def visible? = @visible

    def show
      @visible = true
      @scroll = 0
    end

    def hide
      @visible = false
    end

    def handle_key(key)
      case key
      when "j", :down
        @scroll = [@scroll + 1, max_scroll].min
        nil
      when "k", :up
        @scroll = [@scroll - 1, 0].max
        nil
      when "?", :escape
        hide
        nil
      when "q"
        :quit
      end
    end

    def render(width:, height:)
      box_width = [width - 8, 64].min
      box_width = [box_width, 44].max
      visible_height = height - 8

      visible = @lines[@scroll, visible_height] || []
      content = visible.map { |l| ViewHelpers.truncate(l, box_width - 4) }.join("\n")

      scroll_hint = @scroll < max_scroll ? " | j/k scroll" : ""
      footer = "? or Esc close#{scroll_hint}"

      box = Chamomile::Style.new
                           .width(box_width)
                           .border(Chamomile::Border::ROUNDED)
                           .border_foreground("#b48ead")
                           .padding(0, 1)
                           .render("#{content}\n\n#{footer}")

      box_lines = box.lines
      if box_lines.any?
        title_text = " Keybindings "
        title_styled = Chamomile::Style.new.foreground("#b48ead").bold.render(title_text)
        box_lines[0] = ViewHelpers.inject_title(box_lines[0], title_styled, title_text.length)
      end

      box_lines.join
    end

    private

    def build_lines
      lines = []
      SECTIONS.each_with_index do |section, i|
        lines << "" if i > 0
        lines << Chamomile::Style.new.bold.foreground("#b48ead").render(section[:section])
        section[:bindings].each do |key, desc|
          key_styled = Chamomile::Style.new.bold.render(key.ljust(18))
          lines << "  #{key_styled} #{desc}"
        end
      end
      lines
    end

    def max_scroll
      [@lines.size - 10, 0].max
    end
  end
end

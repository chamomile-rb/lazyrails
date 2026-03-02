# frozen_string_literal: true

module LazyRails
  module Views
    module HelpView
      GLOBAL_BINDINGS = [
        { section: "Navigation", bindings: [
          ["Tab/Shift+Tab", "Cycle panels"],
          ["1-7", "Jump to panel"],
          ["j/k", "Scroll up/down"],
          ["Enter", "Select / expand"],
          ["q", "Quit"],
          ["?", "Toggle help"],
          ["R", "Refresh panel"],
          ["/", "Filter (where supported)"],
          ["L", "Toggle command log"],
          ["z", "Undo last action"]
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
          ["u", "Migrate up version"]
        ] },
        { section: "Tests", bindings: [
          ["Enter", "Run selected test"],
          ["a", "Run all tests"],
          ["f", "Run failed only"]
        ] },
        { section: "Gems", bindings: [
          ["Enter", "Show gem info"],
          ["u", "Update gem"],
          ["U", "Update all"],
          ["o", "Open homepage"]
        ] }
      ].freeze

      def self.render(width:, height:)
        lines = []
        lines << "LazyRails Help"
        lines << "=" * [width - 4, 40].min
        lines << ""

        GLOBAL_BINDINGS.each do |section|
          lines << Flourish::Style.new.bold.render(section[:section])
          section[:bindings].each do |key, desc|
            lines << "  #{key.ljust(18)} #{desc}"
          end
          lines << ""
        end

        lines << "Press ? or Esc to close."
        lines.join("\n")
      end
    end
  end
end

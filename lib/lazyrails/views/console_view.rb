# frozen_string_literal: true

module LazyRails
  module Views
    module ConsoleView
      def self.render_item(entry, selected:, width:)
        color = entry.success? ? "#04b575" : "#ff6347"
        text = ViewHelpers.truncate(entry.to_s, width)

        if selected
          ViewHelpers.selected_style.render(text.ljust(width))
        else
          Chamomile::Style.new.foreground(color).render(text)
        end
      end

      def self.render_detail(entry, width:)
        lines = []
        lines << "> #{entry.expression}"
        lines << ""

        lines << if entry.success?
                   "=> #{entry.result}"
                 else
                   Chamomile::Style.new.foreground("#ff6347").render("Error: #{entry.error}")
                 end

        lines << ""
        duration = format("%.1fs", entry.duration_ms / 1000.0)
        lines << "Ran in #{duration} via rails runner"
        lines.join("\n")
      end
    end
  end
end

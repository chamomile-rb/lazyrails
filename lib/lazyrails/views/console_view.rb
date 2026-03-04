# frozen_string_literal: true

module LazyRails
  module Views
    module ConsoleView
      def self.render_item(entry, selected:, width:)
        color = entry.success? ? "#04b575" : "#ff6347"
        text = ViewHelpers.truncate(entry.to_s, width)

        if selected
          Flourish::Style.new.reverse.render(text)
        else
          Flourish::Style.new.foreground(color).render(text)
        end
      end

      def self.render_detail(entry, width:)
        lines = []
        lines << "> #{entry.expression}"
        lines << ""

        if entry.success?
          lines << "=> #{entry.result}"
        else
          lines << Flourish::Style.new.foreground("#ff6347").render("Error: #{entry.error}")
        end

        lines << ""
        duration = "%.1fs" % (entry.duration_ms / 1000.0)
        lines << "Ran in #{duration} via rails runner"
        lines.join("\n")
      end
    end
  end
end

# frozen_string_literal: true

module LazyRails
  module Views
    module CommandLogView
      def self.render(command_log, width:, selected: 0)
        return "No commands executed yet." if command_log.empty?

        command_log.entries.each_with_index.map do |entry, i|
          icon = entry.success? ? "\u2713" : "\u2717"
          color = entry.success? ? "#04b575" : "#ff6347"
          duration = "%.1fs" % (entry.duration_ms / 1000.0)
          cmd_text = ViewHelpers.truncate(entry.command, width - 12)
          text = "#{icon} #{cmd_text.ljust(width - 12)} #{duration}"

          if i == selected
            Flourish::Style.new.reverse.render(text)
          else
            styled_icon = Flourish::Style.new.foreground(color).render(icon)
            "#{styled_icon} #{cmd_text.ljust(width - 12)} #{duration}"
          end
        end.join("\n")
      end

      def self.render_detail(entry, width:)
        lines = []
        lines << "Command: #{entry.command}"
        lines << "Exit:    #{entry.exit_code}"
        lines << "Time:    #{entry.timestamp.strftime("%H:%M:%S")}"
        lines << "Duration: %.1fs" % (entry.duration_ms / 1000.0)
        lines << ""

        if entry.stdout && !entry.stdout.empty?
          lines << "Output:"
          lines << "-" * [width - 4, 40].min
          lines << entry.stdout
        end

        if entry.stderr && !entry.stderr.empty?
          lines << ""
          lines << "Errors:"
          lines << "-" * [width - 4, 40].min
          lines << entry.stderr
        end

        lines.join("\n")
      end

    end
  end
end

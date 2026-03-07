# frozen_string_literal: true

module LazyRails
  module Views
    module LogView
      STATUS_COLORS = {
        "2" => "#04b575",
        "3" => "#e5c07b",
        "4" => "#ff6347",
        "5" => "#ff6347"
      }.freeze

      def self.render_item(entry, selected:, width:)
        status = entry.status.to_s
        color = STATUS_COLORS[status[0]] || "#999999"

        icon = case status.to_i
               when 200..299 then "\u2713"
               when 300..399 then "\u2192"
               when 400..599 then "\u2717"
               else " "
               end

        slow_mark = entry.slow? ? " \u26a0" : ""
        verb = entry.verb.to_s.ljust(6)
        path_text = ViewHelpers.truncate(entry.path.to_s, [width - 20, 1].max)
        text = "#{verb} #{path_text.ljust([width - 20, 1].max)} #{status} #{icon}#{slow_mark}"

        if selected
          ViewHelpers.selected_style.render(text.ljust(width))
        else
          Flourish::Style.new.foreground(color).render(text)
        end
      end

      def self.render_detail(entry, width:)
        lines = []
        lines << "#{entry.verb} #{entry.path}"
        lines << ("=" * [width - 4, 40].min)
        lines << ""
        lines << "Status:   #{entry.status}"
        lines << "Duration: #{entry.duration_ms}ms" if entry.duration_ms
        lines << ""

        if entry.sql_lines.any?
          lines << "SQL Queries:"
          lines << ("\u2500" * 12)
          entry.sql_lines.each do |sql|
            dur = sql[:duration_ms]
            color = dur.to_f > 100 ? "#ff6347" : "#5b9bd5"
            query_text = "  #{sql[:query]} (#{dur}ms)"
            lines << Flourish::Style.new.foreground(color).render(query_text)
          end
          lines << ""
        end

        if entry.raw && !entry.raw.empty?
          lines << "Full Log:"
          lines << ("\u2500" * 9)
          lines << entry.raw
        end

        lines.join("\n")
      end
    end
  end
end

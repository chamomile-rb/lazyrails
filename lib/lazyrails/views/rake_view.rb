# frozen_string_literal: true

module LazyRails
  module Views
    module RakeView
      def self.render_item(task, selected:, width:)
        desc = task.description.to_s
        name_text = task.name
        if desc.empty?
          text = ViewHelpers.truncate(name_text, width)
        else
          desc_width = [width - name_text.length - 3, 0].max
          dimmed_desc = if desc_width.positive?
                          Chamomile::Style.new.foreground("#666666").render(ViewHelpers.truncate(desc,
                                                                                                 desc_width))
                        else
                          ""
                        end
          text = "#{name_text}  #{dimmed_desc}"
        end

        if selected
          plain = if desc.empty?
                    name_text
                  else
                    "#{name_text}  #{ViewHelpers.truncate(desc,
                                                          [width - name_text.length - 3,
                                                           0].max)}"
                  end
          ViewHelpers.selected_style.render(ViewHelpers.truncate(plain, width).ljust(width))
        else
          text
        end
      end

      def self.render_detail(task, width:)
        lines = []
        lines << task.name
        lines << ("\u2500" * [width - 4, 40].min)
        lines << ""
        lines << "Description: #{task.description.to_s.empty? ? '(none)' : task.description}"
        lines << "Source:      #{task.source.to_s.empty? ? '(unknown)' : task.source}"
        lines << ""
        lines << Chamomile::Style.new.foreground("#666666").render("Press Enter to run")
        lines.join("\n")
      end

      def self.render_detail_running(task, width:)
        lines = []
        lines << task.name
        lines << ("\u2500" * [width - 4, 40].min)
        lines << ""
        lines << Chamomile::Style.new.foreground("#e5c07b").bold.render("\u25CF Running...")
        lines << ""
        lines << Chamomile::Style.new.foreground("#666666").render("Output will appear here when complete.")
        lines.join("\n")
      end

      def self.render_detail_with_output(task, result, width:)
        lines = []
        lines << task.name
        lines << ("\u2500" * [width - 4, 40].min)
        lines << ""
        lines << "Description: #{task.description.to_s.empty? ? '(none)' : task.description}"
        lines << "Source:      #{task.source.to_s.empty? ? '(unknown)' : task.source}"
        lines << ""
        lines << ("\u2500" * [width - 4, 40].min)

        lines << if result.success?
                   Chamomile::Style.new.foreground("#98c379").bold.render("\u2713 #{result.command} (#{result.duration_ms}ms)")
                 else
                   Chamomile::Style.new.foreground("#ff6347").bold.render("\u2717 #{result.command} (exit #{result.exit_code})")
                 end
        lines << ""

        output = result.stdout.to_s.strip
        error_output = result.stderr.to_s.strip
        output.each_line { |l| lines << l.rstrip } unless output.empty?
        unless error_output.empty?
          lines << "" unless output.empty?
          error_output.each_line do |l|
            lines << Chamomile::Style.new.foreground("#ff6347").render(l.rstrip)
          end
        end
        lines << "(no output)" if output.empty? && error_output.empty?

        lines.join("\n")
      end
    end
  end
end

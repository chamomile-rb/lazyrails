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
        lines << ("=" * [width - 4, 40].min)
        lines << ""
        lines << "Description: #{task.description.to_s.empty? ? '(none)' : task.description}"
        lines << "Source:      #{task.source.to_s.empty? ? '(unknown)' : task.source}"
        lines << ""
        lines << "Run with: bin/rails #{task.name}"
        lines.join("\n")
      end
    end
  end
end

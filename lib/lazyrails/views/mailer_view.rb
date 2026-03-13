# frozen_string_literal: true

module LazyRails
  module Views
    module MailerView
      def self.render_item(preview, selected:, width:)
        text = ViewHelpers.truncate(preview.to_s, width)

        if selected
          plain = ViewHelpers.truncate(preview.display_name, width)
          ViewHelpers.selected_style.render(plain.ljust(width))
        else
          text
        end
      end

      def self.render_detail(preview, width:)
        lines = []
        lines << preview.display_name
        lines << ("=" * [width - 4, 40].min)
        lines << ""
        lines << "Press Enter to render this preview."
        lines << "Press o to open in browser (server must be running)."
        lines.join("\n")
      end

      def self.render_detail_content(preview, content, width:)
        lines = []
        lines << preview.display_name
        lines << ("=" * [width - 4, 40].min)
        lines << ""

        if content[:error]
          lines << Chamomile::Style.new.foreground("#ff6347").render("Error: #{content[:error]}")
          return lines.join("\n")
        end

        lines << "Subject:  #{content[:subject]}"
        lines << "To:       #{Array(content[:to]).join(', ')}"
        lines << "From:     #{Array(content[:from]).join(', ')}"
        lines << ""
        lines << "\u2500\u2500\u2500\u2500 Body Preview \u2500\u2500\u2500\u2500"
        lines << ""
        lines << content[:body].to_s
        lines.join("\n")
      end
    end
  end
end

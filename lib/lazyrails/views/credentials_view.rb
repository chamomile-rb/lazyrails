# frozen_string_literal: true

module LazyRails
  module Views
    module CredentialsView
      def self.render_item(credential_file, selected:, width:)
        text = ViewHelpers.truncate(credential_file.to_s, width)

        if selected
          Flourish::Style.new.reverse.render(text)
        else
          color = credential_file.exists ? "#04b575" : "#666666"
          Flourish::Style.new.foreground(color).render(text)
        end
      end

      def self.render_detail(credential_file, width:)
        lines = []
        lines << "#{credential_file.environment} credentials"
        lines << "\u2500" * [width - 4, 40].min
        lines << ""
        if credential_file.exists
          lines << "Press Enter to decrypt and view (y/n confirmation)."
        else
          lines << "Key file not found. Cannot decrypt."
        end
        lines.join("\n")
      end

      def self.render_detail_content(credential_file, content, width:)
        lines = []
        lines << "#{credential_file.environment} credentials"
        lines << "\u2500" * [width - 4, 40].min
        lines << ""
        lines << content
        lines << ""
        warn_style = Flourish::Style.new.foreground("#e5c07b")
        lines << warn_style.render("\u26a0  Sensitive \u2014 press Escape to clear")
        lines.join("\n")
      end
    end
  end
end

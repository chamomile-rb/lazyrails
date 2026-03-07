# frozen_string_literal: true

module LazyRails
  module Views
    module CustomCommandsView
      def self.render_item(command, selected:, width:)
        key_hint = command.key.to_s.empty? ? "" : " [#{command.key}]"
        text = ViewHelpers.truncate("#{command.name}#{key_hint}", width)

        if selected
          Flourish::Style.new.reverse.render(text)
        else
          text
        end
      end

      def self.render_detail(command, width:)
        lines = []
        lines << command.name
        lines << ("=" * [width - 4, 40].min)
        lines << ""
        lines << "Command:      #{command.command}"
        lines << "Key binding:  #{command.key.to_s.empty? ? '(none)' : command.key}"
        lines << "Confirmation: #{command.confirmation_tier}"
        lines << ""
        lines << "Press Enter to run this command."
        lines.join("\n")
      end
    end
  end
end

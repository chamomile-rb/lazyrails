# frozen_string_literal: true

module LazyRails
  module Views
    module GemsView
      def self.render_item(gem_entry, selected:, width:)
        text = gem_entry.to_s

        if selected
          Flourish::Style.new.reverse.render(text)
        else
          text
        end
      end

      def self.render_detail(gem_entry, width:)
        lines = []
        lines << "#{gem_entry.name} (#{gem_entry.version})"
        lines << ("=" * [width - 4, 40].min)
        lines << ""
        lines << "Groups: #{gem_entry.groups.join(', ')}"
        lines.join("\n")
      end
    end
  end
end

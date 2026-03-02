# frozen_string_literal: true

module LazyRails
  module Views
    module ModelsView
      def self.render_item(model, selected:, width:)
        text = model.error ? "#{model.name} (error)" : model.to_s

        if selected
          Flourish::Style.new.reverse.render(text)
        else
          text
        end
      end

      def self.render_detail(model, width:)
        return "Error loading #{model.name}: #{model.error}" if model.error

        lines = []
        lines << "#{model.name} (#{model.table_name}) \u2014 #{model.columns.size} columns"
        lines << "=" * [width - 4, 40].min
        lines << ""

        if model.columns.any?
          model.columns.each { |col| lines << "  #{col}" }
          lines << ""
        end

        if model.associations.any?
          lines << "Associations:"
          model.associations.each { |a| lines << "  #{a}" }
          lines << ""
        end

        if model.validations.any?
          lines << "Validations:"
          model.validations.each { |v| lines << "  #{v}" }
          lines << ""
        end

        lines.join("\n")
      end
    end
  end
end

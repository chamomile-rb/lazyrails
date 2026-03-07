# frozen_string_literal: true

module LazyRails
  module Views
    module ModelsView
      ARROW_COLORS = {
        has_many: "#5b9bd5",
        belongs_to: "#e5c07b",
        has_one: "#04b575",
        has_many_through: "#874bfa"
      }.freeze

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
        lines << ("\u2550" * [width - 4, 40].min)
        lines << ""

        if model.associations.any?
          lines << "Relationships"
          lines << ("\u2500" * 13)
          lines << model.name

          assocs = model.associations
          assocs.each_with_index do |a, i|
            last = i == assocs.size - 1
            connector = last ? "\u2514" : "\u251c"
            macro_label = a.macro.to_s.tr("_", " ")
            color_key = if a.macro == :has_many && a.class_name.include?("through")
                          :has_many_through
                        else
                          a.macro
                        end
            color = ARROW_COLORS[color_key] || "#999999"

            arrow_text = "#{macro_label} \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2192 #{a.class_name}"
            styled_arrow = Flourish::Style.new.foreground(color).render(arrow_text)
            lines << " #{connector}\u2500\u2500 #{styled_arrow}"
          end
          lines << ""
        end

        if model.columns.any?
          lines << "Columns"
          lines << ("\u2500" * 7)
          model.columns.each do |col|
            null_flag = col.null ? "" : "  NOT NULL"
            default_flag = col.default.nil? ? "" : "  default: #{col.default.inspect}"
            lines << "  #{col.name.ljust(20)} #{col.type.to_s.ljust(12)}#{null_flag}#{default_flag}"
          end
          lines << ""
        end

        if model.validations.any?
          lines << "Validations"
          lines << ("\u2500" * 11)
          model.validations.each do |v|
            attrs = v.attributes.map { |a| ":#{a}" }.join(", ")
            opts = v.options.empty? ? "" : v.options.map { |k, val| "#{k}: #{val.inspect}" }.join(", ")
            text = "validates #{attrs}, #{v.kind}"
            text += ", #{opts}" unless opts.empty?
            lines << "  #{text}"
          end
          lines << ""
        end

        lines.join("\n")
      end
    end
  end
end

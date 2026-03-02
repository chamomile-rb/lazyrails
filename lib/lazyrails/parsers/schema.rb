# frozen_string_literal: true

module LazyRails
  module Parsers
    module Schema
      def self.parse(content)
        return {} if content.nil? || content.empty?

        tables = {}
        current_table = nil
        columns = []

        content.each_line do |line|
          stripped = line.strip

          if (match = stripped.match(/\Acreate_table\s+["']([^"']+)["']/))
            current_table = match[1]
            columns = []
          elsif current_table && (match = stripped.match(/\At\.(\w+)\s+["'](\w+)["'](.*)$/))
            type = match[1]
            name = match[2]
            rest = match[3]

            null = !rest.include?("null: false")
            default = extract_default(rest)
            limit = rest.match(/limit:\s*(\d+)/)&.[](1)&.to_i

            columns << Column.new(name: name, type: type.to_sym, null: null, default: default, limit: limit)
          elsif current_table && (match = stripped.match(/\At\.(references|belongs_to)\s+:(\w+)(.*)/))
            name = "#{match[2]}_id"
            rest = match[3]
            null = !rest.include?("null: false")
            type = rest.include?("type: :uuid") ? :uuid : :integer
            columns << Column.new(name: name, type: type, null: null, default: nil, limit: nil)
          elsif current_table && stripped.match?(/\At\.timestamps/)
            null = stripped.include?("null: false") || !stripped.include?("null:")
            columns << Column.new(name: "created_at", type: :datetime, null: !null, default: nil, limit: nil)
            columns << Column.new(name: "updated_at", type: :datetime, null: !null, default: nil, limit: nil)
          elsif current_table && stripped.match?(/\Aend\z/)
            tables[current_table] = columns
            current_table = nil
            columns = []
          end
        end

        tables
      end

      def self.extract_default(rest)
        match = rest.match(/default:\s*(.+?)(?:,|\s*$)/)
        return nil unless match

        value = match[1].strip
        case value
        when /\A["'](.*)["']\z/ then Regexp.last_match(1)
        when /\A\d+\z/          then value.to_i
        when /\A\d+\.\d+\z/    then value.to_f
        when "true"             then true
        when "false"            then false
        when "nil"              then nil
        else value
        end
      end

      private_class_method :extract_default
    end
  end
end

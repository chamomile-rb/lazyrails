# frozen_string_literal: true

module LazyRails
  module Parsers
    module RailsStats
      def self.parse(raw_output)
        return { rows: [], summary: {} } if raw_output.nil? || raw_output.empty?

        rows = []
        summary = {}

        raw_output.each_line do |line|
          line = line.strip
          next if line.empty? || line.start_with?("+", "|  Name")

          if (match = line.match(/^\|\s*(.+?)\s*\|\s*([\d,]+)\s*\|\s*([\d,]+)\s*\|\s*([\d,]+)\s*\|\s*([\d,]+)\s*\|/))
            name = match[1].strip
            values = (2..5).map { |i| match[i].delete(",").to_i }

            if name == "Total"
              summary[:total_lines] = values[0]
              summary[:total_loc] = values[1]
              summary[:total_classes] = values[2]
              summary[:total_methods] = values[3]
            else
              rows << StatRow.new(name: name, lines: values[0], loc: values[1], classes: values[2], methods: values[3])
            end
          elsif (match = line.match(/Code LOC:\s*([\d,]+)\s*Test LOC:\s*([\d,]+)/))
            summary[:code_loc] = match[1].delete(",").to_i
            summary[:test_loc] = match[2].delete(",").to_i
          end
        end

        { rows: rows, summary: summary }
      end
    end
  end
end

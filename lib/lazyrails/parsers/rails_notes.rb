# frozen_string_literal: true

module LazyRails
  module Parsers
    module RailsNotes
      def self.parse(raw_output)
        return [] if raw_output.nil? || raw_output.empty?

        notes = []
        current_file = nil

        raw_output.each_line do |line|
          line = line.rstrip

          if line.match?(/\A\S/) && line.end_with?(":")
            current_file = line.chomp(":")
          elsif current_file && (match = line.match(/\*\s*\[\s*(\d+)\]\s*\[([^\]]+)\]\s*(.+)/))
            notes << Note.new(
              file: current_file,
              line: match[1].to_i,
              tag: match[2].strip,
              message: match[3].strip
            )
          end
        end

        notes
      end
    end
  end
end

# frozen_string_literal: true

module LazyRails
  module Parsers
    module RailsAbout
      def self.parse(raw_output)
        return {} if raw_output.nil? || raw_output.empty?

        info = {}
        raw_output.each_line do |line|
          line = line.strip
          next if line.empty? || line.start_with?("About your")

          next unless (match = line.match(/^(.+?)\s{2,}(.+)$/))

          key = match[1].strip
          value = match[2].strip
          info[key] = value
        end
        info
      end
    end
  end
end

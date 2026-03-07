# frozen_string_literal: true

module LazyRails
  module Parsers
    module LogParser
      STARTED_LINE = /Started (GET|POST|PUT|PATCH|DELETE|HEAD) "(.*?)" /
      COMPLETED_LINE = /Completed (\d+) .* in (\d+)ms/
      SQL_LINE = /([\w:]+ Load|CACHE|SQL|[\w:]+ Create|[\w:]+ Update|[\w:]+ Destroy) \((\d+(?:\.\d+)?)ms\)/

      def self.parse(raw_text)
        entries = []
        current_block = nil
        current_sql = []
        current_raw = []

        raw_text.each_line do |line|
          if (m = line.match(STARTED_LINE))
            # Flush previous block
            if current_block
              current_block[:sql_lines] = current_sql
              current_block[:raw] = current_raw.join
              entries << build_entry(current_block)
            end

            current_block = { verb: m[1], path: m[2], status: nil, duration_ms: nil }
            current_sql = []
            current_raw = [line]
            next
          end

          next unless current_block

          current_raw << line

          if (m = line.match(COMPLETED_LINE))
            current_block[:status] = m[1]
            current_block[:duration_ms] = m[2].to_i
          end

          if (m = line.match(SQL_LINE))
            current_sql << { query: m[1], duration_ms: m[2].to_f }
          end
        end

        # Flush last block
        if current_block
          current_block[:sql_lines] = current_sql
          current_block[:raw] = current_raw.join
          entries << build_entry(current_block)
        end

        entries
      end

      def self.build_entry(block)
        LogEntry.new(
          verb: block[:verb],
          path: block[:path],
          status: block[:status],
          duration_ms: block[:duration_ms],
          sql_lines: block[:sql_lines] || [],
          raw: block[:raw] || ""
        )
      end
      private_class_method :build_entry
    end
  end
end

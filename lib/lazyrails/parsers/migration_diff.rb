# frozen_string_literal: true

module LazyRails
  module Parsers
    module MigrationDiff
      ADD_COLUMN    = /add_column\s+:(\w+),\s+:(\w+),\s+:(\w+)(.*)/
      REMOVE_COLUMN = /remove_column\s+:(\w+),\s+:(\w+)/
      CREATE_TABLE  = /create_table\s+:(\w+)/
      DROP_TABLE    = /drop_table\s+:(\w+)/
      ADD_INDEX     = /add_index\s+:(\w+),\s+(.+)/
      RENAME_COLUMN = /rename_column\s+:(\w+),\s+:(\w+),\s+:(\w+)/

      DiffLine = Data.define(:op, :table, :column, :type, :extras) do
        def to_s
          prefix = op == :add ? "+" : "-"
          col_text = column ? column.ljust(20) : ""
          type_text = type || ""
          extras_text = extras && !extras.empty? ? "  #{extras}" : ""
          "  #{prefix} #{col_text} #{type_text}#{extras_text}"
        end
      end

      def self.parse(migration_content)
        diffs = []

        migration_content.each_line do |line|
          stripped = line.strip

          case stripped
          when ADD_COLUMN
            extras = ::Regexp.last_match(4).to_s.strip.delete_prefix(",").strip
            diffs << DiffLine.new(op: :add, table: ::Regexp.last_match(1), column: ::Regexp.last_match(2),
                                  type: ::Regexp.last_match(3), extras: extras.empty? ? nil : extras)
          when REMOVE_COLUMN
            diffs << DiffLine.new(op: :remove, table: ::Regexp.last_match(1), column: ::Regexp.last_match(2),
                                  type: nil, extras: nil)
          when CREATE_TABLE
            diffs << DiffLine.new(op: :add, table: ::Regexp.last_match(1), column: nil, type: "TABLE", extras: nil)
          when DROP_TABLE
            diffs << DiffLine.new(op: :remove, table: ::Regexp.last_match(1), column: nil, type: "TABLE", extras: nil)
          when ADD_INDEX
            diffs << DiffLine.new(op: :add, table: ::Regexp.last_match(1), column: nil, type: "INDEX",
                                  extras: ::Regexp.last_match(2).strip)
          when RENAME_COLUMN
            diffs << DiffLine.new(op: :remove, table: ::Regexp.last_match(1), column: ::Regexp.last_match(2),
                                  type: nil, extras: nil)
            diffs << DiffLine.new(op: :add, table: ::Regexp.last_match(1), column: ::Regexp.last_match(3), type: nil,
                                  extras: "(renamed from #{::Regexp.last_match(2)})")
          end

          # Handle t.string :name style inside create_table blocks
          next unless stripped.match?(/\At\.(\w+)\s+:(\w+)/)

          m = stripped.match(/\At\.(\w+)\s+:(\w+)(.*)/)
          next unless m

          type = m[1]
          next if %w[timestamps index references].include?(type)

          col = m[2]
          extras = m[3].to_s.strip.delete_prefix(",").strip
          diffs << DiffLine.new(op: :add, table: nil, column: col, type: type, extras: extras.empty? ? nil : extras)
        end

        diffs
      end
    end
  end
end

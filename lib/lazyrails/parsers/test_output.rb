# frozen_string_literal: true

module LazyRails
  module Parsers
    module TestOutput
      def self.parse(raw_output, file: nil)
        if raw_output.nil? || raw_output.empty?
          return TestResult.new(file: file, passed: 0, failed: 0, errors: 0,
                                output: "")
        end

        passed = 0
        failed = 0
        errors = 0

        # Minitest: 5 runs, 10 assertions, 0 failures, 0 errors, 2 skips
        if (match = raw_output.match(/(\d+)\s+runs?,\s+\d+\s+assertions?,\s+(\d+)\s+failures?,\s+(\d+)\s+errors?(?:,\s+(\d+)\s+skips?)?/))
          total = match[1].to_i
          failed = match[2].to_i
          errors = match[3].to_i
          skips = match[4].to_i
          passed = total - failed - errors - skips
        # RSpec: 5 examples, 0 failures, 1 pending
        elsif (match = raw_output.match(/(\d+)\s+examples?,\s+(\d+)\s+failures?(?:,\s+(\d+)\s+pending)?/))
          total = match[1].to_i
          failed = match[2].to_i
          pending = match[3].to_i
          passed = total - failed - pending
        end

        TestResult.new(
          file: file,
          passed: [passed, 0].max,
          failed: failed,
          errors: errors,
          output: raw_output
        )
      end
    end
  end
end

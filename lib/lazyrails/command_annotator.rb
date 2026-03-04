# frozen_string_literal: true

module LazyRails
  module CommandAnnotator
    def self.annotate(command_string, stdout, stderr, exit_code)
      annotation = extract_annotation(command_string, stdout, stderr, exit_code)
      undo = extract_undo(command_string, stdout, exit_code)
      [annotation, undo]
    end

    def self.extract_annotation(cmd, stdout, stderr, exit_code)
      if cmd.include?("db:migrate") && !cmd.include?("db:migrate:") && exit_code == 0
        applied = stdout.scan(/==\s+(\w+):\s+migrating/).flatten
        applied.empty? ? "No pending migrations" : "Applied: #{applied.join(", ")}"
      elsif cmd.include?("db:rollback") && exit_code == 0
        rolled = stdout.scan(/==\s+(\w+):\s+reverting/).flatten
        rolled.empty? ? "Rolled back" : "Reverted: #{rolled.join(", ")}"
      elsif cmd.match?(/generate model\s/)
        files = stdout.scan(/create\s+(\S+)/).flatten
        files.empty? ? nil : "Created: #{files.join(", ")}"
      elsif cmd.match?(/generate migration\s/)
        files = stdout.scan(/create\s+(\S+)/).flatten
        files.empty? ? nil : "Created: #{files.join(", ")}"
      elsif cmd.match?(/destroy model\s/)
        files = stdout.scan(/remove\s+(\S+)/).flatten
        files.empty? ? nil : "Removed: #{files.join(", ")}"
      elsif exit_code != 0
        first_error = stderr.to_s.lines.first&.strip
        first_error && !first_error.empty? ? "Failed: #{first_error}" : nil
      end
    end
    private_class_method :extract_annotation

    def self.extract_undo(cmd, stdout, exit_code)
      return nil if exit_code != 0

      if cmd.include?("db:migrate") && !cmd.include?("db:migrate:")
        count = stdout.scan(/==\s+\w+:\s+migrating/).length
        count > 0 ? ["bin/rails", "db:rollback", "STEP=#{count}"] : nil
      elsif cmd.match?(/generate model (\w+)/)
        model = cmd.match(/generate model (\w+)/)[1]
        ["bin/rails", "destroy", "model", model]
      elsif cmd.include?("db:rollback")
        ["bin/rails", "db:migrate"]
      end
    end
    private_class_method :extract_undo
  end
end

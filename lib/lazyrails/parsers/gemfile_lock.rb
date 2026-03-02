# frozen_string_literal: true

module LazyRails
  module Parsers
    module GemfileLock
      def self.parse(lockfile_path)
        return [] unless File.exist?(lockfile_path)

        require "bundler"

        content = File.read(lockfile_path)
        parser = Bundler::LockfileParser.new(content)
        groups = detect_groups(File.join(File.dirname(lockfile_path), "Gemfile"))

        parser.specs.map do |spec|
          GemEntry.new(
            name: spec.name,
            version: spec.version.to_s,
            groups: groups[spec.name] || [:default]
          )
        end.sort_by(&:name)
      end

      def self.detect_groups(gemfile_path)
        groups = {}
        return groups unless File.exist?(gemfile_path)

        group_stack = [[:default]]

        File.read(gemfile_path).each_line do |line|
          stripped = line.strip
          next if stripped.start_with?("#") || stripped.empty?

          if (match = stripped.match(/\Agroup\s+(.+?)\s+do/))
            new_groups = match[1].scan(/:(\w+)/).flatten.map(&:to_sym)
            group_stack.push(new_groups) unless new_groups.empty?
          elsif stripped.match?(/\Aend\z/) && group_stack.size > 1
            group_stack.pop
          elsif (match = stripped.match(/\Agem\s+['"]([^'"]+)['"](.*)/))
            gem_name = match[1]
            rest = match[2]

            # Check for inline group: option
            gem_groups = if (inline = rest.match(/group:\s*\[?([^\]]+)\]?/))
              inline[1].scan(/:(\w+)/).flatten.map(&:to_sym)
            elsif (inline = rest.match(/group:\s*:(\w+)/))
              [inline[1].to_sym]
            else
              group_stack.last.dup
            end

            groups[gem_name] = gem_groups
          end
        end

        groups
      end

      private_class_method :detect_groups
    end
  end
end

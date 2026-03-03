# frozen_string_literal: true

module LazyRails
  module Parsers
    module ModelFile
      ASSOCIATION_RE = /\b(has_many|has_one|belongs_to|has_and_belongs_to_many)\s+:(\w+)(?:.*class_name:\s*['"](\w+)['"])?/
      VALIDATES_RE = /\bvalidates\s+(.+)/
      VALIDATES_METHOD_RE = /\bvalidates_(\w+)_of\s+(.+)/

      def self.parse(content)
        return { associations: [], validations: [] } if content.nil? || content.empty?

        associations = []
        validations = []

        content.each_line do |line|
          # Strip inline comments (but not inside strings — best effort)
          line = line.sub(/\s+#(?![{]).*$/, "").strip
          next if line.start_with?("#") || line.empty?

          if (match = line.match(ASSOCIATION_RE))
            macro = match[1].to_sym
            name = match[2].to_sym
            class_name = match[3] || ViewHelpers.classify_name(name.to_s)
            associations << Association.new(macro: macro, name: name, class_name: class_name)
          end

          if (match = line.match(VALIDATES_RE))
            parse_validates(match[1], validations)
          elsif (match = line.match(VALIDATES_METHOD_RE))
            parse_validates_method(match[1], match[2], validations)
          end
        end

        { associations: associations, validations: validations }
      end

      # Parse `validates :email, :name, presence: true, uniqueness: true`
      def self.parse_validates(rest, validations)
        # Extract leading attribute symbols (before any hash-key option)
        attrs = []
        rest.scan(/:(\w+)/) do |match|
          word = match[0]
          break if validation_kind?(word)
          attrs << word.to_sym
        end
        return if attrs.empty?

        kinds = []
        kinds << :presence      if rest.match?(/\bpresence\b/)
        kinds << :uniqueness    if rest.match?(/\buniqueness\b/)
        kinds << :length        if rest.match?(/\blength\b/)
        kinds << :format        if rest.match?(/\bformat\b/)
        kinds << :numericality  if rest.match?(/\bnumericality\b/)
        kinds << :inclusion     if rest.match?(/\binclusion\b/)
        kinds << :exclusion     if rest.match?(/\bexclusion\b/)
        kinds << :confirmation  if rest.match?(/\bconfirmation\b/)
        kinds << :acceptance    if rest.match?(/\bacceptance\b/)
        kinds << :comparison    if rest.match?(/\bcomparison\b/)

        kinds.each do |kind|
          validations << Validation.new(kind: kind, attributes: attrs, options: {})
        end
      end

      # Parse `validates_presence_of :email, :name`
      def self.parse_validates_method(kind_name, rest, validations)
        attrs = rest.scan(/:(\w+)/).flatten.map(&:to_sym)
        return if attrs.empty?

        validations << Validation.new(kind: kind_name.to_sym, attributes: attrs, options: {})
      end

      def self.validation_kind?(word)
        %w[presence uniqueness length format numericality inclusion exclusion
           confirmation acceptance comparison allow_nil allow_blank
           on if unless message strict].include?(word)
      end

      private_class_method :parse_validates, :parse_validates_method, :validation_kind?
    end
  end
end

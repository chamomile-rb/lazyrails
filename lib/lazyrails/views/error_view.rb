# frozen_string_literal: true

module LazyRails
  module Views
    module ErrorView
      SUGGESTIONS = {
        "Bundler::GemNotFound" => "Run `bundle install`",
        "SyntaxError" => "Check the file and line number shown above",
        "ActiveRecord::AdapterNotSpecified" => "Check config/database.yml",
        "Gemfile requires Ruby" => "Ruby version mismatch — check .ruby-version",
        "LoadError: cannot load such file" => "A required file is missing",
        "ActiveRecord::NoDatabaseError" => "Run `db:create` to create the database"
      }.freeze

      def self.render(error_text, width:)
        lines = []
        lines << Flourish::Style.new.foreground("#ff6347").bold.render("Error")
        lines << "=" * [width - 4, 40].min
        lines << ""
        lines << error_text
        lines << ""

        suggestion = detect_suggestion(error_text)
        if suggestion
          lines << Flourish::Style.new.foreground("#e5c07b").render("Suggestion: #{suggestion}")
        end

        lines.join("\n")
      end

      def self.detect_suggestion(error_text)
        SUGGESTIONS.each do |pattern, suggestion|
          return suggestion if error_text.include?(pattern)
        end
        nil
      end

      private_class_method :detect_suggestion
    end
  end
end

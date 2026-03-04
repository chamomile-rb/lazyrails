# frozen_string_literal: true

module LazyRails
  class Confirmation
    # Ordered most-specific to least-specific to avoid substring false positives
    RED_PATTERNS = %w[db:drop db:reset db:seed:replant].freeze
    YELLOW_PATTERNS = %w[db:rollback db:migrate:down destroy].freeze

    attr_reader :tier, :command, :input_text, :required_text

    def initialize(command:, tier: nil, required_text: nil)
      @command = command
      @tier = tier || detect_tier(command)
      @input_text = +""
      @required_text = required_text
      @confirmed = false
      @cancelled = false
    end

    def red?    = @tier == :red
    def yellow? = @tier == :yellow
    def green?  = @tier == :green

    def prompt_text
      case @tier
      when :red
        "Type '#{@required_text}' to confirm: #{@input_text}"
      when :yellow
        "Are you sure? (y/n): #{@input_text}"
      end
    end

    def handle_key(key)
      case key
      when :escape
        @cancelled = true
      when :enter
        check_confirmation
      when :backspace
        @input_text.chop!
      else
        @input_text << key.to_s if key.is_a?(String) && key.length == 1
      end
    end

    def confirmed?
      @confirmed
    end

    def cancelled?
      @cancelled
    end

    def needs_confirmation?
      red? || yellow?
    end

    def self.detect_tier(cmd)
      cmd = cmd.join(" ") if cmd.is_a?(Array)
      return :red if RED_PATTERNS.any? { |p| cmd.include?(p) }
      return :yellow if YELLOW_PATTERNS.any? { |p| cmd.include?(p) }
      return :yellow if cmd.match?(/\Abundle update\s*\z/)

      :green
    end

    private

    def check_confirmation
      case @tier
      when :red
        @confirmed = @input_text.strip == @required_text
      when :yellow
        @confirmed = @input_text.strip.downcase == "y"
      else
        @confirmed = true
      end
    end

    def detect_tier(cmd) = self.class.detect_tier(cmd)
  end
end

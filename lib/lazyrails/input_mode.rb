# frozen_string_literal: true

module LazyRails
  class InputMode
    attr_reader :purpose

    def initialize
      @active = false
      @purpose = nil
      @input = nil
    end

    def active? = @active

    def start_filter
      activate(:filter, prompt: "/", placeholder: "filter...")
    end

    def start_input(purpose, prompt:, placeholder:)
      activate(purpose, prompt: prompt, placeholder: placeholder)
    end

    def deactivate
      @active = false
      @purpose = nil
    end

    def handle_key(msg)
      case msg.key
      when :escape then :cancelled
      when :enter  then { action: :submitted, value: @input.value, purpose: @purpose }
      else
        @input.update(msg)
        @purpose == :filter ? { action: :changed, value: @input.value } : nil
      end
    end

    def view
      @input&.view || ""
    end

    private

    def activate(purpose, prompt:, placeholder:)
      @active = true
      @purpose = purpose
      @input = Petals::TextInput.new(prompt: prompt, placeholder: placeholder)
      @input.focus
    end
  end
end

# frozen_string_literal: true

module LazyRails
  class InputMode
    attr_reader :purpose

    def initialize
      @active = false
      @purpose = nil
      @input = nil
      @label = ""
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
        @input.handle(msg)
        @purpose == :filter ? { action: :changed, value: @input.value } : nil
      end
    end

    def view
      @input&.view || ""
    end

    def styled_label
      @label
    end

    private

    def activate(purpose, prompt:, placeholder:)
      @active = true
      @purpose = purpose
      @label = prompt
      @input = Petals::TextInput.new(prompt: "", placeholder: placeholder)
      @input.focus
    end
  end
end

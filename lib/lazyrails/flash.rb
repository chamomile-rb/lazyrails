# frozen_string_literal: true

module LazyRails
  class Flash
    attr_reader :message

    def initialize
      @message = nil
      @expiry = nil
    end

    def set(message, duration: 3)
      @message = message
      @expiry = Time.now + duration
    end

    def tick
      return unless @message && @expiry && Time.now > @expiry

      @message = nil
      @expiry = nil
    end

    def active? = !@message.nil?
  end
end

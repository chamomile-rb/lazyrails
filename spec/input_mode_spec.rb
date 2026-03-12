# frozen_string_literal: true

RSpec.describe LazyRails::InputMode do
  subject(:input_mode) { described_class.new }

  # Minimal stub for Chamomile::KeyEvent
  KeyEvent = Struct.new(:key)

  describe "#start_filter" do
    it "activates with filter purpose" do
      input_mode.start_filter
      expect(input_mode).to be_active
      expect(input_mode.purpose).to eq(:filter)
    end
  end

  describe "#start_input" do
    it "activates with given purpose" do
      input_mode.start_input(:change_port, prompt: "Port: ", placeholder: "3000")
      expect(input_mode).to be_active
      expect(input_mode.purpose).to eq(:change_port)
    end
  end

  describe "#deactivate" do
    it "clears active state and purpose" do
      input_mode.start_filter
      input_mode.deactivate
      expect(input_mode).not_to be_active
      expect(input_mode.purpose).to be_nil
    end
  end

  describe "#handle_key" do
    it "returns :cancelled on escape" do
      input_mode.start_filter
      result = input_mode.handle_key(KeyEvent.new(:escape))
      expect(result).to eq(:cancelled)
    end

    it "returns submitted hash on enter" do
      input_mode.start_filter
      result = input_mode.handle_key(KeyEvent.new(:enter))
      expect(result).to be_a(Hash)
      expect(result[:action]).to eq(:submitted)
      expect(result[:purpose]).to eq(:filter)
    end

    it "returns changed hash for filter purpose on other keys" do
      input_mode.start_filter
      result = input_mode.handle_key(KeyEvent.new("a"))
      expect(result).to be_a(Hash)
      expect(result[:action]).to eq(:changed)
    end

    it "returns nil for non-filter purpose on other keys" do
      input_mode.start_input(:change_port, prompt: "Port: ", placeholder: "3000")
      result = input_mode.handle_key(KeyEvent.new("3"))
      expect(result).to be_nil
    end
  end

  describe "#view" do
    it "returns empty string when not active" do
      expect(input_mode.view).to eq("")
    end

    it "returns input view when active" do
      input_mode.start_filter
      expect(input_mode.view).to be_a(String)
    end
  end
end

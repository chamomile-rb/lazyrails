# frozen_string_literal: true

RSpec.describe LazyRails::Flash do
  subject(:flash) { described_class.new }

  describe "#set" do
    it "stores a message" do
      flash.set("Hello")
      expect(flash.message).to eq("Hello")
    end

    it "becomes active" do
      flash.set("Hello")
      expect(flash).to be_active
    end
  end

  describe "#tick" do
    it "clears an expired message" do
      flash.set("Hello", duration: 0)
      sleep 0.01
      flash.tick
      expect(flash.message).to be_nil
      expect(flash).not_to be_active
    end

    it "keeps a non-expired message" do
      flash.set("Hello", duration: 10)
      flash.tick
      expect(flash.message).to eq("Hello")
      expect(flash).to be_active
    end

    it "does nothing when no message is set" do
      flash.tick
      expect(flash.message).to be_nil
    end
  end

  describe "#active?" do
    it "returns false initially" do
      expect(flash).not_to be_active
    end

    it "returns true after set" do
      flash.set("Hello")
      expect(flash).to be_active
    end
  end
end

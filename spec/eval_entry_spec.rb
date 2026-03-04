# frozen_string_literal: true

RSpec.describe LazyRails::EvalEntry do
  describe "#to_s" do
    it "shows the expression with a prompt" do
      entry = described_class.new(expression: "User.count", result: "42", error: nil, duration_ms: 100)
      expect(entry.to_s).to eq("> User.count")
    end
  end

  describe "#success?" do
    it "returns true when no error" do
      entry = described_class.new(expression: "1+1", result: "2", error: nil, duration_ms: 50)
      expect(entry).to be_success
    end

    it "returns false when error present" do
      entry = described_class.new(expression: "bad", result: nil, error: "NameError", duration_ms: 50)
      expect(entry).not_to be_success
    end
  end
end

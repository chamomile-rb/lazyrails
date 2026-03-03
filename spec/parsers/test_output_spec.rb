# frozen_string_literal: true

RSpec.describe LazyRails::Parsers::TestOutput do
  describe ".parse" do
    it "returns zeros for nil input" do
      result = described_class.parse(nil, file: "test.rb")
      expect(result.passed).to eq(0)
      expect(result.failed).to eq(0)
      expect(result.errors).to eq(0)
      expect(result.file).to eq("test.rb")
    end

    it "returns zeros for empty string" do
      result = described_class.parse("", file: "test.rb")
      expect(result.passed).to eq(0)
      expect(result.failed).to eq(0)
    end

    it "parses minitest output" do
      output = "5 runs, 10 assertions, 1 failures, 1 errors, 0 skips"
      result = described_class.parse(output)

      expect(result.passed).to eq(3)
      expect(result.failed).to eq(1)
      expect(result.errors).to eq(1)
    end

    it "parses minitest output with skips" do
      output = "10 runs, 20 assertions, 0 failures, 0 errors, 2 skips"
      result = described_class.parse(output)

      expect(result.passed).to eq(8)
      expect(result.failed).to eq(0)
      expect(result.errors).to eq(0)
    end

    it "parses rspec output" do
      output = "15 examples, 2 failures"
      result = described_class.parse(output)

      expect(result.passed).to eq(13)
      expect(result.failed).to eq(2)
    end

    it "parses rspec output with pending" do
      output = "20 examples, 1 failure, 3 pending"
      result = described_class.parse(output)

      expect(result.passed).to eq(16)
      expect(result.failed).to eq(1)
    end

    it "preserves raw output" do
      output = "5 runs, 10 assertions, 0 failures, 0 errors, 0 skips"
      result = described_class.parse(output, file: "test/models/user_test.rb")

      expect(result.output).to eq(output)
      expect(result.file).to eq("test/models/user_test.rb")
    end

    it "handles singular forms" do
      output = "1 run, 1 assertion, 0 failures, 0 errors, 0 skips"
      result = described_class.parse(output)
      expect(result.passed).to eq(1)
    end

    it "handles rspec singular" do
      output = "1 example, 0 failures"
      result = described_class.parse(output)
      expect(result.passed).to eq(1)
    end
  end
end

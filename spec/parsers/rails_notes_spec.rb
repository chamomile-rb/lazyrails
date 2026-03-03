# frozen_string_literal: true

RSpec.describe LazyRails::Parsers::RailsNotes do
  describe ".parse" do
    it "returns empty array for nil input" do
      expect(described_class.parse(nil)).to eq([])
    end

    it "returns empty array for empty string" do
      expect(described_class.parse("")).to eq([])
    end

    it "parses notes grouped by file" do
      output = <<~OUTPUT
        app/models/user.rb:
          * [14] [TODO] Add email validation
          * [32] [FIXME] Handle edge case

        app/controllers/users_controller.rb:
          * [ 7] [OPTIMIZE] Cache this query
      OUTPUT

      notes = described_class.parse(output)

      expect(notes.size).to eq(3)

      expect(notes[0].file).to eq("app/models/user.rb")
      expect(notes[0].line).to eq(14)
      expect(notes[0].tag).to eq("TODO")
      expect(notes[0].message).to eq("Add email validation")

      expect(notes[1].file).to eq("app/models/user.rb")
      expect(notes[1].line).to eq(32)
      expect(notes[1].tag).to eq("FIXME")

      expect(notes[2].file).to eq("app/controllers/users_controller.rb")
      expect(notes[2].line).to eq(7)
      expect(notes[2].tag).to eq("OPTIMIZE")
    end

    it "handles output with no notes" do
      output = "app/models/user.rb:\n"
      expect(described_class.parse(output)).to eq([])
    end
  end
end

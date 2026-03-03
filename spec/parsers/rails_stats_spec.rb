# frozen_string_literal: true

RSpec.describe LazyRails::Parsers::RailsStats do
  describe ".parse" do
    it "returns empty structure for nil input" do
      result = described_class.parse(nil)
      expect(result).to eq({ rows: [], summary: {} })
    end

    it "returns empty structure for empty string" do
      result = described_class.parse("")
      expect(result).to eq({ rows: [], summary: {} })
    end

    it "parses standard rails stats output" do
      output = <<~OUTPUT
        +----------------------+--------+--------+---------+---------+-----+-------+
        |  Name                | Lines  |   LOC  | Classes | Methods | M/C | LOC/M |
        +----------------------+--------+--------+---------+---------+-----+-------+
        | Controllers          |    500 |    400 |      10 |      50 |   5 |     6 |
        | Models               |    300 |    250 |       8 |      30 |   3 |     6 |
        | Total                |    800 |    650 |      18 |      80 |   4 |     6 |
        +----------------------+--------+--------+---------+---------+-----+-------+
          Code LOC: 400     Test LOC: 250
      OUTPUT

      result = described_class.parse(output)

      expect(result[:rows].size).to eq(2)
      expect(result[:rows][0].name).to eq("Controllers")
      expect(result[:rows][0].lines).to eq(500)
      expect(result[:rows][0].loc).to eq(400)
      expect(result[:rows][0].classes).to eq(10)
      expect(result[:rows][0].methods).to eq(50)

      expect(result[:rows][1].name).to eq("Models")

      expect(result[:summary][:total_lines]).to eq(800)
      expect(result[:summary][:total_loc]).to eq(650)
      expect(result[:summary][:total_classes]).to eq(18)
      expect(result[:summary][:total_methods]).to eq(80)
      expect(result[:summary][:code_loc]).to eq(400)
      expect(result[:summary][:test_loc]).to eq(250)
    end

    it "handles commas in numbers" do
      output = <<~OUTPUT
        +----------------------+--------+--------+---------+---------+-----+-------+
        |  Name                | Lines  |   LOC  | Classes | Methods | M/C | LOC/M |
        +----------------------+--------+--------+---------+---------+-----+-------+
        | Controllers          |  1,500 |  1,200 |      10 |      50 |   5 |     6 |
        | Total                |  1,500 |  1,200 |      10 |      50 |   5 |     6 |
        +----------------------+--------+--------+---------+---------+-----+-------+
      OUTPUT

      result = described_class.parse(output)
      expect(result[:rows][0].lines).to eq(1500)
      expect(result[:rows][0].loc).to eq(1200)
    end
  end
end

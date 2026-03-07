# frozen_string_literal: true

RSpec.describe LazyRails::TableBrowser do
  subject(:browser) { described_class.new }

  let(:table_names) { %w[comments posts users] }

  describe "#show / #hide" do
    it "starts hidden" do
      expect(browser).not_to be_visible
    end

    it "becomes visible after show" do
      browser.show(table_names)
      expect(browser).to be_visible
      expect(browser.screen).to eq(:table_list)
      expect(browser.cursor).to eq(0)
    end

    it "sorts table names" do
      browser.show(%w[zebra alpha middle])
      # cursor at 0 should be "alpha" after sort
      result = browser.handle_key(:enter)
      expect(result).to eq({ action: :load_table, table: "alpha" })
    end

    it "hides after hide" do
      browser.show(table_names)
      browser.hide
      expect(browser).not_to be_visible
    end

    it "resets state on show" do
      browser.show(table_names)
      browser.handle_key("j")
      browser.show(table_names)
      expect(browser.cursor).to eq(0)
      expect(browser.screen).to eq(:table_list)
    end

    it "exposes selected_table" do
      browser.show(table_names)
      browser.handle_key(:enter)
      expect(browser.selected_table).to eq("comments")
    end
  end

  describe "#handle_key on table list" do
    before { browser.show(table_names) }

    it "moves cursor down with j" do
      browser.handle_key("j")
      expect(browser.cursor).to eq(1)
    end

    it "moves cursor down with :down" do
      browser.handle_key(:down)
      expect(browser.cursor).to eq(1)
    end

    it "moves cursor up with k" do
      browser.handle_key("j")
      browser.handle_key("j")
      browser.handle_key("k")
      expect(browser.cursor).to eq(1)
    end

    it "moves cursor up with :up" do
      browser.handle_key("j")
      browser.handle_key(:up)
      expect(browser.cursor).to eq(0)
    end

    it "clamps cursor at bottom" do
      10.times { browser.handle_key("j") }
      expect(browser.cursor).to eq(2)
    end

    it "clamps cursor at top" do
      browser.handle_key("k")
      expect(browser.cursor).to eq(0)
    end

    it "returns load_table signal on enter" do
      browser.handle_key("j") # cursor on "posts"
      result = browser.handle_key(:enter)
      expect(result).to eq({ action: :load_table, table: "posts" })
      expect(browser.screen).to eq(:row_data)
    end

    it "returns nil on enter with empty table list" do
      browser.show([])
      result = browser.handle_key(:enter)
      expect(result).to be_nil
    end

    it "returns :close on escape" do
      result = browser.handle_key(:escape)
      expect(result).to eq(:close)
    end

    it "returns :close on t" do
      result = browser.handle_key("t")
      expect(result).to eq(:close)
    end

    it "returns :quit on q" do
      result = browser.handle_key("q")
      expect(result).to eq(:quit)
    end

    it "returns nil for navigation keys" do
      expect(browser.handle_key("j")).to be_nil
      expect(browser.handle_key("k")).to be_nil
    end
  end

  describe "#handle_key on row data" do
    before do
      browser.show(table_names)
      browser.handle_key(:enter) # select first table
      browser.load_rows(%w[id name], [%w[1 Alice], %w[2 Bob]])
    end

    it "returns nil for j/k navigation" do
      expect(browser.handle_key("j")).to be_nil
      expect(browser.handle_key("k")).to be_nil
    end

    it "returns to table list on escape" do
      result = browser.handle_key(:escape)
      expect(result).to be_nil
      expect(browser.screen).to eq(:table_list)
    end

    it "returns :quit on q" do
      result = browser.handle_key("q")
      expect(result).to eq(:quit)
    end

    it "handles j/k when table_widget is nil (loading in progress)" do
      browser.show(table_names)
      browser.handle_key(:enter)
      browser.loading!
      # Should not raise — safe navigation handles nil widget
      expect(browser.handle_key("j")).to be_nil
      expect(browser.handle_key("k")).to be_nil
    end
  end

  describe "#loading! / #fail_loading" do
    before { browser.show(table_names) }

    it "sets loading state" do
      browser.handle_key(:enter)
      browser.loading!
      output = browser.render(width: 80, height: 24)
      expect(output).to include("Loading...")
    end

    it "sets error state" do
      browser.handle_key(:enter)
      browser.fail_loading("connection refused")
      output = browser.render(width: 80, height: 24)
      expect(output).to include("connection refused")
    end
  end

  describe "#load_rows" do
    before do
      browser.show(table_names)
      browser.handle_key(:enter)
    end

    it "builds table widget from columns and rows" do
      browser.load_rows(%w[id name], [%w[1 Alice], %w[2 Bob]])
      output = browser.render(width: 80, height: 24)
      expect(output).to include("comments") # table name in header
      expect(output).to include("id")
      expect(output).to include("name")
    end

    it "handles NULL values" do
      browser.load_rows(%w[id email], [["1", nil]])
      output = browser.render(width: 80, height: 24)
      expect(output).to include("NULL")
    end

    it "handles empty rows" do
      browser.load_rows(%w[id name], [])
      output = browser.render(width: 80, height: 24)
      expect(output).to include("id")
      expect(output).to include("name")
    end

    it "handles empty columns and rows" do
      browser.load_rows([], [])
      output = browser.render(width: 80, height: 24)
      expect(output).to include("comments")
    end

    it "called after user escaped back to table_list does not crash" do
      browser.handle_key(:escape) # back to table_list
      expect(browser.screen).to eq(:table_list)
      # Stale result arrives — should not raise
      browser.load_rows(["id"], [["1"]])
    end
  end

  describe "#render" do
    it "renders table list" do
      browser.show(table_names)
      output = browser.render(width: 80, height: 24)
      expect(output).to include("Select a Table")
      expect(output).to include("comments")
      expect(output).to include("posts")
      expect(output).to include("users")
    end

    it "renders empty table list" do
      browser.show([])
      output = browser.render(width: 80, height: 24)
      expect(output).to include("No tables found")
    end

    it "renders table count" do
      browser.show(table_names)
      output = browser.render(width: 80, height: 24)
      expect(output).to include("(3)")
    end

    it "paginates a long table list" do
      many_tables = (1..50).map { |i| "table_#{i.to_s.rjust(2, '0')}" }
      browser.show(many_tables)
      # With height 10, visible_height = max(10-4,1) = 6
      output = browser.render(width: 80, height: 10)
      # Should not render all 50 tables
      visible_lines = output.split("\n").select { |l| l.include?("table_") }
      expect(visible_lines.size).to be <= 6
    end

    it "renders with very small dimensions" do
      browser.show(table_names)
      # Should not crash with tiny width/height
      output = browser.render(width: 5, height: 5)
      expect(output).to be_a(String)
    end
  end

  describe "column width with many columns" do
    before do
      browser.show(table_names)
      browser.handle_key(:enter)
    end

    it "shrinks column widths when there are many columns" do
      cols = (1..20).map { |i| "col#{i}" }
      rows = [cols.map(&:upcase)]
      browser.load_rows(cols, rows)
      # Should not raise
      output = browser.render(width: 80, height: 24)
      expect(output).to include("col1")
    end
  end
end

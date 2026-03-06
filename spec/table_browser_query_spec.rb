# frozen_string_literal: true

RSpec.describe LazyRails::TableBrowser, "query features" do
  subject(:browser) { described_class.new }

  let(:table_names) { %w[comments posts users] }

  before do
    browser.show(table_names)
    browser.handle_key(:enter) # select "comments", enter row_data screen
  end

  describe "#set_where" do
    it "stores a WHERE clause" do
      browser.set_where("id > 5")
      expect(browser.current_query_params["where"]).to eq("id > 5")
    end

    it "resets page to 0" do
      browser.instance_variable_set(:@page, 3)
      browser.set_where("id > 5")
      expect(browser.current_query_params["offset"]).to be_nil
    end

    it "clears WHERE with empty string" do
      browser.set_where("id > 5")
      browser.set_where("")
      expect(browser.current_query_params).not_to have_key("where")
    end

    it "clears WHERE with nil" do
      browser.set_where("id > 5")
      browser.set_where(nil)
      expect(browser.current_query_params).not_to have_key("where")
    end
  end

  describe "#set_order" do
    it "stores an ORDER column" do
      browser.set_order("created_at")
      expect(browser.current_query_params["order"]).to eq("created_at ASC")
    end

    it "toggles direction when same column is set again" do
      browser.set_order("id")
      browser.set_order("id")
      expect(browser.current_query_params["order"]).to eq("id DESC")
    end

    it "resets direction when switching to a different column" do
      browser.set_order("id")
      browser.set_order("id")
      browser.set_order("name")
      expect(browser.current_query_params["order"]).to eq("name ASC")
    end

    it "parses explicit ASC direction from input" do
      browser.set_order("created_at ASC")
      expect(browser.current_query_params["order"]).to eq("created_at ASC")
    end

    it "parses explicit DESC direction from input" do
      browser.set_order("created_at DESC")
      expect(browser.current_query_params["order"]).to eq("created_at DESC")
    end

    it "is case-insensitive for direction" do
      browser.set_order("created_at desc")
      expect(browser.current_query_params["order"]).to eq("created_at DESC")
    end

    it "clears order with empty string" do
      browser.set_order("id")
      browser.set_order("")
      expect(browser.current_query_params).not_to have_key("order")
    end

    it "resets page to 0" do
      browser.instance_variable_set(:@page, 3)
      browser.set_order("id")
      expect(browser.current_query_params["offset"]).to be_nil
    end
  end

  describe "#current_query_params" do
    it "always includes limit" do
      expect(browser.current_query_params["limit"]).to eq(LazyRails::TableBrowser::PAGE_SIZE)
    end

    it "includes offset when page > 0" do
      browser.instance_variable_set(:@page, 2)
      expect(browser.current_query_params["offset"]).to eq(2 * LazyRails::TableBrowser::PAGE_SIZE)
    end

    it "omits offset when page is 0" do
      expect(browser.current_query_params).not_to have_key("offset")
    end

    it "includes where and order when set" do
      browser.set_where("status = 'active'")
      browser.set_order("name")
      params = browser.current_query_params
      expect(params["where"]).to eq("status = 'active'")
      expect(params["order"]).to eq("name ASC")
    end
  end

  describe "#load_rows with total" do
    it "stores total_rows" do
      browser.load_rows(["id"], [["1"]], total: 250)
      output = browser.render(width: 80, height: 24)
      expect(output).to include("250 rows")
    end

    it "defaults total to 0" do
      browser.load_rows(["id"], [["1"]])
      output = browser.render(width: 80, height: 24)
      expect(output).to include("0 rows")
    end
  end

  describe "pagination keys in row data" do
    before do
      browser.load_rows(["id"], [["1"]], total: 250)
    end

    it "returns load signal for next page" do
      result = browser.handle_key("n")
      expect(result).to eq({ action: :load_table, table: "comments" })
    end

    it "returns nil when already on last page" do
      # total=250, page_size=100 → 3 pages (0,1,2)
      browser.handle_key("n") # page 1
      browser.handle_key("n") # page 2
      result = browser.handle_key("n") # should be nil, already on last page
      expect(result).to be_nil
    end

    it "returns nil for prev page when on first page" do
      result = browser.handle_key("p")
      expect(result).to be_nil
    end

    it "returns load signal for prev page when not on first" do
      browser.handle_key("n")
      result = browser.handle_key("p")
      expect(result).to eq({ action: :load_table, table: "comments" })
    end

    it "returns input_where signal for w" do
      result = browser.handle_key("w")
      expect(result).to eq({ action: :input_where })
    end

    it "returns input_order signal for o" do
      result = browser.handle_key("o")
      expect(result).to eq({ action: :input_order })
    end

    it "returns load signal for c (clear filters)" do
      browser.set_where("id > 5")
      result = browser.handle_key("c")
      expect(result).to eq({ action: :load_table, table: "comments" })
      expect(browser.current_query_params).not_to have_key("where")
    end
  end

  describe "render_row_data status line" do
    before do
      browser.load_rows(["id", "name"], [["1", "Alice"]], total: 50)
    end

    it "shows page info" do
      output = browser.render(width: 80, height: 24)
      expect(output).to include("Page 1/1")
      expect(output).to include("50 rows")
    end

    it "shows WHERE clause when set" do
      browser.set_where("id > 5")
      browser.load_rows(["id", "name"], [["6", "Bob"]], total: 10)
      output = browser.render(width: 80, height: 24)
      expect(output).to include("WHERE id > 5")
    end

    it "shows ORDER BY when set" do
      browser.set_order("name")
      browser.load_rows(["id", "name"], [["1", "Alice"]], total: 50)
      output = browser.render(width: 80, height: 24)
      expect(output).to include("ORDER BY name ASC")
    end

    it "shows footer with new keybindings" do
      output = browser.render(width: 80, height: 24)
      expect(output).to include("w where")
      expect(output).to include("o order")
      expect(output).to include("n/p page")
      expect(output).to include("c clear")
    end
  end

  describe "query state reset" do
    it "resets query state when selecting a new table" do
      browser.set_where("id > 5")
      browser.set_order("name")
      browser.handle_key(:escape) # back to table list
      browser.handle_key("j")    # move to "posts"
      browser.handle_key(:enter) # select posts
      expect(browser.current_query_params).not_to have_key("where")
      expect(browser.current_query_params).not_to have_key("order")
    end

    it "resets query state when show is called" do
      browser.set_where("id > 5")
      browser.show(%w[a b c])
      # After re-show, we need to enter a table to check query params
      browser.handle_key(:enter)
      expect(browser.current_query_params).not_to have_key("where")
    end
  end
end

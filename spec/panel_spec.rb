# frozen_string_literal: true

RSpec.describe LazyRails::Panel do
  def make_panel(items: [], **opts)
    panel = described_class.new(type: :routes, title: "Routes", **opts)
    panel.finish_loading(items: items)
    panel
  end

  describe "#selected_item" do
    it "returns nil when no items" do
      panel = make_panel
      expect(panel.selected_item).to be_nil
    end

    it "returns the item at cursor position" do
      panel = make_panel(items: %w[a b c])
      expect(panel.selected_item).to eq("a")
    end

    it "respects cursor position" do
      panel = make_panel(items: %w[a b c])
      panel.move_cursor(1, 10)
      expect(panel.selected_item).to eq("b")
    end
  end

  describe "#move_cursor" do
    it "moves cursor down" do
      panel = make_panel(items: %w[a b c])
      panel.move_cursor(1, 10)
      expect(panel.cursor).to eq(1)
    end

    it "moves cursor up" do
      panel = make_panel(items: %w[a b c])
      panel.move_cursor(2, 10)
      panel.move_cursor(-1, 10)
      expect(panel.cursor).to eq(1)
    end

    it "clamps at bottom" do
      panel = make_panel(items: %w[a b c])
      panel.move_cursor(10, 10)
      expect(panel.cursor).to eq(2)
    end

    it "clamps at top" do
      panel = make_panel(items: %w[a b c])
      panel.move_cursor(-5, 10)
      expect(panel.cursor).to eq(0)
    end

    it "does nothing with empty items" do
      panel = make_panel
      panel.move_cursor(1, 10)
      expect(panel.cursor).to eq(0)
    end

    it "adjusts scroll_offset when cursor goes below visible area" do
      panel = make_panel(items: %w[a b c d e])
      panel.move_cursor(3, 2) # visible_height=2, cursor=3
      expect(panel.scroll_offset).to eq(2) # cursor(3) - visible_height(2) + 1
    end

    it "adjusts scroll_offset when cursor goes above visible area" do
      panel = make_panel(items: %w[a b c d e])
      panel.move_cursor(4, 2) # go to bottom
      panel.move_cursor(-4, 2) # go back to top
      expect(panel.scroll_offset).to eq(0)
    end
  end

  describe "#filtered_items" do
    it "returns all items when filter is empty" do
      panel = make_panel(items: %w[apple banana cherry])
      expect(panel.filtered_items).to eq(%w[apple banana cherry])
    end

    it "filters items case-insensitively" do
      panel = make_panel(items: %w[Apple banana CHERRY])
      panel.filter_text = "a"
      expect(panel.filtered_items).to eq(%w[Apple banana])
    end

    it "returns empty array when nothing matches" do
      panel = make_panel(items: %w[apple banana])
      panel.filter_text = "xyz"
      expect(panel.filtered_items).to eq([])
    end
  end

  describe "#reset_cursor" do
    it "resets cursor and scroll_offset to zero" do
      panel = make_panel(items: %w[a b c d e])
      panel.move_cursor(4, 2)
      panel.reset_cursor
      expect(panel.cursor).to eq(0)
      expect(panel.scroll_offset).to eq(0)
    end
  end

  describe "#item_count" do
    it "returns count of filtered items" do
      panel = make_panel(items: %w[apple banana cherry])
      panel.filter_text = "a"
      expect(panel.item_count).to eq(2)
    end
  end

  describe "#start_loading" do
    it "sets loading to true and clears error" do
      panel = make_panel(items: %w[a b])
      panel.start_loading
      expect(panel.loading).to be true
      expect(panel.error).to be_nil
    end
  end

  describe "#finish_loading" do
    it "sets items and clears loading" do
      panel = described_class.new(type: :routes, title: "Routes")
      panel.finish_loading(items: %w[x y z])
      expect(panel.items).to eq(%w[x y z])
      expect(panel.loading).to be false
    end

    it "accepts optional error" do
      panel = described_class.new(type: :routes, title: "Routes")
      panel.finish_loading(items: [], error: "oops")
      expect(panel.error).to eq("oops")
      expect(panel.loading).to be false
    end
  end

  describe "#fail_loading" do
    it "sets error and clears loading" do
      panel = described_class.new(type: :routes, title: "Routes")
      panel.fail_loading("something went wrong")
      expect(panel.error).to eq("something went wrong")
      expect(panel.loading).to be false
    end
  end

  describe "#update_title" do
    it "changes the title" do
      panel = make_panel
      panel.update_title("New Title")
      expect(panel.title).to eq("New Title")
    end
  end

  describe "#replace_item_at" do
    it "replaces item at given index" do
      panel = make_panel(items: %w[a b c])
      panel.replace_item_at(1, "x")
      expect(panel.items).to eq(%w[a x c])
    end
  end
end

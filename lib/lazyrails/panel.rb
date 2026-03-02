# frozen_string_literal: true

module LazyRails
  class Panel
    TYPES = %i[status server routes database models tests gems].freeze

    attr_accessor :type, :title, :items, :cursor, :scroll_offset, :loading, :error, :filter_text

    def initialize(type:, title:)
      @type = type
      @title = title
      @items = []
      @cursor = 0
      @scroll_offset = 0
      @loading = true
      @error = nil
      @filter_text = ""
    end

    def selected_item
      filtered_items[@cursor]
    end

    def filtered_items
      return items if filter_text.empty?

      items.select { |item| item.to_s.downcase.include?(filter_text.downcase) }
    end

    def move_cursor(delta, visible_height)
      list = filtered_items
      return if list.empty?

      @cursor = (@cursor + delta).clamp(0, list.size - 1)

      if @cursor < @scroll_offset
        @scroll_offset = @cursor
      elsif @cursor >= @scroll_offset + visible_height
        @scroll_offset = @cursor - visible_height + 1
      end
    end

    def reset_cursor
      @cursor = 0
      @scroll_offset = 0
    end

    def item_count
      filtered_items.size
    end
  end
end

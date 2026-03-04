# frozen_string_literal: true

module LazyRails
  class Panel
    TYPES = %i[status server routes database models tests gems rake console credentials logs mailers custom].freeze

    attr_reader :type, :title, :items, :cursor, :scroll_offset, :loading, :error
    attr_reader :filter_text

    def filter_text=(value)
      @filter_text = value
      invalidate_filter_cache
    end

    def initialize(type:, title:)
      @type = type
      @title = title
      @items = []
      @cursor = 0
      @scroll_offset = 0
      @loading = true
      @error = nil
      @filter_text = ""
      @filtered_cache = nil
      @filtered_cache_key = nil
    end

    def start_loading
      @loading = true
      @error = nil
    end

    def finish_loading(items:, error: nil)
      @items = items
      @loading = false
      @error = error
      invalidate_filter_cache
    end

    def fail_loading(error)
      @loading = false
      @error = error
    end

    def update_title(new_title)
      @title = new_title
    end

    def replace_item_at(index, item)
      @items[index] = item
      invalidate_filter_cache
    end

    def selected_item
      filtered_items[@cursor]
    end

    def filtered_items
      cache_key = [items.object_id, items.size, filter_text]
      return @filtered_cache if @filtered_cache_key == cache_key

      @filtered_cache_key = cache_key
      @filtered_cache = if filter_text.empty?
        items
      else
        downcased = filter_text.downcase
        items.select { |item| item.to_s.downcase.include?(downcased) }
      end
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

    private

    def invalidate_filter_cache
      @filtered_cache = nil
      @filtered_cache_key = nil
    end
  end
end

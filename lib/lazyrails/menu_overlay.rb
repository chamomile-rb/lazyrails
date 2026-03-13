# frozen_string_literal: true

module LazyRails
  class MenuOverlay
    MenuItem = Data.define(:label, :key, :action)

    attr_reader :title, :cursor

    def initialize
      @visible = false
      @title = ""
      @items = []
      @cursor = 0
      @callback = nil
    end

    def visible? = @visible

    def show(title:, items:, &callback)
      @title = title
      @items = items
      @cursor = 0
      @callback = callback
      @visible = true
    end

    def hide
      @visible = false
      @items = []
      @callback = nil
    end

    # Returns :close, an action value, or nil
    def handle_key(key)
      case key
      when :escape
        hide
        nil
      when "j", :down
        @cursor = (@cursor + 1) % @items.size unless @items.empty?
        nil
      when "k", :up
        @cursor = (@cursor - 1) % @items.size unless @items.empty?
        nil
      when :enter
        select_current
      when "q"
        hide
        :quit
      else
        # Check if key matches a menu item's shortcut
        item = @items.find { |i| i.key == key }
        if item
          @cursor = @items.index(item)
          select_current
        end
      end
    end

    def render(width:, height:)
      return "" unless @visible

      menu_width = [width * 0.5, 40].max.to_i
      menu_width = [menu_width, width - 4].min

      lines = @items.each_with_index.map do |item, i|
        selected = i == @cursor
        key_hint = item.key ? " [#{item.key}]" : ""
        text = "  #{item.label}#{key_hint}  "
        if selected
          ViewHelpers.selected_style.render(text.ljust(menu_width - 4))
        else
          text.ljust(menu_width - 4)
        end
      end

      content = lines.join("\n")
      footer = "j/k navigate | Enter select | Esc close"

      box = Chamomile::Style.new
                           .width(menu_width)
                           .border(Chamomile::Border::ROUNDED)
                           .border_foreground("#b48ead")
                           .padding(0, 1)
                           .render("#{content}\n\n#{footer}")

      # Inject title into top border
      box_lines = box.lines
      if box_lines.any?
        title_text = " #{@title} "
        title_styled = Chamomile::Style.new.foreground("#b48ead").bold.render(title_text)
        box_lines[0] = ViewHelpers.inject_title(box_lines[0], title_styled, title_text.length)
      end

      box_lines.join
    end

    private

    def select_current
      return nil if @items.empty?

      item = @items[@cursor]
      hide
      @callback&.call(item.action)
      item.action
    end
  end
end

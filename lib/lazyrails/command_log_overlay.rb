# frozen_string_literal: true

module LazyRails
  class CommandLogOverlay
    attr_reader :cursor, :detail

    def initialize(command_log)
      @command_log = command_log
      @visible = false
      @cursor = 0
      @detail = nil
      @scroll_offset = 0
    end

    def visible? = @visible

    def show
      @visible = true
      @cursor = 0
      @detail = nil
      @scroll_offset = 0
    end

    def hide
      @visible = false
      @detail = nil
    end

    def handle_key(key)
      case key
      when :escape then hide
                        nil
      when "L"     then hide
                        nil
      when "j", :down
        max = [@command_log.size - 1, 0].max
        @cursor = [@cursor + 1, max].min
        @detail = nil
        nil
      when "k", :up
        @cursor = [@cursor - 1, 0].max
        @detail = nil
        nil
      when :enter
        entry = @command_log.entries[@cursor]
        @detail = @detail ? nil : entry
        nil
      when "q" then :quit
      end
    end

    def render(width:, height: nil)
      return "No commands executed yet.\n\nPress L or Esc to close." if @command_log.empty?

      header = Chamomile::Style.new.bold.render("Command Log")
      footer = "j/k navigate | Enter detail | L or Esc close"

      if height
        # Reserve: header(1) + blank(1) + footer blank(1) + footer(1) = 4
        usable = height - 4
        list_height = if @detail
                        # Split: top portion for list, rest for detail
                        [(usable * 0.4).to_i, 3].max
                      else
                        [usable, 3].max
                      end
      else
        list_height = @command_log.size
      end

      clamp_scroll(list_height)

      list = Views::CommandLogView.render_window(
        @command_log, width: width - 4, selected: @cursor,
                      offset: @scroll_offset, limit: list_height
      )

      parts = [header, "", list]

      if @detail
        parts << ""
        parts << Chamomile::Style.new.bold.render("Detail")
        parts << Views::CommandLogView.render_detail(@detail, width: width - 4)
      end

      parts << ""
      parts << footer
      parts.join("\n")
    end

    private

    def clamp_scroll(visible_height)
      @scroll_offset = @cursor if @cursor < @scroll_offset
      @scroll_offset = @cursor - visible_height + 1 if @cursor >= @scroll_offset + visible_height
      max_offset = [@command_log.size - visible_height, 0].max
      @scroll_offset = @scroll_offset.clamp(0, max_offset)
    end
  end
end

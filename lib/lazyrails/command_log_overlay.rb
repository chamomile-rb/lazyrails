# frozen_string_literal: true

module LazyRails
  class CommandLogOverlay
    attr_reader :cursor, :detail

    def initialize(command_log)
      @command_log = command_log
      @visible = false
      @cursor = 0
      @detail = nil
    end

    def visible? = @visible

    def show
      @visible = true
      @cursor = 0
      @detail = nil
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
        @detail = @command_log.entries[@cursor]
        nil
      when "q" then :quit
      end
    end

    def render(width:)
      return "No commands executed yet.\n\nPress L or Esc to close." if @command_log.empty?

      header = Flourish::Style.new.bold.render("Command Log")
      list = Views::CommandLogView.render(@command_log, width: width - 4, selected: @cursor)

      parts = [header, "", list]

      if @detail
        parts << ""
        parts << Flourish::Style.new.bold.render("Detail")
        parts << Views::CommandLogView.render_detail(@detail, width: width - 4)
      end

      parts << ""
      parts << "j/k navigate | Enter detail | L or Esc close | q quit"
      parts.join("\n")
    end
  end
end

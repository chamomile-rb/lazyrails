# frozen_string_literal: true

module LazyRails
  class WelcomeOverlay
    CONTENT = <<~TEXT
      Welcome to LazyRails

      A terminal UI for the Rails command line. Everything is
      organized into panels on the left, with details on the right.


      Getting around

        Tab / Shift+Tab   Cycle between panels
        1-9               Jump to a panel by number
        j / k             Scroll up and down
        Enter             Select the highlighted item
        /                 Filter the current panel
        q                 Quit


      Doing things

        x       Open the action menu for the current panel.
                Each panel has its own actions — this is the
                easiest way to discover what you can do.

        G       Open the generator menu (model, scaffold, etc.)
        R       Refresh the current panel
        z       Undo the last command
        L       View the full command log
        ?       Show all keybindings


      Safety

        LazyRails won't run destructive commands without asking.
        Dangerous operations (like db:drop) require you to type
        a confirmation word. Moderate ones ask y/n. Safe ones
        just run.

        Every command is logged — press L to see what ran.
    TEXT

    def initialize
      @visible = false
      @scroll = 0
      @lines = CONTENT.lines.map(&:chomp)
    end

    def visible? = @visible

    def show
      @visible = true
      @scroll = 0
    end

    def hide
      @visible = false
    end

    def handle_key(key)
      case key
      when "j", :down
        @scroll = [@scroll + 1, max_scroll].min
        nil
      when "k", :up
        @scroll = [@scroll - 1, 0].max
        nil
      when :enter       then :dismiss
      when "!"          then :dismiss_forever
      when "q"          then :quit
      end
    end

    def render(width:, height:)
      box_width = [width - 8, 60].min
      box_width = [box_width, 40].max
      visible_height = height - 8

      visible = @lines[@scroll, visible_height] || []
      content = visible.map { |l| ViewHelpers.truncate(l, box_width - 4) }.join("\n")

      scroll_hint = if @scroll < max_scroll
                      "j/k scroll"
                    else
                      ""
                    end

      footer = "Enter continue | ! don't show again | #{scroll_hint}".strip

      box = Flourish::Style.new
                           .width(box_width)
                           .border(Flourish::Border::ROUNDED)
                           .border_foreground("#b48ead")
                           .padding(0, 1)
                           .render("#{content}\n\n#{footer}")

      box_lines = box.lines
      if box_lines.any?
        title_text = " LazyRails "
        title_styled = Flourish::Style.new.foreground("#b48ead").bold.render(title_text)
        box_lines[0] = ViewHelpers.inject_title(box_lines[0], title_styled, title_text.length)
      end

      box_lines.join
    end

    private

    def max_scroll
      [@lines.size - 10, 0].max
    end
  end
end

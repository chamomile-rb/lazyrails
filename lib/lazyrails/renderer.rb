# frozen_string_literal: true

module LazyRails
  module Renderer
    FOCUSED_COLOR = "#7d56f4"
    UNFOCUSED_COLOR = "#444444"

    private

    def render_left_panels(width)
      panel_heights = distribute_panel_heights(@height - 2)
      sections = []

      @panels.each_with_index do |panel, i|
        focused = i == @focused_panel
        h = panel_heights[i]

        key = panel_cache_key(panel, focused, width, h)
        cached = @panel_render_cache[panel.type]
        if cached && cached[0] == key
          sections << cached[1]
          next
        end

        content = render_panel_content(panel, width: width - 4, height: h - 2, focused: focused)

        border_color = focused ? FOCUSED_COLOR : UNFOCUSED_COLOR
        box = Flourish::Style.new
          .width(width)
          .height(h)
          .border(Flourish::Border::ROUNDED)
          .border_foreground(border_color)
          .render(content)

        box_lines = box.lines
        if box_lines.any?
          title = " #{panel.title} "
          title_styled = Flourish::Style.new.foreground(border_color).bold.render(title)
          box_lines[0] = inject_title(box_lines[0], title_styled, title.length)
        end

        output = box_lines.join
        @panel_render_cache[panel.type] = [key, output]
        sections << output
      end

      Flourish.join_vertical(Flourish::LEFT, *sections)
    end

    def panel_cache_key(panel, focused, width, height)
      base = [panel.items.object_id, panel.items.size, panel.cursor,
              panel.scroll_offset, panel.filter_text, panel.loading,
              panel.error, panel.title, focused, width, height]
      case panel.type
      when :status
        base << @about_data.object_id
      when :server
        base << @server.state << @server.pid
      end
      base
    end

    def render_panel_content(panel, width:, height:, focused:)
      return "Loading..." if panel.loading

      if panel.error && panel.items.empty?
        return Views::ErrorView.render(panel.error.to_s, width: width)
      end

      case panel.type
      when :status
        Views::StatusView.render(panel, @project, @about_data, width: width, focused: focused)
      when :server
        Views::ServerView.render(@server, width: width, focused: focused)
      else
        render_list_panel(panel, width: width, height: height, focused: focused)
      end
    end

    def render_list_panel(panel, width:, height:, focused:)
      items = panel.filtered_items
      if items.empty?
        return case panel.type
               when :console then "No expressions yet.\n\nPress 'e' to evaluate a Ruby expression."
               when :logs    then "No log entries yet.\n\nLogs appear here as requests hit the server.\nPress 's' on the Server panel to start it."
               when :jobs    then @jobs_available == false ? "No background jobs.\n\nSolid Queue not detected." : "No jobs in queue."
               else "No items."
               end
      end

      visible = items[panel.scroll_offset, [height, 1].max] || []
      visible.each_with_index.map do |item, i|
        selected = focused && (i + panel.scroll_offset) == panel.cursor
        case panel.type
        when :routes   then Views::RoutesView.render_item(item, selected: selected, width: width)
        when :database then Views::DatabaseView.render_item(item, selected: selected, width: width)
        when :models   then Views::ModelsView.render_item(item, selected: selected, width: width)
        when :tests    then Views::TestsView.render_item(item, selected: selected, width: width)
        when :gems     then Views::GemsView.render_item(item, selected: selected, width: width)
        when :rake     then Views::RakeView.render_item(item, selected: selected, width: width)
        when :console  then Views::ConsoleView.render_item(item, selected: selected, width: width)
        when :credentials then Views::CredentialsView.render_item(item, selected: selected, width: width)
        when :logs     then Views::LogView.render_item(item, selected: selected, width: width)
        when :mailers  then Views::MailerView.render_item(item, selected: selected, width: width)
        when :jobs     then Views::JobsView.render_item(item, selected: selected, width: width)
        when :custom   then Views::CustomCommandsView.render_item(item, selected: selected, width: width)
        else
          selected ? Flourish::Style.new.reverse.render(item.to_s) : item.to_s
        end
      end.join("\n")
    end

    def render_right_pane(width)
      @detail_viewport.set_width(width - 4)
      @detail_viewport.set_height(@height - 4)
      @detail_viewport.set_content(@detail_content)

      content = @detail_viewport.view
      border_color = UNFOCUSED_COLOR

      box = Flourish::Style.new
        .width(width)
        .height(@height - 2)
        .border(Flourish::Border::ROUNDED)
        .border_foreground(border_color)
        .render(content)

      box_lines = box.lines
      if box_lines.any?
        title = " Detail "
        title_styled = Flourish::Style.new.foreground(border_color).bold.render(title)
        box_lines[0] = inject_title(box_lines[0], title_styled, title.length)
      end

      box_lines.join
    end

    def update_detail_content
      panel = current_panel
      item = panel.selected_item

      @detail_content = case panel.type
      when :status
        Views::StatusView.render_detail(@about_data, @stats_data, @notes_data, width: detail_width)
      when :server
        Views::ServerView.render_detail(@server, width: detail_width)
      when :routes
        item ? Views::RoutesView.render_detail(item, @project.dir, width: detail_width, file_cache: @file_cache) : "Select a route."
      when :database
        item ? Views::DatabaseView.render_detail(item, @project.dir, width: detail_width, file_cache: @file_cache) : "Select a migration."
      when :models
        item ? Views::ModelsView.render_detail(item, width: detail_width) : "Select a model."
      when :tests
        item ? Views::TestsView.render_detail(item, width: detail_width) : "Select a test file."
      when :gems
        item ? Views::GemsView.render_detail(item, width: detail_width) : "Select a gem."
      when :rake
        item ? Views::RakeView.render_detail(item, width: detail_width) : "Select a rake task."
      when :console
        item ? Views::ConsoleView.render_detail(item, width: detail_width) : "Press e to evaluate a Ruby expression."
      when :credentials
        render_credentials_detail(item, detail_width)
      when :logs
        item ? Views::LogView.render_detail(item, width: detail_width) : "Waiting for log entries..."
      when :mailers
        render_mailer_detail(item, detail_width)
      when :jobs
        item ? Views::JobsView.render_detail(item, width: detail_width) : "Select a job."
      when :custom
        item ? Views::CustomCommandsView.render_detail(item, width: detail_width) : "Select a command."
      else
        ""
      end
    end

    def render_status_bar
      left = if @flash.active?
        "  #{@flash.message}"
      else
        " Tab navigate \u2502 j/k scroll \u2502 Enter select \u2502 L log \u2502 ? help \u2502 q quit"
      end

      Flourish::Style.new
        .foreground("#666666")
        .width(@width)
        .render(left.slice(0, @width))
    end

    def render_filter_bar
      Flourish::Style.new.width(@width).render(@input_mode.view)
    end

    def render_confirmation
      return "" unless @confirmation

      text = @confirmation.prompt_text
      return "" unless text

      color = @confirmation.red? ? "#ff6347" : "#e5c07b"
      Flourish::Style.new.foreground(color).width(@width).render(text)
    end

    def render_help
      Views::HelpView.render(width: @width, height: @height)
    end

    def render_credentials_detail(item, width)
      return "Select a credential file." unless item
      if @credentials_content
        Views::CredentialsView.render_detail_content(item, @credentials_content, width: width)
      else
        Views::CredentialsView.render_detail(item, width: width)
      end
    end

    def render_mailer_detail(item, width)
      return "Select a mailer preview." unless item
      if @mailer_preview_content
        Views::MailerView.render_detail_content(item, @mailer_preview_content, width: width)
      else
        Views::MailerView.render_detail(item, width: width)
      end
    end

    def inject_title(top_line, styled_title, title_visible_len)
      ViewHelpers.inject_title(top_line, styled_title, title_visible_len)
    end
  end
end

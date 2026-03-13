# frozen_string_literal: true

module LazyRails
  module Renderer
    FOCUSED_COLOR = "#b48ead"
    UNFOCUSED_COLOR = "#7c7c7c"

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
        box = Chamomile::Style.new
                              .width(width)
                              .height(h)
                              .border(Chamomile::Border::ROUNDED)
                              .border_foreground(border_color)
                              .render(content)

        box_lines = box.lines
        if box_lines.any?
          title = " #{panel.title} "
          title_styled = Chamomile::Style.new.foreground(border_color).bold.render(title)
          box_lines[0] = inject_title(box_lines[0], title_styled, title.length)
        end

        output = box_lines.join
        @panel_render_cache[panel.type] = [key, output]
        sections << output
      end

      Chamomile.vertical(sections, align: :left)
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

      return Views::ErrorView.render(panel.error.to_s, width: width) if panel.error && panel.items.empty?

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

      panel.ensure_visible([height, 1].max) if focused
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
          selected ? Chamomile::Style.new.reverse.render(item.to_s) : item.to_s
        end
      end.join("\n")
    end

    def render_right_pane(width)
      @detail_viewport.width   = width - 4
      @detail_viewport.height  = @height - 4
      @detail_viewport.content = @detail_content

      content = @detail_viewport.view
      border_color = UNFOCUSED_COLOR

      box = Chamomile::Style.new
                            .width(width)
                            .height(@height - 2)
                            .border(Chamomile::Border::ROUNDED)
                            .border_foreground(border_color)
                            .render(content)

      box_lines = box.lines
      if box_lines.any?
        title = " Detail "
        title_styled = Chamomile::Style.new.foreground(border_color).bold.render(title)
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
                          if item
                            Views::RoutesView.render_detail(item, @project.dir, width: detail_width,
                                                                                file_cache: @file_cache)
                          else
                            "Select a route."
                          end
                        when :database
                          if item
                            Views::DatabaseView.render_detail(item, @project.dir, width: detail_width,
                                                                                  file_cache: @file_cache)
                          else
                            "Select a migration."
                          end
                        when :models
                          item ? Views::ModelsView.render_detail(item, width: detail_width) : "Select a model."
                        when :tests
                          item ? Views::TestsView.render_detail(item, width: detail_width) : "Select a test file."
                        when :gems
                          item ? Views::GemsView.render_detail(item, width: detail_width) : "Select a gem."
                        when :rake
                          item ? Views::RakeView.render_detail(item, width: detail_width) : "Select a rake task."
                        when :console
                          if item
                            Views::ConsoleView.render_detail(item,
                                                             width: detail_width)
                          else
                            "Press e to evaluate a Ruby expression."
                          end
                        when :credentials
                          render_credentials_detail(item, detail_width)
                        when :logs
                          item ? Views::LogView.render_detail(item, width: detail_width) : "Waiting for log entries..."
                        when :mailers
                          render_mailer_detail(item, detail_width)
                        when :jobs
                          item ? Views::JobsView.render_detail(item, width: detail_width) : "Select a job."
                        when :custom
                          if item
                            Views::CustomCommandsView.render_detail(item,
                                                                    width: detail_width)
                          else
                            "Select a command."
                          end
                        else
                          ""
                        end
    end

    def render_status_bar
      return Chamomile::Style.new.foreground("#e5c07b").width(@width).render("  #{@flash.message}".slice(0, @width)) if @flash.active?

      hints = [
        ["Tab", "navigate"], ["j/k", "scroll"], ["Enter", "select"],
        ["x", "actions"], ["L", "log"], ["?", "help"], ["q", "quit"]
      ]
      bar = " #{hints.map do |key, desc|
        styled_key = Chamomile::Style.new.bold.foreground('#b48ead').render(key)
        "#{styled_key} #{desc}"
      end.join(" \u2502 ")}"

      Chamomile::Style.new.foreground("#999999").width(@width).render(bar)
    end

    def render_filter_bar
      label = Chamomile::Style.new.bold.foreground("#b48ead").render(" #{@input_mode.styled_label}")
      input = @input_mode.view
      hints = Chamomile::Style.new.foreground("#666666").render("Enter submit \u2502 Esc cancel ")

      hints_len = "Enter submit | Esc cancel ".length
      label_len = @input_mode.styled_label.length + 1
      input_area = @width - label_len - hints_len

      # Build: [label][input padding...][hints]
      input_visible = Chamomile::ANSI.printable_width(input)
      padding = input_area > input_visible ? " " * (input_area - input_visible) : ""

      Chamomile::Style.new.width(@width).render("#{label}#{input}#{padding}#{hints}")
    end

    def render_confirmation_box
      return "" unless @confirmation

      text = @confirmation.prompt_text
      return "" unless text

      color = @confirmation.red? ? "#ff6347" : "#e5c07b"
      cmd = @confirmation.command.is_a?(Array) ? @confirmation.command.join(" ") : @confirmation.command.to_s

      lines = []
      lines << Chamomile::Style.new.foreground(color).bold.render(cmd)
      lines << ""
      lines << text
      lines << ""
      lines << Chamomile::Style.new.foreground("#666666").render("Esc cancel")
      content = lines.join("\n")

      box_width = [cmd.length + 6, text.length + 6].max.clamp(30, @width - 8)

      box = Chamomile::Style.new
                            .width(box_width)
                            .border(Chamomile::Border::ROUNDED)
                            .border_foreground(color)
                            .padding(0, 1)
                            .render(content)

      box_lines = box.lines
      if box_lines.any?
        title_text = " Confirm "
        title_styled = Chamomile::Style.new.foreground(color).bold.render(title_text)
        box_lines[0] = ViewHelpers.inject_title(box_lines[0], title_styled, title_text.length)
      end

      box_lines.join
    end

    def render_command_log_box
      content = @command_log_overlay.render(width: @width - 8)

      box_width = [@width - 4, 60].max
      box_width = [box_width, @width - 2].min

      box = Chamomile::Style.new
                            .width(box_width)
                            .height(@height - 4)
                            .border(Chamomile::Border::ROUNDED)
                            .border_foreground("#b48ead")
                            .padding(0, 1)
                            .render(content)

      box_lines = box.lines
      if box_lines.any?
        title_text = " Command Log "
        title_styled = Chamomile::Style.new.foreground("#b48ead").bold.render(title_text)
        box_lines[0] = ViewHelpers.inject_title(box_lines[0], title_styled, title_text.length)
      end

      box_lines.join
    end

    def render_table_browser_box
      content = @table_browser.render(width: @width - 8, height: @height - 6)

      box_width = [@width - 4, 60].max
      box_width = [box_width, @width - 2].min

      box = Chamomile::Style.new
                            .width(box_width)
                            .height(@height - 4)
                            .border(Chamomile::Border::ROUNDED)
                            .border_foreground("#b48ead")
                            .padding(0, 1)
                            .render(content)

      box_lines = box.lines
      if box_lines.any?
        title_text = " Table Browser "
        title_styled = Chamomile::Style.new.foreground("#b48ead").bold.render(title_text)
        box_lines[0] = ViewHelpers.inject_title(box_lines[0], title_styled, title_text.length)
      end

      box_lines.join
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

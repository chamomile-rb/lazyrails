# frozen_string_literal: true

module LazyRails
  class TableBrowser
    QUERY_SCRIPT = File.expand_path("table_query_runner.rb", __dir__)
    PAGE_SIZE = 100

    attr_reader :screen, :cursor, :selected_table

    def initialize
      @visible = false
      @tables = []
      @cursor = 0
      @scroll_offset = 0
      @selected_table = nil
      @table_widget = nil
      @loading = false
      @error = nil
      @screen = :table_list

      # Query state
      @where_clause = nil
      @order_column = nil
      @order_dir = "ASC"
      @page = 0
      @total_rows = 0
    end

    def visible? = @visible

    def show(table_names)
      @visible = true
      @tables = table_names.sort
      @cursor = 0
      @scroll_offset = 0
      @selected_table = nil
      @table_widget = nil
      @loading = false
      @error = nil
      @screen = :table_list
      reset_query_state
    end

    def hide
      @visible = false
    end

    def handle_key(key)
      case @screen
      when :table_list then handle_table_list_key(key)
      when :row_data   then handle_row_data_key(key)
      end
    end

    def loading!
      @loading = true
      @error = nil
    end

    def fail_loading(error)
      @loading = false
      @error = error
    end

    def load_rows(columns, rows, total: 0)
      @loading = false
      @error = nil
      @total_rows = total

      table_columns = columns.map do |col|
        Petals::Table::Column.new(title: col, width: column_width(col, columns.size))
      end

      table_rows = rows.map do |row|
        row.map { |v| v.nil? ? "NULL" : v.to_s }
      end

      @table_widget = Petals::Table.new(columns: table_columns, rows: table_rows)
    end

    def current_query_params
      params = {}
      params["where"] = @where_clause if @where_clause && !@where_clause.strip.empty?
      params["order"] = order_expression if @order_column && !@order_column.strip.empty?
      params["limit"] = PAGE_SIZE
      params["offset"] = @page * PAGE_SIZE if @page.positive?
      params
    end

    def set_where(clause)
      @where_clause = clause.nil? || clause.strip.empty? ? nil : clause
      @page = 0
    end

    def set_order(input)
      if input.nil? || input.strip.empty?
        @order_column = nil
        @order_dir = "ASC"
      else
        parts = input.strip.split(/\s+/, 2)
        col = parts[0]
        dir = parts[1]&.upcase

        if %w[DESC ASC].include?(dir)
          @order_column = col
          @order_dir = dir
        elsif @order_column == col
          @order_dir = @order_dir == "ASC" ? "DESC" : "ASC"
        else
          @order_column = col
          @order_dir = "ASC"
        end
      end
      @page = 0
    end

    def render(width:, height:)
      case @screen
      when :table_list then render_table_list(width, height)
      when :row_data   then render_row_data(width, height)
      end
    end

    private

    def reset_query_state
      @where_clause = nil
      @order_column = nil
      @order_dir = "ASC"
      @page = 0
      @total_rows = 0
    end

    def order_expression
      "#{@order_column} #{@order_dir}"
    end

    def total_pages
      return 1 if @total_rows <= 0

      (@total_rows.to_f / PAGE_SIZE).ceil
    end

    def handle_table_list_key(key)
      case key
      when "j", :down
        max = [@tables.size - 1, 0].max
        @cursor = [@cursor + 1, max].min
        nil
      when "k", :up
        @cursor = [@cursor - 1, 0].max
        nil
      when :enter
        return nil if @tables.empty?

        @selected_table = @tables[@cursor]
        @screen = :row_data
        reset_query_state
        { action: :load_table, table: @selected_table }
      when :escape, "t"
        :close
      when "q"
        :quit
      end
    end

    def handle_row_data_key(key)
      case key
      when "j", :down
        @table_widget&.move_down
        nil
      when "k", :up
        @table_widget&.move_up
        nil
      when "w"
        { action: :input_where }
      when "o"
        { action: :input_order }
      when "n"
        if @page < total_pages - 1
          @page += 1
          { action: :load_table, table: @selected_table }
        end
      when "p"
        if @page.positive?
          @page -= 1
          { action: :load_table, table: @selected_table }
        end
      when "c"
        reset_query_state
        { action: :load_table, table: @selected_table }
      when :escape
        @screen = :table_list
        @table_widget = nil
        @loading = false
        @error = nil
        nil
      when "q"
        :quit
      end
    end

    def render_table_list(width, height)
      header = Flourish::Style.new.bold.render("Select a Table (#{@tables.size})")
      lines = [header, ""]

      if @tables.empty?
        lines << "No tables found."
      else
        # Paginate: reserve lines for header (2) + footer (2)
        visible_height = [height - 4, 1].max
        adjust_scroll_offset(visible_height)

        visible = @tables[@scroll_offset, visible_height] || []
        visible.each_with_index do |name, i|
          absolute_index = i + @scroll_offset
          lines << if absolute_index == @cursor
                     ViewHelpers.selected_style.render("  #{name.ljust([width - 6, 0].max)}  ")
                   else
                     "  #{name}"
                   end
        end
      end

      lines << ""
      lines << "j/k navigate | Enter select | Esc or t close | q quit"
      lines.join("\n")
    end

    def render_row_data(_width, height)
      header = Flourish::Style.new.bold.render("Table: #{@selected_table}")
      lines = [header, ""]

      # Status line with query info
      status_parts = []
      status_parts << "WHERE #{@where_clause}" if @where_clause
      status_parts << "ORDER BY #{order_expression}" if @order_column
      status_parts << "Page #{@page + 1}/#{total_pages} (#{@total_rows} rows)"
      status_line = status_parts.join(" | ")
      lines << Flourish::Style.new.foreground("#888888").render(status_line)
      lines << ""

      if @loading
        lines << "Loading..."
      elsif @error
        lines << Flourish::Style.new.foreground("#ff6347").render("Error: #{@error}")
      elsif @table_widget
        @table_widget.height = [height - 7, 3].max
        lines << @table_widget.view
      else
        lines << "No data."
      end

      lines << ""
      lines << "j/k scroll | w where | o order | n/p page | c clear | Esc back | q quit"
      lines.join("\n")
    end

    def adjust_scroll_offset(visible_height)
      @scroll_offset = @cursor if @cursor < @scroll_offset
      @scroll_offset = @cursor - visible_height + 1 if @cursor >= @scroll_offset + visible_height
      @scroll_offset = @scroll_offset.clamp(0, [@tables.size - visible_height, 0].max)
    end

    def column_width(col_name, total_columns)
      base = [col_name.length + 2, 12].max
      if total_columns > 6
        # Shrink columns to fit more on screen
        [base, (80 / total_columns).clamp(8..)].min
      else
        [base, 30].min
      end
    end
  end
end

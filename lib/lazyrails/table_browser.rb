# frozen_string_literal: true

module LazyRails
  class TableBrowser
    QUERY_SCRIPT = File.expand_path("table_query_runner.rb", __dir__)

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

    def load_rows(columns, rows)
      @loading = false
      @error = nil

      table_columns = columns.map do |col|
        Petals::Table::Column.new(title: col, width: column_width(col, columns.size))
      end

      table_rows = rows.map do |row|
        row.map { |v| v.nil? ? "NULL" : v.to_s }
      end

      @table_widget = Petals::Table.new(columns: table_columns, rows: table_rows)
    end

    def render(width:, height:)
      case @screen
      when :table_list then render_table_list(width, height)
      when :row_data   then render_row_data(width, height)
      end
    end

    private

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
          if absolute_index == @cursor
            lines << Flourish::Style.new.reverse.render("  #{name.ljust([width - 6, 0].max)}  ")
          else
            lines << "  #{name}"
          end
        end
      end

      lines << ""
      lines << "j/k navigate | Enter select | Esc or t close | q quit"
      lines.join("\n")
    end

    def render_row_data(width, height)
      header = Flourish::Style.new.bold.render("Table: #{@selected_table}")
      lines = [header, ""]

      if @loading
        lines << "Loading..."
      elsif @error
        lines << Flourish::Style.new.foreground("#ff6347").render("Error: #{@error}")
      elsif @table_widget
        @table_widget.height = [height - 5, 3].max
        lines << @table_widget.view
      else
        lines << "No data."
      end

      lines << ""
      lines << "j/k scroll | Esc back to tables | q quit"
      lines.join("\n")
    end

    def adjust_scroll_offset(visible_height)
      @scroll_offset = @cursor if @cursor < @scroll_offset
      @scroll_offset = @cursor - visible_height + 1 if @cursor >= @scroll_offset + visible_height
      @scroll_offset = [[@scroll_offset, @tables.size - visible_height].min, 0].max
    end

    def column_width(col_name, total_columns)
      base = [col_name.length + 2, 12].max
      if total_columns > 6
        # Shrink columns to fit more on screen
        [base, [80 / total_columns, 8].max].min
      else
        [base, 30].min
      end
    end
  end
end

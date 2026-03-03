# frozen_string_literal: true

module LazyRails
  # Custom messages for async operations
  TestFinishedMsg = Data.define(:path, :status, :output)

  class App
    include Chamomile::Model
    include Chamomile::Commands
    include Renderer
    include DataLoader

    PANEL_DEFS = [
      { type: :status,   title: "Status" },
      { type: :server,   title: "Server" },
      { type: :routes,   title: "Routes" },
      { type: :database, title: "Database" },
      { type: :models,   title: "Models" },
      { type: :tests,    title: "Tests" },
      { type: :gems,     title: "Gems" }
    ].freeze

    FOCUSED_COLOR = "#7d56f4"
    UNFOCUSED_COLOR = "#444444"
    LEFT_WIDTH_RATIO = 0.30
    UI_TICK_SECONDS = 1.0

    def initialize(project)
      @project = project
      @panels = PANEL_DEFS.map { |d| Panel.new(type: d[:type], title: d[:title]) }
      @focused_panel = 0
      @width = 80
      @height = 24
      @command_log = CommandLog.new
      @server = ServerManager.new(project)
      @detail_viewport = Petals::Viewport.new(width: 40, height: 20)

      # Component objects
      @flash = Flash.new
      @command_log_overlay = CommandLogOverlay.new(@command_log)
      @table_browser = TableBrowser.new
      @input_mode = InputMode.new

      # Data stores
      @introspect_data = nil
      @about_data = {}
      @stats_data = {}
      @notes_data = []

      # UI state
      @show_help = false
      @confirmation = nil
      @route_grouped = false
      @last_server_state = :stopped

      # Caches
      @detail_content = ""
      @file_cache = FileCache.new
    end

    # ─── Chamomile lifecycle ──────────────────────────────

    def start
      batch(
        load_introspect_cmd,
        load_gems_cmd,
        load_tests_cmd,
        ui_tick
      )
    end

    def update(msg)
      # Handle confirmation mode first
      return handle_confirmation(msg) if @confirmation

      # Handle input mode (filter / prompts)
      return handle_input_mode(msg) if @input_mode.active?

      case msg
      when Chamomile::WindowSizeMsg
        handle_resize(msg)
      when Chamomile::KeyMsg
        return handle_key(msg)
      when Chamomile::TickMsg
        return handle_tick
      when Chamomile::InterruptMsg
        @server.stop
        return quit
      when IntrospectLoadedMsg
        return handle_introspect_loaded(msg)
      when GemsLoadedMsg
        handle_gems_loaded(msg)
      when TestsLoadedMsg
        handle_tests_loaded(msg)
      when CommandFinishedMsg
        return handle_command_finished(msg)
      when TestFinishedMsg
        handle_test_finished(msg)
      when TableRowsLoadedMsg
        handle_table_rows_loaded(msg)
      end

      nil
    end

    def view
      return render_help if @show_help
      return @command_log_overlay.render(width: @width) if @command_log_overlay.visible?
      return @table_browser.render(width: @width, height: @height) if @table_browser.visible?

      left_width = (@width * LEFT_WIDTH_RATIO).to_i
      right_width = @width - left_width - 1

      left_content = render_left_panels(left_width)
      right_content = render_right_pane(right_width)

      layout = Flourish.join_horizontal(Flourish::TOP, left_content, " ", right_content)

      if @confirmation
        layout = "#{layout}\n#{render_confirmation}"
      elsif @input_mode.active?
        layout = "#{layout}\n#{render_filter_bar}"
      else
        layout = "#{layout}\n#{render_status_bar}"
      end

      layout
    end

    private

    # ─── Helpers ──────────────────────────────────────────

    def ui_tick
      tick(UI_TICK_SECONDS)
    end

    def current_panel
      @panels[@focused_panel]
    end

    def find_panel(type)
      @panels.find { |p| p.type == type }
    end

    def panel_visible_height
      heights = distribute_panel_heights(@height - 2)
      h = heights[@focused_panel] || 5
      [h - 2, 1].max
    end

    def detail_width
      [@width - (@width * LEFT_WIDTH_RATIO).to_i - 5, 10].max
    end

    def distribute_panel_heights(total)
      n = @panels.size
      min_unfocused = 3

      unfocused_total = (n - 1) * min_unfocused
      focused_height = total - unfocused_total

      # Fall back to equal distribution if terminal is too small
      if focused_height < min_unfocused
        base = total / n
        remainder = total % n
        return @panels.each_with_index.map { |_, i| i < remainder ? base + 1 : base }
      end

      @panels.each_with_index.map { |_, i| i == @focused_panel ? focused_height : min_unfocused }
    end

    def set_flash(message, duration: 3)
      @flash.set(message, duration: duration)
    end

    def test_all_command
      if File.directory?(File.join(@project.dir, "spec"))
        "bundle exec rspec"
      else
        "bin/rails test"
      end
    end

    def test_failed_command
      if File.directory?(File.join(@project.dir, "spec"))
        "bundle exec rspec --only-failures"
      else
        "bin/rails test --fail-fast"
      end
    end

    def toggle_route_grouping
      panel = find_panel(:routes)
      return unless @introspect_data

      items = if @route_grouped
        @route_grouped = false
        @introspect_data.routes
      else
        @route_grouped = true
        @introspect_data.routes.sort_by do |r|
          r.action.split("#").first rescue "zzz"
        end
      end
      panel.finish_loading(items: items)
      panel.reset_cursor
    end

    # ─── Key handling (from KeyHandler) ───────────────────

    def handle_key(msg)
      # Help overlay intercepts all keys
      if @show_help
        @show_help = false if msg.key == "?" || msg.key == :escape
        return msg.key == "q" ? ((@server.stop; quit)) : nil
      end

      # Command log overlay intercepts all keys
      if @command_log_overlay.visible?
        signal = @command_log_overlay.handle_key(msg.key)
        return (@server.stop; quit) if signal == :quit
        return nil
      end

      # Table browser overlay intercepts all keys
      if @table_browser.visible?
        signal = @table_browser.handle_key(msg.key)
        case signal
        when :quit  then @server.stop; return quit
        when :close then @table_browser.hide
        when Hash
          return load_table_rows_cmd(signal[:table]) if signal[:action] == :load_table
        end
        return nil
      end

      # Handle Shift+Tab (Chamomile sends :tab with [:shift] modifier)
      if msg.key == :tab && msg.shift?
        @focused_panel = (@focused_panel - 1) % @panels.size
        update_detail_content
        return nil
      end

      case msg.key
      when "q"
        @server.stop
        return quit
      when "?"
        @show_help = true
      when "L"
        @command_log_overlay.show
      when :tab
        @focused_panel = (@focused_panel + 1) % @panels.size
        update_detail_content
      when "1".."7"
        idx = msg.key.to_i - 1
        if idx < @panels.size
          @focused_panel = idx
          update_detail_content
        end
      when "j", :down
        current_panel.move_cursor(1, panel_visible_height)
        update_detail_content
      when "k", :up
        current_panel.move_cursor(-1, panel_visible_height)
        update_detail_content
      when :enter
        return handle_enter
      when "/"
        start_filter
      when "R"
        return handle_refresh
      when "z"
        return handle_undo
      else
        return handle_panel_key(msg)
      end

      nil
    end

    def handle_panel_key(msg)
      case current_panel.type
      when :server   then handle_server_key(msg)
      when :database then handle_database_key(msg)
      when :tests    then handle_tests_key(msg)
      when :gems     then handle_gems_key(msg)
      when :routes   then handle_routes_key(msg)
      when :models   then handle_models_key(msg)
      end
    end

    def handle_server_key(msg)
      case msg.key
      when "s"
        @server.start
        set_flash("Starting server on port #{@server.port}...")
      when "S"
        @server.stop
        set_flash("Server stopped.")
      when "r"
        @server.restart
        set_flash("Restarting server...")
      when "p"
        @input_mode.start_input(:change_port, prompt: "Port: ", placeholder: "3000")
      end
      nil
    end

    def handle_database_key(msg)
      case msg.key
      when "t"
        if @introspect_data
          @table_browser.show(@introspect_data.tables.keys)
        else
          set_flash("Data still loading...")
        end
      when "m"
        return run_rails_cmd("bin/rails db:migrate", :database)
      when "M"
        start_confirmation("bin/rails db:rollback", tier: :yellow)
      when "c"
        @input_mode.start_input(:migration_name, prompt: "Migration name: ", placeholder: "CreateUsers")
      when "d"
        migration = current_panel.selected_item
        if migration
          start_confirmation("bin/rails db:migrate:down VERSION=#{migration.version}", tier: :yellow)
        end
      when "u"
        migration = current_panel.selected_item
        return run_rails_cmd("bin/rails db:migrate:up VERSION=#{migration.version}", :database) if migration
      end
      nil
    end

    def handle_tests_key(msg)
      case msg.key
      when "a" then return run_rails_cmd(test_all_command, :tests)
      when "f" then return run_rails_cmd(test_failed_command, :tests)
      end
      nil
    end

    def handle_gems_key(msg)
      case msg.key
      when "u"
        gem_entry = current_panel.selected_item
        return run_rails_cmd(["bundle", "update", gem_entry.name], :gems) if gem_entry
      when "U"
        start_confirmation("bundle update", tier: :yellow)
      when "o"
        gem_entry = current_panel.selected_item
        return open_gem_homepage(gem_entry) if gem_entry
      end
      nil
    end

    def handle_routes_key(msg)
      case msg.key
      when "g"
        toggle_route_grouping
      end
      nil
    end

    def handle_models_key(msg)
      case msg.key
      when "g"
        @input_mode.start_input(:generate_model, prompt: "Model name: ", placeholder: "User name:string email:string")
      end
      nil
    end

    def handle_enter
      panel = current_panel
      item = panel.selected_item
      return nil unless item

      case panel.type
      when :tests
        return run_test_file_cmd(item)
      end

      update_detail_content
      nil
    end

    # ─── Input mode (from InputHandler) ───────────────────

    def start_filter
      return unless %i[routes models tests gems].include?(current_panel.type)

      @input_mode.start_filter
    end

    def handle_input_mode(msg)
      return nil unless msg.is_a?(Chamomile::KeyMsg)

      signal = @input_mode.handle_key(msg)

      case signal
      when :cancelled
        @input_mode.deactivate
        current_panel.filter_text = ""
        current_panel.reset_cursor
      when Hash
        case signal[:action]
        when :submitted
          value = signal[:value]
          purpose = signal[:purpose]
          @input_mode.deactivate
          return handle_input_submit(value, purpose)
        when :changed
          current_panel.filter_text = signal[:value]
          current_panel.reset_cursor
        end
      end

      nil
    end

    def handle_input_submit(value, purpose)
      case purpose
      when :filter
        current_panel.filter_text = value
        current_panel.reset_cursor
        nil
      when :migration_name
        return run_rails_cmd(%w[bin/rails generate migration] + value.split, :database) unless value.empty?
      when :generate_model
        return run_rails_cmd(%w[bin/rails generate model] + value.split, :models) unless value.empty?
      when :change_port
        port = value.to_i
        if port > 0 && port < 65_536
          @server.port = port
          set_flash("Port changed to #{port}")
        else
          set_flash("Invalid port: #{value}")
        end
        nil
      end
    end

    def start_confirmation(command, tier: nil, required_text: nil)
      panel_name = current_panel.title.downcase
      required_text ||= panel_name if tier == :red
      @confirmation = Confirmation.new(command: command, tier: tier, required_text: required_text)
    end

    def handle_confirmation(msg)
      return nil unless msg.is_a?(Chamomile::KeyMsg)

      @confirmation.handle_key(msg.key)

      if @confirmation.confirmed?
        command = @confirmation.command
        panel_type = current_panel.type
        @confirmation = nil
        return run_rails_cmd(command, panel_type)
      elsif @confirmation.cancelled?
        @confirmation = nil
        set_flash("Cancelled.")
      end

      nil
    end

    # ─── Message handling (from MessageHandler) ───────────

    def handle_tick
      @flash.tick

      # Detect server state changes
      current_state = @server.state
      if current_state != @last_server_state
        case current_state
        when :running
          set_flash("Server running on port #{@server.port}")
        when :stopped
          set_flash("Server stopped.") if @last_server_state == :running
        when :error
          set_flash("Server error — check detail pane")
        end
        @last_server_state = current_state
        update_detail_content if current_panel.type == :server
      elsif current_panel.type == :server && @server.log_changed?
        # Refresh server detail content only when log has new output
        update_detail_content
      end

      ui_tick
    end

    def handle_introspect_loaded(msg)
      @file_cache.invalidate

      if msg.error
        load_fallback_data
        [:routes, :database, :models].each { |t| find_panel(t).fail_loading(msg.error) }
        find_panel(:status).fail_loading(msg.error)
      else
        @introspect_data = msg.data

        find_panel(:routes).finish_loading(items: msg.data.routes)

        db_panel = find_panel(:database)
        db_panel.finish_loading(items: msg.data.migrations)
        pending = Views::DatabaseView.pending_count(msg.data.migrations)
        db_panel.update_title(pending > 0 ? "Database (#{pending} pending)" : "Database")

        find_panel(:models).finish_loading(items: msg.data.models)

        # About/stats/notes now come from the same rails runner invocation
        @about_data = msg.data.about || {}
        @stats_data = msg.data.stats || {}
        @notes_data = msg.data.notes || []
        find_panel(:status).fail_loading(nil)
      end

      update_detail_content
      nil
    end

    def handle_gems_loaded(msg)
      find_panel(:gems).finish_loading(items: msg.gems, error: msg.error)
      update_detail_content
    end

    def handle_tests_loaded(msg)
      find_panel(:tests).finish_loading(items: msg.files, error: msg.error)
      update_detail_content
    end

    def handle_command_finished(msg)
      @command_log.add(msg.entry)
      set_flash("#{msg.entry.success? ? "\u2713" : "\u2717"} #{msg.entry.command} (#{msg.entry.duration_ms}ms)")

      # Reload panel data after command
      case msg.panel
      when :database, :models
        return load_introspect_cmd
      when :gems
        return load_gems_cmd
      when :tests
        return load_tests_cmd
      end

      nil
    end

    def handle_test_finished(msg)
      tests_panel = find_panel(:tests)
      idx = tests_panel.items.index { |f| f.path == msg.path }
      if idx
        tests_panel.replace_item_at(idx, TestFile.new(
          path: msg.path,
          status: msg.status,
          last_output: msg.output
        ))
      end
      set_flash("#{msg.status == :passed ? "\u2713" : "\u2717"} #{msg.path}")
      update_detail_content
    end

    def handle_table_rows_loaded(msg)
      # Ignore stale results if browser was closed or user navigated to a different table
      return unless @table_browser.visible? && @table_browser.screen == :row_data
      return unless msg.table == @table_browser.selected_table

      if msg.error
        @table_browser.fail_loading(msg.error)
      else
        @table_browser.load_rows(msg.columns, msg.rows)
      end
    end

    def handle_resize(msg)
      @width = msg.width
      @height = msg.height
      right_width = @width - (@width * LEFT_WIDTH_RATIO).to_i - 1
      @detail_viewport.set_width(right_width - 4)
      @detail_viewport.set_height(@height - 4)
      update_detail_content
    end

    def handle_refresh
      panel = current_panel
      panel.start_loading
      case panel.type
      when :routes, :database, :models, :status
        return load_introspect_cmd
      when :gems
        return load_gems_cmd
      when :tests
        return load_tests_cmd
      end
      nil
    end

    def handle_undo
      entry = @command_log.last_reversible
      unless entry
        set_flash("Nothing to undo.")
        return nil
      end

      reverse = @command_log.reverse_command(entry)
      unless reverse
        set_flash("Cannot undo.")
        return nil
      end

      start_confirmation(reverse, tier: :yellow)
      nil
    end

    def load_fallback_data
      schema_path = File.join(@project.dir, "db/schema.rb")
      if File.exist?(schema_path)
        tables = Parsers::Schema.parse(File.read(schema_path))
        models = tables.map do |table_name, cols|
          ModelInfo.new(name: ViewHelpers.classify_name(table_name), table_name: table_name, columns: cols)
        end
        find_panel(:models).finish_loading(items: models)
      end
    end
  end
end

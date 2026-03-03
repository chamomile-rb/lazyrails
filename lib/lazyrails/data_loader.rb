# frozen_string_literal: true

module LazyRails
  module DataLoader
    private

    def load_introspect_cmd
      project_dir = @project.dir
      cmd(-> {
        begin
          script = Introspect::RUNNER_SCRIPT
          result = CommandRunner.run("bin/rails runner #{script}", dir: project_dir)

          if result.success?
            data = Introspect.load(result.stdout)
            IntrospectLoadedMsg.new(data: data, error: nil)
          else
            IntrospectLoadedMsg.new(data: nil, error: result.stderr)
          end
        rescue => e
          IntrospectLoadedMsg.new(data: nil, error: e.message)
        end
      })
    end

    def load_gems_cmd
      project_dir = @project.dir
      cmd(-> {
        begin
          lockfile = File.join(project_dir, "Gemfile.lock")
          gems = Parsers::GemfileLock.parse(lockfile)
          GemsLoadedMsg.new(gems: gems, error: nil)
        rescue => e
          GemsLoadedMsg.new(gems: [], error: e.message)
        end
      })
    end

    def load_tests_cmd
      project_dir = @project.dir
      cmd(-> {
        begin
          files = []
          test_dir = File.join(project_dir, "test")
          spec_dir = File.join(project_dir, "spec")

          if File.directory?(spec_dir)
            Dir.glob("#{spec_dir}/**/*_spec.rb").sort.each do |f|
              files << TestFile.new(path: f.sub("#{project_dir}/", ""))
            end
          end

          if File.directory?(test_dir)
            Dir.glob("#{test_dir}/**/*_test.rb").sort.each do |f|
              files << TestFile.new(path: f.sub("#{project_dir}/", ""))
            end
          end

          TestsLoadedMsg.new(files: files, error: nil)
        rescue => e
          TestsLoadedMsg.new(files: [], error: e.message)
        end
      })
    end

    def run_rails_cmd(command, panel_type)
      display = command.is_a?(Array) ? command.join(" ") : command
      set_flash("Running: #{display}...")
      project_dir = @project.dir
      cmd(-> {
        result = CommandRunner.run(command, dir: project_dir)
        CommandFinishedMsg.new(entry: result, panel: panel_type)
      })
    end

    def run_test_file_cmd(test_file)
      set_flash("Running: #{test_file.path}...")
      project_dir = @project.dir
      path = test_file.path
      test_cmd = path.start_with?("spec/") ? ["bundle", "exec", "rspec", path] : ["bin/rails", "test", path]

      cmd(-> {
        result = CommandRunner.run(test_cmd, dir: project_dir)
        status = result.success? ? :passed : :failed
        TestFinishedMsg.new(path: path, status: status, output: result.stdout + result.stderr)
      })
    end

    def load_table_rows_cmd(table_name)
      @table_browser.loading!
      project_dir = @project.dir
      script = TableBrowser::QUERY_SCRIPT
      cmd(-> {
        begin
          result = CommandRunner.run(["bin/rails", "runner", script, table_name], dir: project_dir)
          if result.success?
            data = JSON.parse(result.stdout, symbolize_names: false)
            if data["error"]
              TableRowsLoadedMsg.new(table: table_name, columns: [], rows: [], error: data["error"])
            else
              TableRowsLoadedMsg.new(table: table_name, columns: data["columns"], rows: data["rows"], error: nil)
            end
          else
            TableRowsLoadedMsg.new(table: table_name, columns: [], rows: [], error: result.stderr)
          end
        rescue => e
          TableRowsLoadedMsg.new(table: table_name, columns: [], rows: [], error: e.message)
        end
      })
    end

    def open_gem_homepage(gem_entry)
      project_dir = @project.dir
      name = gem_entry.name
      cmd(-> {
        begin
          result = CommandRunner.run(["bundle", "info", name], dir: project_dir)
          if result.success? && (match = result.stdout.match(/Homepage:\s*(\S+)/))
            Platform.open_url(match[1])
          end
        rescue
          # Best-effort — ignore failures
        end
        nil
      })
    end
  end
end

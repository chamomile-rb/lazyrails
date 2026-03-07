# frozen_string_literal: true

module LazyRails
  module DataLoader
    private

    def load_introspect_cmd
      project_dir = @project.dir
      cmd(lambda do
        script = Introspect::RUNNER_SCRIPT
        result = CommandRunner.run("bin/rails runner #{script}", dir: project_dir)

        if result.success?
          data = Introspect.load(result.stdout)
          IntrospectLoadedMsg.new(data: data, error: nil)
        else
          IntrospectLoadedMsg.new(data: nil, error: result.stderr)
        end
      rescue StandardError => e
        IntrospectLoadedMsg.new(data: nil, error: e.message)
      end)
    end

    def load_gems_cmd
      project_dir = @project.dir
      cmd(lambda do
        lockfile = File.join(project_dir, "Gemfile.lock")
        gems = Parsers::GemfileLock.parse(lockfile)
        GemsLoadedMsg.new(gems: gems, error: nil)
      rescue StandardError => e
        GemsLoadedMsg.new(gems: [], error: e.message)
      end)
    end

    def load_tests_cmd
      project_dir = @project.dir
      cmd(lambda do
        files = []
        test_dir = File.join(project_dir, "test")
        spec_dir = File.join(project_dir, "spec")

        if File.directory?(spec_dir)
          Dir.glob("#{spec_dir}/**/*_spec.rb").each do |f|
            files << TestFile.new(path: f.sub("#{project_dir}/", ""))
          end
        end

        if File.directory?(test_dir)
          Dir.glob("#{test_dir}/**/*_test.rb").each do |f|
            files << TestFile.new(path: f.sub("#{project_dir}/", ""))
          end
        end

        TestsLoadedMsg.new(files: files, error: nil)
      rescue StandardError => e
        TestsLoadedMsg.new(files: [], error: e.message)
      end)
    end

    def run_rails_cmd(command, panel_type)
      display = command.is_a?(Array) ? command.join(" ") : command
      set_flash("Running: #{display}...")
      project_dir = @project.dir
      cmd(lambda {
        result = CommandRunner.run(command, dir: project_dir)
        CommandFinishedMsg.new(entry: result, panel: panel_type)
      })
    end

    def run_test_file_cmd(test_file)
      set_flash("Running: #{test_file.path}...")
      project_dir = @project.dir
      path = test_file.path
      test_cmd = path.start_with?("spec/") ? ["bundle", "exec", "rspec", path] : ["bin/rails", "test", path]

      cmd(lambda {
        result = CommandRunner.run(test_cmd, dir: project_dir)
        status = result.success? ? :passed : :failed
        TestFinishedMsg.new(path: path, status: status, output: result.stdout + result.stderr)
      })
    end

    def load_table_rows_cmd(table_name)
      @table_browser.loading!
      project_dir = @project.dir
      script = TableBrowser::QUERY_SCRIPT
      query_json = JSON.generate(@table_browser.current_query_params)
      args = ["bin/rails", "runner", script, table_name, query_json]
      cmd(lambda do
        result = CommandRunner.run(args, dir: project_dir)
        if result.success?
          data = JSON.parse(result.stdout, symbolize_names: false)
          if data["error"]
            TableRowsLoadedMsg.new(table: table_name, columns: [], rows: [], total: 0, error: data["error"])
          else
            TableRowsLoadedMsg.new(table: table_name, columns: data["columns"], rows: data["rows"],
                                   total: data["total"] || 0, error: nil)
          end
        else
          TableRowsLoadedMsg.new(table: table_name, columns: [], rows: [], total: 0, error: result.stderr)
        end
      rescue StandardError => e
        TableRowsLoadedMsg.new(table: table_name, columns: [], rows: [], total: 0, error: e.message)
      end)
    end

    def run_eval_cmd(expression)
      project_dir = @project.dir
      cmd(lambda do
        script = "puts (#{expression}).inspect"
        result = CommandRunner.run(
          ["bin/rails", "runner", "-e", "development", script],
          dir: project_dir
        )
        entry = EvalEntry.new(
          expression: expression,
          result: result.success? ? result.stdout.strip : nil,
          error: result.success? ? nil : result.stderr.strip,
          duration_ms: result.duration_ms
        )
        EvalFinishedMsg.new(entry: entry)
      rescue StandardError => e
        entry = EvalEntry.new(expression: expression, result: nil, error: e.message, duration_ms: 0)
        EvalFinishedMsg.new(entry: entry)
      end)
    end

    def decrypt_credentials_cmd(credential_file)
      project_dir = @project.dir
      env = credential_file.environment.gsub(" (default)", "")
      cmd(lambda do
        args = ["bin/rails", "credentials:show"]
        args += ["--environment", env] unless env == "development"
        result = CommandRunner.run(args, dir: project_dir)
        CredentialsLoadedMsg.new(
          environment: credential_file.environment,
          content: result.success? ? result.stdout : nil,
          error: result.success? ? nil : result.stderr
        )
      rescue StandardError => e
        CredentialsLoadedMsg.new(environment: credential_file.environment, content: nil, error: e.message)
      end)
    end

    def load_mailers_cmd
      project_dir = @project.dir
      cmd(lambda do
        preview_dirs = [
          File.join(project_dir, "test/mailers/previews"),
          File.join(project_dir, "spec/mailers/previews")
        ].select { |d| Dir.exist?(d) }

        previews = preview_dirs.flat_map do |dir|
          Dir.glob(File.join(dir, "**/*_preview.rb")).flat_map do |file|
            content = File.read(file)
            mailer = File.basename(file, "_preview.rb").then do |n|
              n.split("_").map(&:capitalize).join
            end
            methods = content.scan(/def\s+(\w+)/).flatten.reject { |m| m == "initialize" }
            methods.map do |m|
              MailerPreview.new(
                mailer_class: mailer,
                method_name: m,
                preview_path: file
              )
            end
          end
        end

        MailersLoadedMsg.new(previews: previews, error: nil)
      rescue StandardError => e
        MailersLoadedMsg.new(previews: [], error: e.message)
      end)
    end

    def render_mailer_preview_cmd(preview)
      project_dir = @project.dir
      preview_path = preview.preview_path
      mailer_class = preview.mailer_class
      method_name = preview.method_name
      cmd(lambda do
        escaped_path = preview_path.gsub("\\", "\\\\\\\\").gsub("'", "\\\\'")
        script = "require '#{escaped_path}'; " \
                 "mail = #{mailer_class}Preview.new.public_send(:#{method_name}); " \
                 "puts JSON.generate({ subject: mail.subject, to: mail.to, from: mail.from, " \
                 "body: mail.body.decoded.gsub(/<[^>]+>/, '').squeeze(' ').strip })"
        result = CommandRunner.run(["bin/rails", "runner", script], dir: project_dir)
        if result.success?
          data = JSON.parse(result.stdout, symbolize_names: true)
          MailerPreviewLoadedMsg.new(preview: preview, error: nil, **data)
        else
          MailerPreviewLoadedMsg.new(preview: preview, subject: nil, to: nil,
                                     from: nil, body: nil, error: result.stderr)
        end
      rescue StandardError => e
        MailerPreviewLoadedMsg.new(preview: preview, subject: nil, to: nil,
                                   from: nil, body: nil, error: e.message)
      end)
    end

    def load_jobs_cmd(filter = "all")
      project_dir = @project.dir
      script = File.expand_path("jobs_query_runner.rb", __dir__)
      params = { "status" => filter, "limit" => 200 }

      cmd(lambda do
        result = CommandRunner.run(
          ["bin/rails", "runner", script, "stats_and_list", JSON.generate(params)],
          dir: project_dir
        )

        if result.success?
          data = JSON.parse(result.stdout, symbolize_names: false)
          return JobsLoadedMsg.new(available: false, jobs: [], counts: {}, error: nil) if data["available"] == false

          counts = (data["counts"] || {}).transform_keys(&:to_sym)
          jobs = (data["jobs"] || []).map { |j| parse_job_entry(j) }
          JobsLoadedMsg.new(available: true, jobs: jobs, counts: counts, error: nil)
        else
          JobsLoadedMsg.new(available: true, jobs: [], counts: {}, error: result.stderr)
        end
      rescue StandardError => e
        JobsLoadedMsg.new(available: true, jobs: [], counts: {}, error: e.message)
      end)
    end

    def retry_job_cmd(fe_id)
      run_job_action_cmd("retry", fe_id)
    end

    def discard_job_cmd(fe_id)
      run_job_action_cmd("discard", fe_id)
    end

    def retry_all_jobs_cmd(filter: nil, queue: nil)
      project_dir = @project.dir
      script = File.expand_path("jobs_query_runner.rb", __dir__)
      params = {}
      params["class_name"] = filter if filter
      params["queue"] = queue if queue
      cmd(lambda do
        result = CommandRunner.run(
          ["bin/rails", "runner", script, "retry_all", JSON.generate(params)],
          dir: project_dir
        )
        if result.success?
          data = JSON.parse(result.stdout, symbolize_names: false)
          JobActionMsg.new(action: "retry_all", job_id: nil, success: data["success"], error: data["error"])
        else
          JobActionMsg.new(action: "retry_all", job_id: nil, success: false, error: result.stderr)
        end
      rescue StandardError => e
        JobActionMsg.new(action: "retry_all", job_id: nil, success: false, error: e.message)
      end)
    end

    def dispatch_job_cmd(job_id)
      run_job_action_cmd("dispatch", job_id)
    end

    def discard_scheduled_job_cmd(job_id)
      run_job_action_cmd("discard_scheduled", job_id)
    end

    def run_job_action_cmd(action, id)
      project_dir = @project.dir
      script = File.expand_path("jobs_query_runner.rb", __dir__)
      cmd(lambda do
        result = CommandRunner.run(["bin/rails", "runner", script, action, id.to_s], dir: project_dir)
        if result.success?
          data = JSON.parse(result.stdout, symbolize_names: false)
          JobActionMsg.new(action: action, job_id: id, success: data["success"], error: data["error"])
        else
          JobActionMsg.new(action: action, job_id: id, success: false, error: result.stderr)
        end
      rescue StandardError => e
        JobActionMsg.new(action: action, job_id: id, success: false, error: e.message)
      end)
    end

    def parse_job_entry(j)
      JobEntry.new(
        id: j["id"], fe_id: j["fe_id"], class_name: j["class_name"],
        queue_name: j["queue_name"], status: j["status"], priority: j["priority"],
        active_job_id: j["active_job_id"], arguments: j["arguments"],
        error_class: j["error_class"], error_message: j["error_message"],
        backtrace: j["backtrace"], worker_id: j["worker_id"],
        started_at: j["started_at"], scheduled_at: j["scheduled_at"],
        finished_at: j["finished_at"], failed_at: j["failed_at"],
        concurrency_key: j["concurrency_key"], expires_at: j["expires_at"],
        created_at: j["created_at"]
      )
    end

    def open_gem_homepage(gem_entry)
      project_dir = @project.dir
      name = gem_entry.name
      cmd(lambda do
        result = CommandRunner.run(["bundle", "info", name], dir: project_dir)
        if result.success? && (match = result.stdout.match(/Homepage:\s*(\S+)/))
          Platform.open_url(match[1])
        end
      rescue StandardError
        # Best-effort — ignore failures
      end)
    end
  end
end

# frozen_string_literal: true

module LazyRails
  class CommandRunner
    # cmd can be a String (passed to shell) or Array (exec'd directly, no shell).
    # Use Array form when the command includes user input to prevent injection.
    def self.run(cmd, dir:, env: {})
      env = env.merge("DISABLE_SPRING" => "1")
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      stdout, stderr, status = if cmd.is_a?(Array)
        Open3.capture3(env, *cmd, chdir: dir)
      else
        Open3.capture3(env, cmd, chdir: dir)
      end
      duration = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round
      stdout = force_utf8(stdout)
      stderr = force_utf8(stderr)

      display_cmd = cmd.is_a?(Array) ? cmd.join(" ") : cmd
      CommandEntry.new(
        command: display_cmd,
        exit_code: status.exitstatus || 1,
        duration_ms: duration,
        timestamp: Time.now,
        stdout: stdout,
        stderr: stderr
      )
    end

    def self.stream(cmd, dir:, env: {}, &block)
      env = env.merge("DISABLE_SPRING" => "1")
      Open3.popen2e(env, cmd, chdir: dir) do |stdin, output, wait_thr|
        stdin.close
        output.each_line { |line| block.call(force_utf8(line)) }
        wait_thr.value
      end
    end

    def self.force_utf8(str)
      str.force_encoding("UTF-8").encode("UTF-8", invalid: :replace, undef: :replace)
    end
  end
end

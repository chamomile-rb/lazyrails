# frozen_string_literal: true

module LazyRails
  class Project
    attr_reader :dir, :rails_version, :ruby_version, :app_name, :git_branch

    def initialize(dir:, style:, rails_version: nil, ruby_version: nil, app_name: nil, git_branch: nil)
      @dir = dir
      @style = style # :modern, :old, :gemfile_only
      @rails_version = rails_version
      @ruby_version = ruby_version
      @app_name = app_name
      @git_branch = git_branch
    end

    def old_rails?
      @style == :old
    end

    def bin_rails
      case @style
      when :modern then "bin/rails"
      when :old then "script/rails"
      else "bundle exec rails"
      end
    end

    def self.detect(dir)
      dir = File.expand_path(dir)
      return nil unless File.directory?(dir)

      style = detect_style(dir)
      return nil unless style

      rails_version = detect_rails_version(dir)
      ruby_version = detect_ruby_version
      app_name = detect_app_name(dir)
      git_branch = detect_git_branch(dir)

      new(
        dir: dir,
        style: style,
        rails_version: rails_version,
        ruby_version: ruby_version,
        app_name: app_name,
        git_branch: git_branch
      )
    end

    def self.detect_style(dir)
      bin_rails = File.join(dir, "bin/rails")
      if File.exist?(bin_rails) && File.executable?(bin_rails)
        :modern
      elsif File.exist?(File.join(dir, "script/rails"))
        :old
      elsif gemfile_has_rails?(dir)
        :gemfile_only
      end
    end

    def self.gemfile_has_rails?(dir)
      gemfile = File.join(dir, "Gemfile")
      return false unless File.exist?(gemfile)

      File.read(gemfile).match?(/gem\s+['"]rails['"]/)
    end

    def self.detect_rails_version(dir)
      lockfile = File.join(dir, "Gemfile.lock")
      return nil unless File.exist?(lockfile)

      content = File.read(lockfile)
      match = content.match(/^\s+rails \((\S+)\)/)
      match[1] if match
    end

    def self.detect_ruby_version
      `ruby -v`.strip.match(/ruby (\S+)/)[1]
    rescue
      nil
    end

    def self.detect_app_name(dir)
      app_rb = File.join(dir, "config/application.rb")
      return File.basename(dir) unless File.exist?(app_rb)

      content = File.read(app_rb)
      match = content.match(/module\s+(\w+)/)
      match ? match[1] : File.basename(dir)
    end

    def self.detect_git_branch(dir)
      git_path = File.join(dir, ".git")

      # Handle worktrees/submodules where .git is a file
      if File.file?(git_path)
        gitdir_ref = File.read(git_path).strip
        if (match = gitdir_ref.match(/\Agitdir:\s*(.+)/))
          head_path = File.join(match[1], "HEAD")
        else
          return nil
        end
      elsif File.directory?(git_path)
        head_path = File.join(git_path, "HEAD")
      else
        return nil
      end

      return nil unless File.exist?(head_path)

      content = File.read(head_path).strip
      match = content.match(%r{ref: refs/heads/(.+)})
      match ? match[1] : content[0..7]
    end

    private_class_method :detect_style, :gemfile_has_rails?, :detect_rails_version,
                         :detect_ruby_version, :detect_app_name, :detect_git_branch
  end
end

# frozen_string_literal: true

require "chamomile"
require "petals"
require "flourish"
require "json"
require "open3"

require_relative "lazyrails/version"

# Data structs
require_relative "lazyrails/structs"

# Core
require_relative "lazyrails/view_helpers"
require_relative "lazyrails/command_runner"
require_relative "lazyrails/command_log"
require_relative "lazyrails/project"
require_relative "lazyrails/introspect"
require_relative "lazyrails/server_manager"
require_relative "lazyrails/confirmation"
require_relative "lazyrails/panel"
require_relative "lazyrails/file_cache"
require_relative "lazyrails/platform"

# Component objects
require_relative "lazyrails/flash"
require_relative "lazyrails/command_log_overlay"
require_relative "lazyrails/table_browser"
require_relative "lazyrails/input_mode"

# Parsers
require_relative "lazyrails/parsers/schema"
require_relative "lazyrails/parsers/model_file"
require_relative "lazyrails/parsers/gemfile_lock"
require_relative "lazyrails/parsers/rails_about"
require_relative "lazyrails/parsers/rails_stats"
require_relative "lazyrails/parsers/rails_notes"
require_relative "lazyrails/parsers/test_output"

# Views
require_relative "lazyrails/views/status_view"
require_relative "lazyrails/views/server_view"
require_relative "lazyrails/views/routes_view"
require_relative "lazyrails/views/database_view"
require_relative "lazyrails/views/models_view"
require_relative "lazyrails/views/tests_view"
require_relative "lazyrails/views/gems_view"
require_relative "lazyrails/views/command_log_view"
require_relative "lazyrails/views/help_view"
require_relative "lazyrails/views/error_view"

# App modules (stateless utilities)
require_relative "lazyrails/renderer"
require_relative "lazyrails/data_loader"
require_relative "lazyrails/app"

module LazyRails
end

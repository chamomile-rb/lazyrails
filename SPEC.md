# LazyRails — Specification

A lazygit-style terminal UI for the Rails command line. Built on the Chamomile ecosystem (chamomile + petals + flourish).

## Overview

LazyRails gives Rails developers a fast, navigable TUI that surfaces everything the Rails CLI offers — routes, migrations, models, tests, server logs, gems — in a single split-pane interface. Tab between panels, drill into details, and run commands without memorizing flags.

Every command we run is logged transparently so users learn the CLI as they use the TUI.

## Dependencies

```ruby
spec.add_dependency "chamomile", "~> 0.1"
spec.add_dependency "petals",    "~> 0.1"
spec.add_dependency "flourish",  "~> 0.1"
```

Runtime requirement: a Rails project directory (detected via `bin/rails`, or `Gemfile` with `rails` gem).

## Architecture

### Elm Architecture (Model/Update/View)

```
LazyRails::App
  include Chamomile::Model

  @panels         — array of Panel structs
  @focused_panel  — index into @panels
  @detail_view    — currently rendered right-side content
  @server         — ServerManager (subprocess handle)
  @command_log    — ring buffer of CommandEntry structs
  @flash          — status bar message + expiry
```

Each panel is a self-contained data source with its own cursor, scroll offset, and cached data. The App model owns all state; panels are plain data structs, not separate Chamomile models.

### Data Strategy: Rails APIs via `rails runner`, not text parsing

Instead of parsing the text output of commands like `rails routes` or `db:migrate:status`, we use Rails' internal APIs through `rails runner` and get structured JSON back. This eliminates fragile regex parsing entirely.

| Data | API | Fallback (Rails can't boot) |
|------|-----|-----------------------------|
| Routes | `Rails.application.routes.routes` + `ActionDispatch::Routing::RouteWrapper` | None (need Rails) |
| Schema/columns | `ActiveRecord::Base.connection.columns(table)` | Parse `db/schema.rb` with regex |
| Migrations | `ActiveRecord::SchemaMigration.all_versions` + `MigrationContext` | Glob `db/migrate/` files |
| Associations | `Model.reflect_on_all_associations` | Regex on model files |
| Validations | `Model.validators` | Regex on model files |
| Gems | `Bundler::LockfileParser` (plain Ruby, no Rails needed) | — |
| About/Stats/Notes | `rails about` / `rails stats` / `rails notes` (text, parsed) | None (need Rails) |

**How it works:** A single `rails runner` invocation executes `lib/lazyrails/introspect.rb`, which dumps all introspectable data as one JSON blob to stdout. One boot, one JSON parse, all panel data populated.

```ruby
# lib/lazyrails/introspect.rb — executed via: bin/rails runner lib/lazyrails/introspect.rb
require "json"

data = {}

# Routes
data[:routes] = Rails.application.routes.routes.filter_map do |route|
  w = ActionDispatch::Routing::RouteWrapper.new(route)
  next if w.internal?
  { verb: w.verb, path: w.path, action: w.endpoint, name: w.name, engine: w.engine? }
end

# Tables + columns
conn = ActiveRecord::Base.connection
data[:tables] = conn.tables.sort.to_h do |table|
  cols = conn.columns(table).map { |c| { name: c.name, type: c.type, null: c.null, default: c.default, limit: c.limit } }
  [table, cols]
end

# Migrations
applied = ActiveRecord::SchemaMigration.all_versions
context = ActiveRecord::MigrationContext.new(ActiveRecord::Migrator.migrations_paths)
data[:migrations] = context.migrations.map do |m|
  { status: applied.include?(m.version.to_s) ? "up" : "down", version: m.version, name: m.name, filename: m.filename }
end

# Models + associations + validations
data[:models] = ActiveRecord::Base.descendants.filter_map do |model|
  next if model.abstract_class? || !model.table_exists?
  assocs = model.reflect_on_all_associations.map { |a| { macro: a.macro, name: a.name, class_name: a.class_name } }
  valids = model.validators.map { |v| { kind: v.kind, attributes: v.attributes, options: v.options.except(:if, :unless) } }
  { name: model.name, table: model.table_name, associations: assocs, validations: valids }
rescue => e
  { name: model.name, error: e.message }
end

# Connection info
data[:connection] = {
  adapter: conn.adapter_name,
  database: conn.current_database,
  tables_count: conn.tables.size,
}

puts JSON.generate(data)
```

**Benefits:**
- One `rails runner` call replaces 3+ separate commands
- Structured JSON — no regex, no format fragility
- Catches engine routes, STI models, meta-programmed associations
- Fallback parsers (schema.rb, model files) only activate when Rails can't boot

### Panel Layout

```
┌─ Status ──────────┐┌─ Detail ────────────────────────────┐
│ Rails 7.2.1       ││                                     │
│ Ruby 3.3.0        ││  Route detail / migration SQL /     │
│ Environment: dev   ││  model schema / test output /       │
│ DB: postgresql     ││  server logs / gem info             │
├─ Server ──────────┤│                                     │
│ ● Running :3000   ││                                     │
├─ Routes ──────────┤│                                     │
│  GET  /users      ││                                     │
│  POST /users      ││                                     │
│▸ GET  /users/:id  ││                                     │
│  ...              ││                                     │
├─ Database ────────┤│                                     │
│  ↑ 20240101 Creat ││                                     │
│▸ ↓ 20240115 AddEm ││                                     │
├─ Models ──────────┤│                                     │
│  User (12 cols)   ││                                     │
│▸ Post  (8 cols)   ││                                     │
├─ Tests ───────────┤│                                     │
│  test/models/     ││                                     │
│▸ test/controllers/││                                     │
├─ Gems ────────────┤│                                     │
│  rails (7.2.1)    ││                                     │
│▸ pg (1.5.4)       ││                                     │
└───────────────────┘└─────────────────────────────────────┘
 Tab navigate │ j/k scroll │ Enter select │ L log │ ? help │ q quit
```

Left column: ~30% width, 7 stacked panels.
Right column: ~70% width, single detail pane.

---

## Panels

### 1. Status
**Data source:** `bin/rails about` (parsed).

Displays:
- Rails version, Ruby version
- Environment (RAILS_ENV, defaults to `development`)
- Database adapter + schema version
- App name (from `config/application.rb`)
- Working directory
- Git branch (if in a git repo)

**Detail view:** Full `rails about` output + `rails stats` output (code statistics table).

**Refresh:** On startup only (static info).

**Edge cases:**
- `rails about` fails if Rails can't boot → show error, still populate what we can from `Gemfile.lock` and `ruby -v`

### 2. Server
**Data source:** Managed subprocess (`bin/rails server`).

Displays:
- Server state: Stopped / Starting / Running / Error
- Bound address and port (default `localhost:3000`)
- PID when running

**Detail view:** Live server log output (tail of stdout/stderr). Scrollable via Viewport.

**Keybindings:**
| Key | Action |
|-----|--------|
| `s` | Start server (`bin/rails server`) |
| `S` | Stop server (SIGTERM, then SIGKILL after 5s) |
| `r` | Restart server |
| `p` | Change port (TextInput prompt) |

**Subprocess management:** `Process.spawn` with stdout/stderr pipes, streamed into a ring buffer (last 2000 lines). SIGTERM on quit; SIGKILL if it doesn't exit within 5 seconds.

**Edge cases:**
- Port already in use → capture stderr, show error in detail view with the port conflict message
- Server crashes on boot (missing gems, syntax error) → show stderr output, set state to Error
- User quits LazyRails while server is running → always stop server on exit

### 3. Routes
**Data source:** `Rails.application.routes.routes` + `ActionDispatch::Routing::RouteWrapper` (via introspect.rb JSON).

Each route: `Route = Data.define(:verb, :path, :action, :name, :engine)`

Displays:
- `VERB  /path  controller#action`
- Color-coded by verb: GET=green, POST=blue, PUT/PATCH=yellow, DELETE=red
- Engine routes grouped under a header (e.g., "Devise::Engine", "Sidekiq::Web")

**Detail view:** Selected route expanded:
- Full path with format constraints
- Controller file path (resolved from `app/controllers/`)
- Whether the action method exists in the controller file
- Named route helper (e.g., `users_path`, `edit_user_path`)

**Keybindings:**
| Key | Action |
|-----|--------|
| `/` | Filter routes (TextInput — searches name, path, and action) |
| `g` | Group by controller (toggle) |
| `Enter` | Show detail |

**Refresh:** On startup + `R` to reload (re-runs introspect.rb).

**Edge cases:**
- No routes → empty array from introspect → show "No routes defined"
- Engine routes → `RouteWrapper#engine?` returns true; group these by engine name
- API-only apps → same structured data, just different routes present
- Internal routes (Rails info/welcome pages) → filtered out by `RouteWrapper#internal?`

### 4. Database
**Data source:** `ActiveRecord::SchemaMigration.all_versions` + `ActiveRecord::MigrationContext` (via introspect.rb JSON).

Each migration: `Migration = Data.define(:status, :version, :name, :file_path, :database)`

Displays:
- `↑ 20240101120000  CreateUsers` (up = green arrow)
- `↓ 20240115090000  AddEmailToUsers` (down = red arrow)
- Multi-database apps: group by database name

**Detail view:** Migration file contents (read from the `filename` path returned by introspect).

**Keybindings:**
| Key | Action |
|-----|--------|
| `m` | Run `db:migrate` (confirmation: green) |
| `M` | Run `db:rollback` (confirmation: yellow) |
| `Enter` | View migration file |
| `c` | Create migration (TextInput → `rails generate migration NAME`) |
| `d` | Migrate down this specific version (confirmation: yellow) |
| `u` | Migrate up this specific version |

**Fallback:** When Rails can't boot (no DB), glob `db/migrate/*.rb` to show migration files without up/down status.

**Edge cases:**
- **Database doesn't exist** → introspect.rb catches `ActiveRecord::NoDatabaseError`, returns `{ migrations_error: "no_database" }` → show "No database — press `C` to create (`db:create`)"
- **No migrations** → empty array → "No migrations yet"
- **Multi-database** → introspect.rb iterates each database config and returns migrations grouped by database name
- **Pending migrations** → any migration with status `"down"` is pending; show count in panel title: "Database (2 pending)"

### 5. Models
**Data source:** `ActiveRecord::Base.descendants` + `reflect_on_all_associations` + `validators` + `connection.columns` (via introspect.rb JSON).

Each model: `ModelInfo = Data.define(:name, :file_path, :table_name, :columns, :associations, :validations)`

Displays:
- Model name + column count
- STI/abstract indicators if applicable

**Detail view:**
```
User (users) — 12 columns
─────────────────────────
  id            integer     NOT NULL
  email         string      NOT NULL  default: ""
  name          string
  created_at    datetime    NOT NULL
  updated_at    datetime    NOT NULL

Associations:
  has_many :posts
  has_many :comments, through: :posts
  belongs_to :organization

Validations:
  validates :email, presence: true, uniqueness: true
  validates :name, length: { maximum: 100 }
```

**Primary data:** introspect.rb gives us columns (from `connection.columns`), associations (from `reflect_on_all_associations`), and validations (from `Model.validators`) — all as structured JSON. This catches meta-programmed associations that static file analysis would miss.

**Fallback (no Rails boot):** Parse `db/schema.rb` for columns (regex on `create_table` blocks + `t.type` calls). Parse model files for associations/validations (regex on `has_many`, `belongs_to`, `validates` lines). Less complete but still useful.

**Keybindings:**
| Key | Action |
|-----|--------|
| `Enter` | Show schema + associations + validations |
| `g` | Generate model (TextInput prompt) |
| `/` | Filter models |

**Edge cases:**
- **No `db/schema.rb`** → check for `db/structure.sql`; if using SQL format, show raw SQL for the table instead of parsed columns
- **No models** → "No models found in app/models/"
- **Namespaced models** (e.g., `Admin::User` in `app/models/admin/user.rb`) → display with namespace
- **Abstract models** (e.g., `ApplicationRecord`) → show but mark as abstract, no table
- **STI models** → share a table; show which table they inherit from
- **Models without a table** (POROs in `app/models/`) → show file but note "no database table"

### 6. Tests
**Data source:** Glob test files from `test/` or `spec/`.

Displays:
- Test files organized by directory
- Last run status per file if available (pass/fail/not run)

**Detail view:** Test run output for selected file, streamed live.

**Keybindings:**
| Key | Action |
|-----|--------|
| `Enter` | Run selected test file |
| `a` | Run all tests |
| `f` | Run failed tests only (Minitest: `bin/rails test --fail-fast`, RSpec: `--only-failures`) |
| `/` | Filter test files |

**Test runner detection:** Check for `spec/` → RSpec (`bundle exec rspec FILE`), `test/` → Minitest (`bin/rails test FILE`).

**Subprocess:** Stream output line-by-line into a Viewport. Parse summary line for pass/fail/error counts.

**Edge cases:**
- **No test directory** → "No tests found"
- **Both `test/` and `spec/` exist** → show both, detect runner per directory
- **Test requires database** → may fail if DB not set up; show error with suggestion to run `db:test:prepare`
- **Very long test suites** → stream output, show progress, allow Ctrl+C to cancel

### 7. Gems
**Data source:** `Bundler::LockfileParser` (built into Ruby, no Rails needed) + `Gemfile` (for groups).

Each gem: `GemEntry = Data.define(:name, :version, :groups)`

Displays:
- `gem_name (version)`
- Grouped by Gemfile group (default, development, test, production)

**Detail view:** Output from `bundle info GEM` — version, summary, homepage, path, dependencies.

**Keybindings:**
| Key | Action |
|-----|--------|
| `Enter` | Show gem info |
| `u` | `bundle update GEM` (confirmation: yellow) |
| `U` | `bundle update` all (confirmation: yellow) |
| `o` | Open gem homepage in browser |
| `/` | Filter gems |

**Edge cases:**
- **No `Gemfile.lock`** → "Run `bundle install` first"
- **`bundle info` fails** → fall back to just name + version from lockfile
- **Gems with native extensions** → no special handling needed, just display info

---

## Command Log

Inspired by lazygit's most popular feature. Every `bin/rails` / `bundle` command we execute is logged.

```
CommandEntry = Data.define(:command, :exit_code, :duration_ms, :timestamp)
```

**Display (toggled with `L`):**
```
┌─ Command Log ────────────────────────────────────────────┐
│ ✓ bin/rails about                              0.8s      │
│ ✓ bin/rails routes                             3.2s      │
│ ✓ bin/rails db:migrate:status                  1.1s      │
│ ✗ bin/rails db:migrate                         0.4s  [1] │
│ ✓ bin/rails generate migration AddAge          0.3s      │
└──────────────────────────────────────────────────────────┘
```

- Green checkmark for exit 0, red X for non-zero
- Duration in seconds
- `Enter` on a log entry shows full stdout/stderr in detail view
- Ring buffer, last 100 commands

**Value:** Users learn the CLI commands. Debugging: if something fails, they see the exact command and can re-run it manually.

---

## Destructive Operation Safety

### Confirmation Tiers

**RED — Double confirm (type panel name to proceed):**
- `db:drop` — destroys entire database
- `db:reset` — drops + recreates + seeds
- `db:seed:replant` — truncates ALL tables then seeds

**YELLOW — Single confirm (y/n):**
- `db:rollback` — undoes last migration (may lose data)
- `db:migrate:down VERSION=X` — undoes specific migration
- `rails destroy MODEL` — deletes generated files
- `bundle update` (all) — may change many versions

**GREEN — No confirm:**
- `db:migrate` — runs pending migrations (forward-only)
- `db:create` — creates database (non-destructive)
- `db:seed` — runs seeds (additive)
- `db:schema:dump` — writes file only
- `rails generate` — creates files only
- `bundle update GEM` — single gem update

### Undo Support

Keep a history of reversible commands:
- `rails generate X` → undo: `rails destroy X`
- `db:migrate` → undo: `db:rollback`
- `db:migrate:up VERSION=X` → undo: `db:migrate:down VERSION=X`

Show "Undo last action" (`z`) when the previous command has a known reverse. Gray out when not reversible.

---

## Rails Console Introspection (without a REPL)

Rather than embedding a full REPL, we surface the high-value read-only data that developers typically open `rails console` to check. All of this comes from `introspect.rb` (one `rails runner` call).

### What introspect.rb surfaces

```ruby
# Model introspection (Models panel detail view)
Model.columns_hash              # name, type, null, default, limit — via connection.columns
Model.reflect_on_all_associations  # has_many, belongs_to, etc. with class names
Model.validators                # presence, uniqueness, length, etc. with options

# Schema introspection (Models panel + Status panel)
connection.tables               # all table names
connection.columns(table)       # full column metadata per table
connection.indexes(table)       # indexes with uniqueness
connection.foreign_keys(table)  # FK constraints

# Route introspection (Routes panel)
Rails.application.routes.routes  # all routes with verb, path, action, name, engine

# Connection info (Status panel)
connection.adapter_name          # "PostgreSQL", "SQLite", "Mysql2"
connection.current_database      # database name

# Migration status (Database panel)
ActiveRecord::SchemaMigration.all_versions  # applied version numbers
ActiveRecord::MigrationContext.migrations   # all migration files with version, name, filename
```

### Fallbacks when Rails can't boot

- `Bundler::LockfileParser` → Gems panel (plain Ruby, no Rails)
- Parse `db/schema.rb` → column names/types (regex on `create_table` blocks)
- Parse model files → associations/validations (regex on `has_many`, `validates`, etc.)
- Glob test files → Tests panel (file list only, can't run)
- `ruby -v` → Ruby version

### What stays out of scope (v0.1)

- Arbitrary queries (`User.where(...)`) — needs a REPL
- Route testing (`app.get "/users"`) — needs a REPL
- `reload!` workflow — needs a persistent console session
- Sandbox mode — needs a REPL

---

## Additional Data Sources

### `rails stats` (shown in Status detail view)

```
+----------------------+-------+-------+---------+---------+-----+-------+
| Name                 | Lines |   LOC | Classes | Methods | M/C | LOC/M |
+----------------------+-------+-------+---------+---------+-----+-------+
| Controllers          |   510 |   387 |       8 |      47 |   5 |     6 |
| Models               |   320 |   248 |      12 |      28 |   2 |     6 |
| ...                  |       |       |         |         |     |       |
+----------------------+-------+-------+---------+---------+-----+-------+
| Total                |  1548 |  1202 |      48 |      96 |   2 |    10 |
+----------------------+-------+-------+---------+---------+-----+-------+
  Code LOC: 811     Test LOC: 391     Code to Test Ratio: 1:0.5
```

Parsed into a table struct. Displayed in Status panel detail view alongside `rails about`.

### `rails notes` (shown in Status detail view or as a filterable sub-view)

```
app/controllers/posts_controller.rb:
  * [ 12] [TODO] Add pagination support
  * [ 45] [FIXME] N+1 query here

app/models/user.rb:
  * [  3] [OPTIMIZE] Cache this computation
```

Parsed into `Note = Data.define(:file, :line, :tag, :message)`. Grouped by file in the detail view. Filterable by tag (TODO/FIXME/OPTIMIZE).

### `rails middleware` (shown in Status detail view)

List of Rack middleware in execution order. Useful for debugging but low priority — just display as a scrollable list.

### `rails initializers` (shown in Status detail view)

List of initializers in execution order. Same treatment as middleware.

---

## Edge Cases — Project Detection & Boot

### Project Detection (in order)

1. Check for `bin/rails` — standard Rails 5+ project
2. Check for `script/rails` — Rails 3-4 project (show warning: "Old Rails project, some features may not work")
3. Check for `Gemfile` with `gem "rails"` — Rails project without binstubs (suggest `bin/setup`)
4. None found → "Not a Rails project: #{dir}", exit 1

### Rails Boot Failure

Every panel data source goes through CommandRunner. If Rails can't boot, commands fail with stderr output. Handle gracefully:

```
┌─ Status ──────────┐┌─ Error ─────────────────────────────┐
│ ⚠ Rails can't boot││                                     │
│ Ruby 3.3.0        ││  Bundler::GemNotFound:               │
│ See detail →      ││  Could not find gem 'pg' in locally  │
│                   ││  installed gems.                     │
│                   ││                                     │
│                   ││  Run `bundle install` to install     │
│                   ││  missing gems.                      │
│                   ││                                     │
│                   ││  Full error:                        │
│                   ││  ...                                │
└───────────────────┘└─────────────────────────────────────┘
```

**What still works when Rails can't boot:**
- Parse `Gemfile.lock` → Gems panel
- Parse `db/schema.rb` → partial Models panel (columns only, no associations via runner)
- Glob test files → Tests panel (list only, can't run)
- `ruby -v` → Ruby version
- Read `Gemfile.lock` for Rails version

**Common boot failure modes:**
| Error | Message Pattern | Suggestion |
|-------|----------------|------------|
| Missing gems | `Bundler::GemNotFound` | "Run `bundle install`" |
| Syntax error | `SyntaxError:` | Show file + line number |
| Missing DB config | `ActiveRecord::AdapterNotSpecified` | "Check config/database.yml" |
| Wrong Ruby | `Gemfile requires Ruby X but running Y` | Show both versions |
| Missing file | `LoadError: cannot load such file` | Show the missing require |

### Spring Preloader

- Detect Spring via `bin/rails` content or `spring` in Gemfile
- Strip `Running via Spring preloader in process XXXX` from stdout
- Set `DISABLE_SPRING=1` in subprocess env for predictable output (Spring was removed as default in Rails 7.1+)

### Encoding

Force `UTF-8` on all captured subprocess output:
```ruby
stdout.force_encoding("UTF-8").encode("UTF-8", invalid: :replace, undef: :replace)
```

### Multi-Database Apps (Rails 6+)

- `database.yml` defines multiple databases (e.g., `primary`, `animals`)
- `db:migrate:status` output has per-database sections
- Migrations live in separate directories (`db/migrate/`, `db/animals_migrate/`)
- Database panel groups migrations by database
- `db:migrate` runs all databases; per-database: `db:migrate:animals`
- Schema files: `db/schema.rb` (primary), `db/animals_schema.rb` (others)

---

## Global Keybindings

| Key | Action |
|-----|--------|
| `Tab` / `Shift+Tab` | Cycle focused panel |
| `1`-`7` | Jump to panel by number |
| `j` / `k` or `Down` / `Up` | Scroll within panel |
| `Enter` | Drill into detail / expand |
| `q` | Quit (stop server if running, confirm) |
| `?` | Toggle help overlay |
| `R` | Refresh current panel data |
| `/` | Filter current panel (where supported) |
| `L` | Toggle command log overlay |
| `z` | Undo last reversible action |

---

## Data Layer

### CommandRunner

Thin wrapper around subprocess execution. Every command goes through here for logging and testability.

```ruby
module LazyRails
  class CommandRunner
    Result = Data.define(:stdout, :stderr, :success, :duration_ms)

    # Synchronous — run command, return Result
    def self.run(cmd, dir:, env: {})
      env = env.merge("DISABLE_SPRING" => "1")
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      stdout, stderr, status = Open3.capture3(env, cmd, chdir: dir)
      duration = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round
      stdout = force_utf8(stdout)
      stderr = force_utf8(stderr)
      Result.new(stdout:, stderr:, success: status.success?, duration_ms: duration)
    end

    # Async — run command, yield lines to block
    def self.stream(cmd, dir:, env: {}, &block)
      env = env.merge("DISABLE_SPRING" => "1")
      Open3.popen2e(env, cmd, chdir: dir) do |_stdin, output, wait_thr|
        output.each_line { |line| block.call(force_utf8(line)) }
        wait_thr.value
      end
    end

    def self.force_utf8(str)
      str.force_encoding("UTF-8").encode("UTF-8", invalid: :replace, undef: :replace)
    end
  end
end
```

All Rails commands go through CommandRunner → trivial to stub in tests.

### Introspect (primary data source)

One `rails runner` call, one JSON blob, all structured data:

```ruby
LazyRails::Introspect.load(json_string)  # → IntrospectData with routes, tables, migrations, models, connection
```

`IntrospectData` is a plain struct that holds arrays of `Route`, `Migration`, `ModelInfo`, etc. — all built from the JSON hash via `Data.define` constructors.

### Parsers (fallbacks + text commands)

Pure functions for when Rails can't boot or for text-based commands:

```ruby
# Fallback parsers (used when introspect.rb fails)
LazyRails::Parsers::Schema.parse(schema_rb_content)  # → {table_name => [Column, ...]}
LazyRails::Parsers::ModelFile.parse(file_content)     # → {associations: [...], validations: [...]}

# Always text-based (no structured API available)
LazyRails::Parsers::RailsAbout.parse(raw_output)     # → Hash
LazyRails::Parsers::RailsStats.parse(raw_output)     # → [StatRow, ...]
LazyRails::Parsers::RailsNotes.parse(raw_output)     # → [Note, ...]
LazyRails::Parsers::TestOutput.parse(raw_output)      # → TestResult

# Plain Ruby (no Rails needed)
LazyRails::Parsers::GemfileLock.parse(lockfile_path)  # → [GemEntry, ...] (via Bundler::LockfileParser)
```

### Data Structs

```ruby
Route       = Data.define(:verb, :path, :action, :name, :engine)
Migration   = Data.define(:status, :version, :name, :file_path, :database)
Column      = Data.define(:name, :type, :null, :default, :limit)
ModelInfo   = Data.define(:name, :file_path, :table_name, :columns, :associations, :validations)
GemEntry    = Data.define(:name, :version, :groups)
TestResult  = Data.define(:file, :passed, :failed, :errors, :output)
StatRow     = Data.define(:name, :lines, :loc, :classes, :methods)
Note        = Data.define(:file, :line, :tag, :message)
CommandEntry = Data.define(:command, :exit_code, :duration_ms, :timestamp, :stdout, :stderr)
```

---

## UI Components (from Petals)

| Component | Usage |
|-----------|-------|
| `Petals::Viewport` | Detail pane, server log, test output, command log |
| `Petals::TextInput` | Filter input, port input, migration name, model name |
| `Petals::Spinner` | Loading indicators (routes loading, command running) |
| `Petals::Help` | `?` help overlay with all keybindings |
| `Petals::Table` | Routes display, gems display, stats display |
| `Petals::List` | Model list, test file list (with fuzzy filter) |
| `Petals::KeyBinding` | All keybinding matching |

## Styling (from Flourish)

- Panel borders: `Flourish::Border::ROUNDED`
- Focused panel: `#7d56f4`, unfocused: `#444444`
- Layout: `Flourish.join_horizontal` / `Flourish.join_vertical`
- Status bar: dim foreground
- Verb colors: GET=`#04b575`, POST=`#5b9bd5`, PUT/PATCH=`#e5c07b`, DELETE=`#ff6347`
- Migration status: up=`#04b575`, down=`#ff6347`
- Command log: success=`#04b575`, failure=`#ff6347`
- Panel titles injected into top border (same technique as `layout_demo_interactive.rb`)

---

## Startup Sequence

1. Detect Rails project (check `bin/rails`, `script/rails`, `Gemfile`)
2. Render frame immediately with spinners in all panels
3. Run data loads in parallel (separate threads):
   - **Thread 1:** `bin/rails runner introspect.rb` → Routes, Database, Models, Connection (one JSON blob)
   - **Thread 2:** `bin/rails about` + `bin/rails stats` + `bin/rails notes` → Status panel
   - **Thread 3 (instant, no Rails):** `Bundler::LockfileParser` on `Gemfile.lock` → Gems panel
   - **Thread 4 (instant, no Rails):** Glob `test/` or `spec/` → Tests panel
4. Thread 3+4 complete instantly → Gems and Tests panels render first
5. Thread 1 completes (~2-5s) → Routes, Database, Models panels all populate at once
6. Thread 2 completes → Status panel gets full data
7. Target: render shell in <0.5s, instant panels in <0.1s, full data in <5s

If introspect.rb fails (Rails can't boot), activate fallback parsers for what we can show (Gems, partial Models from schema.rb, test file list). Other panels show the error.

---

## Testing Strategy

### Unit Tests (~80% of coverage)
- **Parsers** — Pure input/output with fixture strings. Test every format variant, edge case, and empty state.
- **Data structs** — `Data.define` equality, serialization.
- **CommandRunner** — Stub `Open3`, verify command construction, env vars, encoding, error handling.

### Component Tests
- **Panel rendering** — Given panel state (items, cursor, focused), assert view output.
- **Keybinding routing** — Send KeyMsg, verify model state changes.
- **Confirmation dialogs** — Verify destructive ops require confirmation, green ops don't.
- **Command log** — Verify entries are recorded with correct data.

### Integration Tests
- **App lifecycle** — Initialize → update with messages → verify view output.
- **Error states** — Simulate boot failure, missing DB, no routes.
- **Async loading** — Verify spinner → data transition.

### Fixture Data (`spec/fixtures/`)
```
# Primary data source (JSON from introspect.rb)
introspect.json               — full introspect output (routes, tables, migrations, models, connection)
introspect_no_db.json         — introspect output when database doesn't exist
introspect_empty.json         — introspect output for a fresh Rails app (no models, no migrations)
introspect_multidb.json       — introspect output for multi-database app
introspect_boot_fail.txt      — stderr when Rails can't boot

# Text command outputs (still need text parsing)
rails_about.txt               — standard `rails about` output
rails_stats.txt               — standard `rails stats` output
rails_notes.txt               — standard `rails notes` output
rails_notes_empty.txt         — no annotations (empty string)
test_output_minitest.txt      — minitest run output
test_output_rspec.txt         — rspec run output

# Fallback parsers (when Rails can't boot)
schema.rb                     — sample db/schema.rb file
structure.sql                 — sample db/structure.sql
Gemfile.lock                  — sample lockfile
model_user.rb                 — sample model with associations + validations
model_post.rb                 — sample model with STI
```

No Rails subprocess needed for tests. Fast and deterministic.

---

## File Structure

```
lazyrails/
  lib/
    lazyrails.rb
    lazyrails/
      version.rb
      app.rb                  # Main Chamomile model
      panel.rb                # Panel data struct
      command_runner.rb        # Subprocess wrapper + logging
      command_log.rb           # Ring buffer of CommandEntry
      server_manager.rb        # Rails server lifecycle
      project.rb              # Rails project detection + info
      confirmation.rb          # Destructive operation confirmation UI
      introspect.rb            # Rails runner script (dumps JSON) + loader
      parsers/
        schema.rb              # Fallback: parse db/schema.rb when Rails can't boot
        model_file.rb          # Fallback: regex associations/validations from model files
        gemfile_lock.rb        # Bundler::LockfileParser wrapper (no Rails needed)
        rails_about.rb         # Text parser for `rails about` output
        rails_stats.rb         # Text parser for `rails stats` output
        rails_notes.rb         # Text parser for `rails notes` output
        test_output.rb         # Text parser for test runner output
      views/
        status_view.rb
        server_view.rb
        routes_view.rb
        database_view.rb
        models_view.rb
        tests_view.rb
        gems_view.rb
        detail_view.rb
        command_log_view.rb
        help_view.rb
        error_view.rb
  spec/
    spec_helper.rb
    fixtures/
      (all fixture files listed above)
    lazyrails/
      app_spec.rb
      introspect_spec.rb       # JSON loading + struct construction
      command_runner_spec.rb
      command_log_spec.rb
      server_manager_spec.rb
      project_spec.rb
      confirmation_spec.rb
      parsers/
        schema_spec.rb          # Fallback schema.rb parser
        model_file_spec.rb      # Fallback model file parser
        gemfile_lock_spec.rb
        rails_about_spec.rb
        rails_stats_spec.rb
        rails_notes_spec.rb
        test_output_spec.rb
      views/
        status_view_spec.rb
        server_view_spec.rb
        routes_view_spec.rb
        database_view_spec.rb
        models_view_spec.rb
        tests_view_spec.rb
        gems_view_spec.rb
  bin/
    lazyrails                  # CLI entry point
  lazyrails.gemspec
  Gemfile
  README.md
  CHANGELOG.md
  LICENSE
  .rubocop.yml
  .gitignore
```

---

## CLI Entry Point

```ruby
#!/usr/bin/env ruby
require "lazyrails"

dir = ARGV[0] || Dir.pwd

project = LazyRails::Project.detect(dir)
if project.nil?
  warn "Not a Rails project: #{dir}"
  warn "Expected to find bin/rails or a Gemfile with 'rails'"
  exit 1
end

if project.old_rails?
  warn "Warning: Detected Rails #{project.rails_version} — some features may not work"
end

app = LazyRails::App.new(project)
Chamomile.run(app, alt_screen: true)
```

Usage:
```sh
lazyrails              # current directory
lazyrails ~/myapp      # specific project
```

---

## Future Considerations (not in v0.1)

- **Rails console integration** — Embedded REPL panel for arbitrary queries
- **Generator wizard** — Guided `rails generate` with field type selection
- **Rake tasks panel** — Discover and run custom rake tasks from `lib/tasks/`
- **Credentials viewer** — `rails credentials:show` in a secure detail view
- **Active Job monitor** — Queue depth, failed jobs, retry
- **Custom commands** — User-defined commands in `.lazyrails.yml`
- **Action Cable** — WebSocket connection status

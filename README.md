# LazyRails

A [lazygit](https://github.com/jesseduffield/lazygit)-style terminal UI for the Rails command line. Navigate routes, migrations, models, tests, server logs, and gems in a single split-pane interface — no flags to memorize.

Built on the [Chamomile](https://github.com/emo/chamomile) ecosystem (chamomile + petals + flourish).

## Install

```
gem install lazyrails
```

Or add to your Gemfile:

```ruby
gem "lazyrails", group: :development
```

Requires Ruby >= 3.2.

## Usage

```
cd your-rails-app
lazyrails
```

Or point it at a directory:

```
lazyrails /path/to/rails/app
```

## Panels

| # | Panel    | What it shows                              |
|---|----------|--------------------------------------------|
| 1 | Status   | Rails/Ruby version, env, app name, branch  |
| 2 | Server   | Start/stop/restart the dev server           |
| 3 | Routes   | All routes with verb, path, and action      |
| 4 | Database | Migrations with up/down status              |
| 5 | Models   | Models with columns, associations, validations |
| 6 | Tests    | Test files with pass/fail status            |
| 7 | Gems     | All gems from Gemfile.lock                  |

## Keybindings

### Navigation

| Key              | Action             |
|------------------|--------------------|
| `Tab` / `Shift+Tab` | Cycle panels    |
| `1`-`7`          | Jump to panel      |
| `j` / `k`        | Scroll up/down     |
| `Enter`          | Select / expand    |
| `/`              | Filter (routes, models, tests, gems) |
| `R`              | Refresh panel      |
| `L`              | Toggle command log |
| `z`              | Undo last action   |
| `?`              | Toggle help        |
| `q`              | Quit               |

### Server

| Key | Action          |
|-----|-----------------|
| `s` | Start server    |
| `S` | Stop server     |
| `r` | Restart server  |
| `p` | Change port     |

### Database

| Key | Action              |
|-----|---------------------|
| `m` | Run db:migrate      |
| `M` | Run db:rollback     |
| `c` | Create migration    |
| `d` | Migrate down version|
| `u` | Migrate up version  |

### Tests

| Key     | Action            |
|---------|-------------------|
| `Enter` | Run selected test |
| `a`     | Run all tests     |
| `f`     | Run failed only   |

### Gems

| Key | Action         |
|-----|----------------|
| `u` | Update gem     |
| `U` | Update all     |
| `o` | Open homepage  |

## How it works

LazyRails uses `rails runner` to introspect your app through Rails' internal APIs (routes, migrations, models, associations, validations) and gets structured JSON back. This is more reliable than parsing CLI text output.

When Rails can't boot, it falls back to parsing `db/schema.rb` and model files directly.

Every command LazyRails runs is logged transparently in the command log (`L`), so you learn the Rails CLI as you use the TUI.

### Safety

Destructive commands have confirmation tiers:

- **Red** (e.g. `db:drop`, `db:reset`) — type the panel name to confirm
- **Yellow** (e.g. `db:rollback`, `bundle update`) — y/n confirmation
- **Green** (e.g. `db:migrate`, `bundle update gem_name`) — runs immediately

## Development

```
git clone https://github.com/emo/lazyrails
cd lazyrails
bundle install
bundle exec ruby bin/lazyrails /path/to/rails/app
```

## License

MIT

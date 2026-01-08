<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->

# AGENTS.md

## Project Identity

Project Name: ratatui_ruby-tea

Description: Part of the RatatuiRuby ecosystem.

## 1. Standards

### STRICT REQUIREMENTS

- Every file MUST begin with an SPDX-compliant header. Use `LGPL-3.0-or-later` for code; `CC-BY-SA-4.0` for documentation. `reuse annotate` can help you generate the header. **For Ruby files**, wrap SPDX comments in `#--` / `#++` to hide them from RDoc output.
- Every line of Ruby MUST be covered by tests that would stand up to mutation testing.
  - Tests must be meaningful and verify specific behavior or rendering output; simply verifying that code "doesn't crash" is insufficient and unacceptable.
- **Pre-commit:** Use `agent_rake` to ensure commit-readiness. See Tools for detailed instructions.
- **Git Pager:** ALWAYS set `PAGER=cat` for ALL `git` commands (e.g., `PAGER=cat git diff`). This is mandatory.

### Tools

- **NEVER** run `bundle exec rake` directly. **NEVER** run `bundle exec ruby -Ilib:test ...` directly.
- **ALWAYS use `agent_rake`** (provided by the `ratatui_ruby-devtools` gem) for running tests, linting, or checking compilation.
  - **Usage:**
    - Runs default task (compile + test + lint): `agent_rake`
    - Runs specific task: `agent_rake test:ruby` (for example)
- **Setup:** `bin/setup` must handle Bundler dependencies.
- **Git:** ALWAYS set `PAGER=cat` with `git`. **THIS IS CRITICAL!**

### Ruby Standards

- Use `Data.define` for all value objects (Ruby 3.2+).
- Define types in `.rbs` files. Don't use `untyped` just because it's easy; be comprehensive and accurate.
- Every public Ruby class/method must be documented for humans in RDoc.

## 2. Committing

- Who commits: DON'T stage (DON'T `git add`) unless explicitly instructed. DON'T commit unless explicitly instructed. DO suggest a commit message when you finish.
- **Format:**
    - Format: Use [Conventional Commits](https://www.conventionalcommits.org/).
    - Body: Explanation if necessary (wrap at 72 chars).
        - **DON'T list the files changed or the edits made in the body.**
        - **DON'T use markdown syntax** (no backticks, no bolding, no lists, no links).

## 3. Definition of Done (DoD)

Before considering a task complete:

1. **Default Rake Task Passes:** Run `agent_rake` (no args). Confirm it passes with ZERO errors.
2. **Documentation Updated:** If public APIs changed, update relevant docs.
3. **Changelog Updated:** If public APIs changed, update CHANGELOG.md's **Unreleased** section.
4. **Commit Message Suggested:** Include a suggested commit message block.

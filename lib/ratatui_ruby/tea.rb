# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: LGPL-3.0-or-later
#++

require_relative "tea/version"
require_relative "tea/command"
require_relative "tea/runtime"

module RatatuiRuby # :nodoc: Documented in the ratatui_ruby gem.
  # The Elm Architecture for RatatuiRuby.
  #
  # Building TUI applications means managing state, events, and rendering. Mixing them leads to
  # spaghetti code. Bugs hide in the tangles.
  #
  # This module implements The Elm Architecture (TEA). It separates your application into three
  # pure functions: model, view, and update. The runtime handles the rest.
  #
  # Use it to build applications with predictable, testable state management.
  module Tea
    # Starts the MVU event loop.
    #
    # Convenience delegator to Runtime.run. See Runtime for full documentation.
    def self.run(...)
      Runtime.run(...)
    end

    # Wraps a command with a routing prefix.
    #
    # Parents trigger child commands. The results need routing back
    # to the correct child. Manually wrapping every command is tedious.
    #
    # This method prefixes command results automatically. Use it to route
    # child command results in Fractal Architecture.
    #
    # [command] The child command to wrap.
    # [prefix] Symbol prepended to results (e.g., <tt>:stats</tt>).
    #
    # === Example
    #
    #   # Verbose:
    #   Command.map(widget.fetch_command) { |r| [:stats, *r] }
    #
    #   # Concise:
    #   Tea.route(widget.fetch_command, :stats)
    def self.route(command, prefix)
      Command.map(command) { |result| [prefix, *result] }
    end

    # Delegates a prefixed message to a child UPDATE.
    #
    # Parent UPDATE functions route messages to children. Each route requires
    # pattern matching, calling the child, and rewrapping any returned command.
    # The boilerplate adds up fast.
    #
    # This method handles the dispatch. It checks the prefix, calls the child,
    # and wraps any command. Returns <tt>nil</tt> if the prefix does not match.
    #
    # [message] Incoming message (e.g., <tt>[:stats, :system_info, {...}]</tt>).
    # [prefix] Expected prefix symbol (e.g., <tt>:stats</tt>).
    # [child_update] The child's UPDATE callable.
    # [child_model] The child's current model.
    #
    # === Example
    #
    #   # Verbose:
    #   case message
    #   in [:stats, *rest]
    #     new_child, cmd = StatsPanel::UPDATE.call(rest, model.stats)
    #     mapped = cmd ? Command.map(cmd) { |r| [:stats, *r] } : nil
    #     [new_child, mapped]
    #   end
    #
    #   # Concise:
    #   Tea.delegate(message, :stats, StatsPanel::UPDATE, model.stats)
    def self.delegate(message, prefix, child_update, child_model)
      return nil unless message.is_a?(Array) && message.first == prefix

      rest = message[1..]
      new_child, command = child_update.call(rest, child_model)
      wrapped = command ? route(command, prefix) : nil
      [new_child, wrapped]
    end
  end
end

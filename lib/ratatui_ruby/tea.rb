# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: LGPL-3.0-or-later
#++

require_relative "tea/version"
require_relative "tea/cmd"
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
  end
end

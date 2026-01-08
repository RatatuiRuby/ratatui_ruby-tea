# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: LGPL-3.0-or-later
#++

require "ratatui_ruby"

module RatatuiRuby
  module Tea
    # Runs the Model-View-Update event loop.
    #
    # Applications need a render loop. You poll events, update state, redraw. Every frame.
    # The boilerplate is tedious and error-prone.
    #
    # This class handles the loop. You provide the model, view, and update. It handles the rest.
    #
    # Use it to build applications with predictable state.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-FileCopyrightText: 2026 Kerrick Long
    # SPDX-License-Identifier: MIT-0
    #++
    #   RatatuiRuby::Tea.run(
    #     model: { count: 0 }.freeze,
    #     view: ->(m, tui) { tui.paragraph(text: m[:count].to_s) },
    #     update: ->(msg, m) { msg.q? ? [m, Cmd.quit] : [m, nil] }
    #   )
    #--
    # SPDX-SnippetEnd
    #++
    class Runtime
      # Starts the MVU event loop.
      #
      # Runs until the update function returns a <tt>Cmd.quit</tt> command.
      #
      # [model] Initial application state (immutable).
      # [view] Callable receiving <tt>(model, tui)</tt>, returns a widget.
      # [update] Callable receiving <tt>(msg, model)</tt>, returns <tt>[new_model, cmd]</tt>.
      def self.run(model:, view:, update:)
        RatatuiRuby.run do |tui|
          loop do
            tui.draw { |frame| frame.render_widget(view.call(model, tui), frame.area) }
            msg = tui.poll_event
            model, cmd = update.call(msg, model)
            break if cmd.is_a?(Cmd::Quit)
          end
        end
      end
    end
  end
end

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
      # [update] Callable receiving <tt>(msg, model)</tt>, returns <tt>[new_model, cmd]</tt> or just <tt>new_model</tt>.
      def self.run(model:, view:, update:)
        RatatuiRuby.run do |tui|
          loop do
            tui.draw { |frame| frame.render_widget(view.call(model, tui), frame.area) }
            msg = tui.poll_event
            result = update.call(msg, model)
            model, cmd = normalize_update_result(result)
            break if cmd.is_a?(Cmd::Quit)
          end
        end
      end

      # Detects whether +result+ is a +[model, cmd]+ tuple or a plain model.
      #
      # Returns +[model, cmd]+ in either case.
      def self.normalize_update_result(result)
        return result if result.is_a?(Array) && result.size == 2 && valid_cmd?(result[1])

        [result, nil]
      end
      private_class_method :normalize_update_result

      # Returns +true+ if +value+ is a valid command (+nil+ or a +Cmd+ type).
      def self.valid_cmd?(value)
        value.nil? || value.class.name&.start_with?("RatatuiRuby::Tea::Cmd::")
      end
      private_class_method :valid_cmd?
    end
  end
end

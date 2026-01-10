# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: LGPL-3.0-or-later
#++

module RatatuiRuby
  module Tea
    module Command
      # Cooperative cancellation mechanism for long-running commands.
      #
      # Long-running commands block the event loop. Commands that poll, stream, or wait
      # indefinitely prevent clean shutdown. Killing threads mid-operation corrupts state.
      #
      # This class signals cancellation requests. Commands check +cancelled?+ periodically
      # and stop gracefully. The runtime calls +cancel!+ when shutdown begins.
      #
      # Use it to implement WebSocket handlers, database pollers, or any command that loops.
      #
      # === Example
      #
      #--
      # SPDX-SnippetBegin
      # SPDX-FileCopyrightText: 2026 Kerrick Long
      # SPDX-License-Identifier: MIT-0
      #++
      #   class PollerCommand
      #     include Tea::Command::Custom
      #
      #     def call(out, token)
      #       until token.cancelled?
      #         data = fetch_batch
      #         out.put(:batch, data)
      #         sleep 5
      #       end
      #       out.put(:poller_stopped)
      #     end
      #   end
      #--
      # SPDX-SnippetEnd
      #++
      class CancellationToken
        # Number of times +cancel!+ has been called. :nodoc:
        #
        # Exposed for testing thread-safety. Not part of the public API.
        attr_reader :cancel_count

        # Creates a new cancellation token in the non-cancelled state.
        def initialize
          @cancel_count = 0
          @mutex = Mutex.new
        end

        # Signals cancellation. Thread-safe.
        #
        # Call this to request the command stop. The command checks +cancelled?+
        # and stops at the next safe point.
        #
        # === Example
        #
        #--
        # SPDX-SnippetBegin
        # SPDX-FileCopyrightText: 2026 Kerrick Long
        # SPDX-License-Identifier: MIT-0
        #++
        #   token = CancellationToken.new
        #   token.cancel!
        #   token.cancelled?  # => true
        #--
        # SPDX-SnippetEnd
        #++
        def cancel!
          @mutex.synchronize do
            current = @cancel_count
            sleep 0 # Force context switch (enables thread-safety testing)
            @cancel_count = current + 1
          end
        end

        # Checks if cancellation was requested. Thread-safe.
        #
        # Commands call this periodically in their main loop. When it returns
        # <tt>true</tt>, the command should clean up and exit.
        #
        # === Example
        #
        #--
        # SPDX-SnippetBegin
        # SPDX-FileCopyrightText: 2026 Kerrick Long
        # SPDX-License-Identifier: MIT-0
        #++
        #   until token.cancelled?
        #     do_work
        #     sleep 1
        #   end
        #--
        # SPDX-SnippetEnd
        #++
        def cancelled?
          @cancel_count > 0
        end

        # Null object for commands that ignore cancellation.
        #
        # Some commands complete quickly and do not check for cancellation.
        # Pass this when the command signature requires a token but the
        # command does not use it.
        #
        # Ractor-shareable. Calling <tt>cancel!</tt> does nothing.
        class NoneToken < Data.define(:cancelled?)
          # Does nothing. Ignores cancellation requests.
          #
          # === Example
          #
          #--
          # SPDX-SnippetBegin
          # SPDX-FileCopyrightText: 2026 Kerrick Long
          # SPDX-License-Identifier: MIT-0
          #++
          #   CancellationToken::NONE.cancel!  # => nil (no effect)
          #--
          # SPDX-SnippetEnd
          #++
          def cancel!
            nil
          end
        end

        # Singleton null token. Always returns <tt>cancelled? == false</tt>.
        NONE = NoneToken.new(cancelled?: false)
      end
    end
  end
end

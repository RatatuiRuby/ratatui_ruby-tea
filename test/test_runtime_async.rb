# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require "ratatui_ruby/test_helper"

class TestRuntimeAsync < Minitest::Test
  include RatatuiRuby::TestHelper

  def test_runtime_executes_commands_asynchronously
    model = Ractor.make_shareable({ events: [] })

    # Command that sleeps for 0.01s.
    long_running_cmd = RatatuiRuby::Tea::Cmd.exec("sleep 0.01", :cmd_complete)

    view = -> (_m, t) { t.clear }

    final_model = nil

    update = -> (msg, m) do
      # Map raw key events to symbols for clarity
      clean_msg = if msg.is_a?(RatatuiRuby::Event::Key)
        case msg.code
        when "s" then :start_cmd
        when "p" then :ping
        when "q" then :quit
        else msg
        end
      elsif msg.is_a?(Array) && msg[0] == :cmd_complete
        :cmd_complete
      else
        msg
      end

      new_events = (m[:events] + [clean_msg]).freeze

      puts "DEBUG: Processing msg: #{clean_msg}"
      case clean_msg
      when :start_cmd
        [m.merge(events: new_events).freeze, long_running_cmd]
      when :ping, :cmd_complete
        [m.merge(events: new_events).freeze, nil]
      when :quit
        final_model = m.merge(events: new_events).freeze
        [final_model, RatatuiRuby::Tea::Cmd.quit]
      else
        [m, nil]
      end
    end

    final_model = nil

    with_test_terminal do
      # Inject events:
      # 's': Starts the long running command
      # 'p': Should be processed immediately if non-blocking
      # 'q': Quits the loop
      inject_key("s")
      inject_key("p")
      inject_key("q")

      # Stub Open3.capture3 to simulate blocking work without shelling out
      require "open3"
      mock_status = Object.new
      mock_status.define_singleton_method(:exitstatus) { 0 }

      # Sleep for 0.05s to simulate work (blocking)
      blocking_simulation = -> (_cmd) { sleep(0.05); ["", "", mock_status] }

      Open3.stub(:capture3, blocking_simulation) do
        RatatuiRuby::Tea::Runtime.run(model:, view:, update:)
      rescue => e
        puts "CAUGHT ERROR: #{e.class}: #{e.message}"
        puts e.backtrace.join("\n")
        raise e
      end
    end

    events = final_model[:events]
    start_idx = events.index(:start_cmd)
    ping_idx = events.index(:ping)

    # Debug output
    puts "Events processed: #{events.inspect}"

    assert ping_idx > start_idx, "ping must happen after start_cmd"

    # If synchronous: events will be [:start_cmd, :cmd_complete, :ping, :quit]
    # Because 's' blocks, finishes (cmd_complete), then 'p' is polled.

    # If asynchronous: events will be [:start_cmd, :ping, :quit]
    # Because 's' starts thread, loop continues, 'p' is polled. 'q' is polled. Quit.
    # The 'cmd_complete' message arrives later but loop is closed.

    # So valid async execution order is NO :cmd_complete between start and ping.
    if events.include?(:cmd_complete)
      cmd_complete_idx = events.index(:cmd_complete)
      refute (cmd_complete_idx > start_idx && cmd_complete_idx < ping_idx),
        "FAIL: :cmd_complete happened between :start_cmd and :ping. Runtime is synchronous."
    end
  end
end

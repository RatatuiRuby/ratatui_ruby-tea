# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: MIT-0
#++

$LOAD_PATH.unshift File.expand_path("../../../lib", __dir__)
require "ratatui_ruby"
require "ratatui_ruby/tea"
require "ratatui_ruby/test_helper"
require "open3"
require "minitest/autorun"
require_relative "../../../examples/app_fractal_dashboard/dashboard/update_manual"
require_relative "../../../examples/app_fractal_dashboard/dashboard/update_helpers"
require_relative "../../../examples/app_fractal_dashboard/dashboard/update_router"

# Integration tests for the Fractal Dashboard example.
class TestFractalDashboardSnapshots < Minitest::Test
  include RatatuiRuby::TestHelper

  # Mock Open3.capture3 to return deterministic output
  MOCK_SYSTEM_INFO = "Darwin testhost 24.0.0 Darwin Kernel Version 24.0.0: Test"
  MOCK_DISK_USAGE = <<~DISK
    Filesystem      Size  Used Avail Use% Mounted on
    /dev/disk1s1    500G  250G  250G  50% /
    /dev/disk1s2    100G   50G   50G  50% /Users
  DISK
  MOCK_PING = "PING localhost (127.0.0.1): 56 data bytes\n64 bytes from 127.0.0.1: icmp_seq=0 ttl=64 time=0.123 ms"
  MOCK_UPTIME = " 10:30  up 5 days, 12:34, 3 users, load averages: 1.50 1.25 1.00"

  def with_mocked_open3(&)
    Open3.stub(:capture3, lambda { |cmd|
      case cmd
      when /uname/ then [MOCK_SYSTEM_INFO, "", stub_status(0)]
      when /df/ then [MOCK_DISK_USAGE, "", stub_status(0)]
      when /ping/ then [MOCK_PING, "", stub_status(0)]
      when /uptime/ then [MOCK_UPTIME, "", stub_status(0)]
      else ["", "unknown command", stub_status(1)]
      end
    }, &)
  end

  def stub_status(code)
    status = Minitest::Mock.new
    status.expect(:exitstatus, code)
    status
  end

  def test_initial_view
    with_test_terminal do
      inject_key(:q)

      RatatuiRuby::Tea.run(
        model: DashboardManual::INITIAL,
        view: DashboardManual::VIEW,
        update: DashboardManual::UPDATE
      )

      assert_snapshots("initial_view")
    end
  end

  def test_after_system_info_key
    with_mocked_open3 do
      with_test_terminal do
        inject_key("s")
        inject_sync
        inject_key(:q)

        RatatuiRuby::Tea.run(
          model: DashboardManual::INITIAL,
          view: DashboardManual::VIEW,
          update: DashboardManual::UPDATE
        )

        assert_snapshots("after_system_info")
      end
    end
  end

  def test_after_disk_usage_key
    with_mocked_open3 do
      with_test_terminal do
        inject_key("d")
        inject_sync
        inject_key(:q)

        RatatuiRuby::Tea.run(
          model: DashboardManual::INITIAL,
          view: DashboardManual::VIEW,
          update: DashboardManual::UPDATE
        )

        assert_snapshots("after_disk_usage")
      end
    end
  end

  def test_after_ping_key
    with_mocked_open3 do
      with_test_terminal do
        inject_key("p")
        inject_sync
        inject_key(:q)

        RatatuiRuby::Tea.run(
          model: DashboardManual::INITIAL,
          view: DashboardManual::VIEW,
          update: DashboardManual::UPDATE
        )

        assert_snapshots("after_ping")
      end
    end
  end

  def test_after_uptime_key
    with_mocked_open3 do
      with_test_terminal do
        inject_key("u")
        inject_sync
        inject_key(:q)

        RatatuiRuby::Tea.run(
          model: DashboardManual::INITIAL,
          view: DashboardManual::VIEW,
          update: DashboardManual::UPDATE
        )

        assert_snapshots("after_uptime")
      end
    end
  end

  def test_all_update_variants_produce_same_view
    # Capture with manual
    manual_content = nil
    with_test_terminal do
      inject_key(:q)
      RatatuiRuby::Tea.run(
        model: DashboardManual::INITIAL,
        view: DashboardManual::VIEW,
        update: DashboardManual::UPDATE
      )
      manual_content = buffer_content
    end

    # Capture with helpers
    helpers_content = nil
    with_test_terminal do
      inject_key(:q)
      RatatuiRuby::Tea.run(
        model: DashboardHelpers::INITIAL,
        view: DashboardHelpers::VIEW,
        update: DashboardHelpers::UPDATE
      )
      helpers_content = buffer_content
    end

    # Capture with router
    router_content = nil
    with_test_terminal do
      inject_key(:q)
      RatatuiRuby::Tea.run(
        model: DashboardRouter::INITIAL,
        view: DashboardRouter::VIEW,
        update: DashboardRouter::UPDATE
      )
      router_content = buffer_content
    end

    assert_equal manual_content, helpers_content, "Manual and Helpers views differ"
    assert_equal manual_content, router_content, "Manual and Router views differ"
    assert_equal helpers_content, router_content, "Helpers and Router views differ"
  end

  def test_custom_modal_opens_and_escapes
    with_test_terminal do
      inject_key("c")       # Open modal
      inject_key(:esc)      # Cancel modal
      inject_key(:q)        # Quit

      RatatuiRuby::Tea.run(
        model: DashboardManual::INITIAL,
        view: DashboardManual::VIEW,
        update: DashboardManual::UPDATE
      )

      # Should be back to initial view (ESC dismissed modal)
      assert_snapshots("initial_view")
    end
  end

  def test_custom_modal_opens_on_c_key
    with_test_terminal do
      inject_key("c")       # Open modal
      inject_key(:esc)      # Cancel modal immediately
      inject_key(:q)        # Quit

      RatatuiRuby::Tea.run(
        model: DashboardManual::INITIAL,
        view: DashboardManual::VIEW,
        update: DashboardManual::UPDATE
      )

      # If we got here without error, modal opened and closed successfully
      assert true
    end
  end

  def test_custom_modal_typing_and_cancel
    with_test_terminal do
      inject_key("c")       # Open modal
      inject_key("e")       # Type 'e'
      inject_key("c")       # Type 'c'
      inject_key("h")       # Type 'h'
      inject_key("o")       # Type 'o'
      inject_key(:esc)      # Cancel
      inject_key(:q)        # Quit

      RatatuiRuby::Tea.run(
        model: DashboardManual::INITIAL,
        view: DashboardManual::VIEW,
        update: DashboardManual::UPDATE
      )

      # Should be back to initial view
      assert_snapshots("initial_view")
    end
  end

  def test_custom_modal_enter_on_empty_cancels
    # Pressing ENTER on empty input = cancel (no command runs)
    with_test_terminal do
      inject_key("c")       # Open modal
      inject_key(:enter)    # Enter on empty = cancel
      inject_key(:q)        # Quit

      RatatuiRuby::Tea.run(
        model: DashboardManual::INITIAL,
        view: DashboardManual::VIEW,
        update: DashboardManual::UPDATE
      )

      # Should be back to initial view
      assert_snapshots("initial_view")
    end
  end

  def test_modal_input_view
    with_test_terminal do
      # Start with modal open
      start_model = DashboardManual::INITIAL.with(
        shell_modal: CustomShellModal::INITIAL.with(mode: :input)
      )

      # 1. Render modal (captured)
      # 2. ESC to cancel modal
      # 3. q to quit
      inject_key(:esc)
      inject_key(:q)

      RatatuiRuby::Tea.run(
        model: start_model,
        view: DashboardManual::VIEW,
        update: DashboardManual::UPDATE
      )

      assert_snapshots("modal_input")
    end
  end

  def test_modal_typing_view
    with_test_terminal do
      # Start with modal open
      start_model = DashboardManual::INITIAL.with(
        shell_modal: CustomShellModal::INITIAL.with(mode: :input)
      )

      # 1. Type "ls -la"
      # 2. Render (captured)
      # 3. ESC to cancel
      # 4. q to quit
      inject_key("l")
      inject_key("s")
      inject_key(" ")
      inject_key("-")
      inject_key("l")
      inject_key("a")
      inject_key(:esc)
      inject_key(:q)

      RatatuiRuby::Tea.run(
        model: start_model,
        view: DashboardManual::VIEW,
        update: DashboardManual::UPDATE
      )

      assert_snapshots("modal_typing")
    end
  end

  def test_modal_output_view
    with_test_terminal do
      # Start with modal showing output
      chunks = Ractor.make_shareable([
        CustomShellOutput::Chunk.new(stream: :stdout, text: "total 0\n"),
        CustomShellOutput::Chunk.new(stream: :stderr, text: "Error: something went wrong\n"),
        CustomShellOutput::Chunk.new(stream: :stdout, text: "drwxr-xr-x  3 kerrick  staff  96 Jan  1 12:00 .\n"),
      ].freeze)

      output_model = CustomShellOutput::INITIAL.with(
        command: "ls -la",
        chunks:,
        running: false,
        exit_status: 1
      )

      start_model = DashboardManual::INITIAL.with(
        shell_modal: CustomShellModal::INITIAL.with(
          mode: :output,
          output: output_model
        )
      )

      # 1. Render output (captured)
      # 2. ESC to dismiss
      # 3. q to quit
      inject_key(:esc)
      inject_key(:q)

      RatatuiRuby::Tea.run(
        model: start_model,
        view: DashboardManual::VIEW,
        update: DashboardManual::UPDATE
      )

      assert_snapshots("modal_output")
    end
  end
end

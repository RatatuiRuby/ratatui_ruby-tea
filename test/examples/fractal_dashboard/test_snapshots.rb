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
        inject_keys("s", :q)

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
        inject_keys("d", :q)

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
        inject_keys("p", :q)

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
        inject_keys("u", :q)

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
end

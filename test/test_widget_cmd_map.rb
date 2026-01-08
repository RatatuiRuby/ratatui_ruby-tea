# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: MIT-0
#++

require "test_helper"
require_relative "../examples/widget_cmd_map/app"

class TestWidgetCmdMap < Minitest::Test
  def test_update_routes_stats_panel_message
    model = WidgetCmdMap::INITIAL
    msg = [:stats, :system_info, { stdout: "Darwin\n", stderr: "", status: 0 }]

    result = WidgetCmdMap::UPDATE.call(msg, model)

    new_model, cmd = result
    assert_equal "Darwin", new_model.stats.system_info.output
    assert_nil cmd
  end

  def test_update_routes_network_panel_message
    model = WidgetCmdMap::INITIAL
    msg = [:network, :ping, { stdout: "PING localhost\n", stderr: "", status: 0 }]

    result = WidgetCmdMap::UPDATE.call(msg, model)

    new_model, cmd = result
    assert_equal "PING localhost", new_model.network.ping.output
    assert_nil cmd
  end

  def test_s_key_triggers_mapped_system_info_command
    model = WidgetCmdMap::INITIAL
    msg = RatatuiRuby::Event::Key.new(code: "s", modifiers: [])

    result = WidgetCmdMap::UPDATE.call(msg, model)

    new_model, cmd = result
    assert new_model.stats.system_info.loading, "Should set loading state"
    assert_kind_of RatatuiRuby::Tea::Cmd::Mapped, cmd
    assert_kind_of RatatuiRuby::Tea::Cmd::Exec, cmd.inner_cmd
    assert_equal :system_info, cmd.inner_cmd.tag
  end

  def test_p_key_triggers_mapped_ping_command
    model = WidgetCmdMap::INITIAL
    msg = RatatuiRuby::Event::Key.new(code: "p", modifiers: [])

    result = WidgetCmdMap::UPDATE.call(msg, model)

    new_model, cmd = result
    assert new_model.network.ping.loading, "Should set loading state"
    assert_kind_of RatatuiRuby::Tea::Cmd::Mapped, cmd
    assert_kind_of RatatuiRuby::Tea::Cmd::Exec, cmd.inner_cmd
    assert_equal :ping, cmd.inner_cmd.tag
  end

  def test_mapper_wraps_with_panel_prefix
    # Verify the mapper transforms the message correctly
    inner_cmd = WidgetCmdMap::SystemInfoWidget.fetch_cmd
    cmd = RatatuiRuby::Tea::Cmd.map(inner_cmd) { |m| [:stats, *m] }

    # Simulate what dispatch would produce
    inner_msg = [:system_info, { stdout: "test", stderr: "", status: 0 }]
    transformed = cmd.mapper.call(inner_msg)

    assert_equal :stats, transformed[0]
    assert_equal :system_info, transformed[1]
  end
end

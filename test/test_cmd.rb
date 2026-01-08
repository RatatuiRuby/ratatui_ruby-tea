# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: LGPL-3.0-or-later
#++

require "test_helper"

class TestCmd < Minitest::Test
  def test_cmd_quit_is_sentinel
    result = RatatuiRuby::Tea::Cmd.quit
    assert_kind_of RatatuiRuby::Tea::Cmd::Quit, result
  end

  def test_cmd_exec_creates_exec_command
    cmd = RatatuiRuby::Tea::Cmd.exec("echo hello", :got_output)
    assert_kind_of RatatuiRuby::Tea::Cmd::Exec, cmd
    assert_equal "echo hello", cmd.command
    assert_equal :got_output, cmd.tag
  end

  def test_cmd_exec_is_ractor_shareable
    cmd = RatatuiRuby::Tea::Cmd.exec("ls", :files)
    # The command itself should be shareable (no Proc captures)
    assert Ractor.shareable?(cmd), "Cmd::Exec should be Ractor-shareable"
  end

  def test_execute_cmd_exec_produces_ractor_shareable_message
    # The message returned by the runtime must be Ractor-shareable
    # so models using stdout/stderr can be shared across Ractors
    require "open3" # Must require before stubbing
    cmd = RatatuiRuby::Tea::Cmd.exec("never_executed", :got_output)

    mock_status = Object.new
    mock_status.define_singleton_method(:exitstatus) { 0 }

    msg = nil
    Open3.stub(:capture3, ["mocked output\n", "mocked stderr\n", mock_status]) do
      msg = RatatuiRuby::Tea::Runtime.__send__(:execute_cmd_exec, cmd)
    end

    assert Ractor.shareable?(msg), "Cmd::Exec message should be Ractor-shareable"
  end
end

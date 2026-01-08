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
end

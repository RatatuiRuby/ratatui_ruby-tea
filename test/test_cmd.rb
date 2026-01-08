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

  def test_cmd_map_creates_mapped_command
    inner = RatatuiRuby::Tea::Cmd.exec("echo hello", :inner_tag)

    cmd = RatatuiRuby::Tea::Cmd.map(inner) { |msg| [:parent, msg] }

    assert_kind_of RatatuiRuby::Tea::Cmd::Mapped, cmd
  end

  def test_cmd_map_stores_inner_and_mapper
    inner = RatatuiRuby::Tea::Cmd.exec("echo hello", :inner_tag)
    mapper = -> (msg) { [:parent, msg] }

    cmd = RatatuiRuby::Tea::Cmd.map(inner, &mapper)

    assert_equal inner, cmd.inner_cmd
    assert_equal mapper, cmd.mapper
  end
end

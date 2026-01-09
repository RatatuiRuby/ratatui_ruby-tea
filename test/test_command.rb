# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: LGPL-3.0-or-later
#++

require "test_helper"

class TestCommand < Minitest::Test
  def test_command_quit_is_sentinel
    result = RatatuiRuby::Tea::Command.exit
    assert_kind_of RatatuiRuby::Tea::Command::Exit, result
  end

  def test_command_system_creates_execute_command
    command = RatatuiRuby::Tea::Command.system("echo hello", :got_output)
    assert_kind_of RatatuiRuby::Tea::Command::System, command
    assert_equal "echo hello", command.command
    assert_equal :got_output, command.tag
  end

  def test_command_system_defaults_to_non_streaming
    command = RatatuiRuby::Tea::Command.system("echo hello", :got_output)
    refute command.stream?, "stream? should default to false"
  end

  def test_command_system_accepts_stream_kwarg
    command = RatatuiRuby::Tea::Command.system("echo hello", :got_output, stream: true)
    assert command.stream?, "stream? should be true when passed"
  end

  def test_command_system_is_ractor_shareable
    command = RatatuiRuby::Tea::Command.system("ls", :files)
    # The command itself should be shareable (no Proc captures)
    assert Ractor.shareable?(command), "Command::System should be Ractor-shareable"
  end

  def test_command_map_creates_mapped_command
    inner = RatatuiRuby::Tea::Command.system("echo hello", :inner_tag)

    command = RatatuiRuby::Tea::Command.map(inner) { |message| [:parent, message] }

    assert_kind_of RatatuiRuby::Tea::Command::Mapped, command
  end

  def test_command_map_stores_inner_and_mapper
    inner = RatatuiRuby::Tea::Command.system("echo hello", :inner_tag)
    mapper = -> (message) { [:parent, message] }

    command = RatatuiRuby::Tea::Command.map(inner, &mapper)

    assert_equal inner, command.inner_command
    assert_equal mapper, command.mapper
  end
end

# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: LGPL-3.0-or-later
#++

require "test_helper"
require "ratatui_ruby/tea/shortcuts"

class TestShortcuts < Minitest::Test
  include RatatuiRuby::Tea::Shortcuts

  def test_cmd_exit_returns_exit_command
    result = Cmd.exit

    assert_kind_of RatatuiRuby::Tea::Command::Exit, result
  end

  def test_cmd_sh_returns_system_command
    result = Cmd.sh("echo hello", :got_output)

    assert_kind_of RatatuiRuby::Tea::Command::System, result
    assert_equal "echo hello", result.command
    assert_equal :got_output, result.tag
  end

  def test_cmd_map_returns_mapped_command
    inner = Cmd.sh("ls", :files)
    mapper = -> (message) { [:wrapped, message] }

    result = Cmd.map(inner, &mapper)

    assert_kind_of RatatuiRuby::Tea::Command::Mapped, result
    assert_equal inner, result.inner_command
    assert_equal mapper, result.mapper
  end

  def test_including_shortcuts_provides_cmd_module
    # self.class already includes Shortcuts (see top of class)
    # This test documents the expected usage pattern
    assert defined?(Cmd), "Cmd module should be available after including Shortcuts"
  end

  def test_cmd_map_with_block_syntax
    inner = Cmd.sh("ls", :files)

    result = Cmd.map(inner) { |message| [:parent, *message] }

    assert_kind_of RatatuiRuby::Tea::Command::Mapped, result
    # Verify the mapper works
    transformed = result.mapper.call([:files, { stdout: "a.txt" }])
    assert_equal [:parent, :files, { stdout: "a.txt" }], transformed
  end
end

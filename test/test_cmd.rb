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
end

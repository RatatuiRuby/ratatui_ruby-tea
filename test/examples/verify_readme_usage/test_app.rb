# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: LGPL-3.0-or-later
#++

require "test_helper"
require "ratatui_ruby/test_helper"
require_relative "../../../examples/verify_readme_usage/app"

class TestReadmeUsage < Minitest::Test
  include RatatuiRuby::TestHelper

  def setup
    @app = VerifyReadmeUsage.new
  end

  def test_render
    with_test_terminal do
      inject_key(:q)
      @app.run

      assert_snapshots("render")
    end
  end
end

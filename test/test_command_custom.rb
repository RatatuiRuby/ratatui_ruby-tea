# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: LGPL-3.0-or-later
#++

require "test_helper"

class TestCommandCustom < Minitest::Test
  def test_tea_command_returns_true
    klass = Class.new do
      include RatatuiRuby::Tea::Command::Custom
    end

    assert klass.new.tea_command?, "tea_command? should return true"
  end

  def test_default_grace_period_is_two_seconds
    klass = Class.new do
      include RatatuiRuby::Tea::Command::Custom
    end

    assert_equal 2.0, klass.new.tea_cancellation_grace_period
  end

  def test_grace_period_can_be_overridden
    klass = Class.new do
      include RatatuiRuby::Tea::Command::Custom

      def tea_cancellation_grace_period
        Float::INFINITY
      end
    end

    assert_equal Float::INFINITY, klass.new.tea_cancellation_grace_period
  end
end

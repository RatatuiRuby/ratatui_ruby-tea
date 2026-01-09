# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: MIT-0
#++

require_relative "base"

# UPDATE using the declarative Tea::Router DSL.
#
# This is the minimal-boilerplate approach: declare routes and keymaps,
# let from_router generate the UPDATE lambda. Maximum DX, least control.
module DashboardRouter
  include RatatuiRuby::Tea::Router

  Command = RatatuiRuby::Tea::Command

  # Shared with other UPDATE variants
  Model = DashboardBase::Model
  INITIAL = DashboardBase::INITIAL
  VIEW = DashboardBase::VIEW

  route :stats, to: StatsPanel
  route :network, to: NetworkPanel

  # Guard: only handle keys when modal is not active
  MODAL_INACTIVE = -> (model) { !CustomShellModal.active?(model.shell_modal) }

  keymap do
    key :ctrl_c, -> { Command.exit }
    only when: MODAL_INACTIVE do
      key :q, -> { Command.exit }
      key :s, -> { SystemInfo.fetch_command }
      key :d, -> { DiskUsage.fetch_command }
      key :p, -> { Ping.fetch_command }
      key :u, -> { Uptime.fetch_command }
      key :c, -> { CustomShellModal.open }
    end
  end

  UPDATE = from_router
end

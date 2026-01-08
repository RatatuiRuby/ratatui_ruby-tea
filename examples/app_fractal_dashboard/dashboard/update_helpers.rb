# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: MIT-0
#++

require_relative "base"

# UPDATE using Tea.route and Tea.delegate helpers.
#
# This is the medium-verbosity approach: routing helpers reduce boilerplate
# while keeping the case statement visible. A good middle ground.
module DashboardHelpers
  Command = RatatuiRuby::Tea::Command
  Tea = RatatuiRuby::Tea

  # Shared with other UPDATE variants
  Model = DashboardBase::Model
  INITIAL = DashboardBase::INITIAL
  VIEW = DashboardBase::VIEW

  UPDATE = lambda do |message, model|
    # Try routing to child bags first
    if (result = Tea.delegate(message, :stats, StatsPanel::UPDATE, model.stats))
      new_child, command = result
      return [model.with(stats: new_child), command && Tea.route(command, :stats)]
    end

    if (result = Tea.delegate(message, :network, NetworkPanel::UPDATE, model.network))
      new_child, command = result
      return [model.with(network: new_child), command && Tea.route(command, :network)]
    end

    # Handle user input
    case message
    in _ if message.q? || message.ctrl_c?
      Command.exit

    in _ if message.s?
      command = Tea.route(SystemInfo.fetch_command, :stats)
      new_stats = model.stats.with(system_info: model.stats.system_info.with(loading: true))
      [model.with(stats: new_stats), command]

    in _ if message.d?
      command = Tea.route(DiskUsage.fetch_command, :stats)
      new_stats = model.stats.with(disk_usage: model.stats.disk_usage.with(loading: true))
      [model.with(stats: new_stats), command]

    in _ if message.p?
      command = Tea.route(Ping.fetch_command, :network)
      new_network = model.network.with(ping: model.network.ping.with(loading: true))
      [model.with(network: new_network), command]

    in _ if message.u?
      command = Tea.route(Uptime.fetch_command, :network)
      new_network = model.network.with(uptime: model.network.uptime.with(loading: true))
      [model.with(network: new_network), command]

    else
      model
    end
  end
end

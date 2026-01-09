# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: LGPL-3.0-or-later
#++

# Text input bag for custom shell command modal.
#
# Handles text entry. Sets cancelled: or submitted: in model for parent to detect.
module CustomShellInput
  Model = Data.define(:text, :cancelled, :submitted)
  INITIAL = Ractor.make_shareable(Model.new(text: "", cancelled: false, submitted: false))

  VIEW = lambda do |model, tui|
    content = if model.text.empty?
      tui.paragraph(text: tui.text_span(content: "Type a command...", style: { fg: :dark_gray }))
    else
      tui.paragraph(text: model.text)
    end

    tui.layout(
      direction: :vertical,
      constraints: [
        tui.constraint_length(1),
        tui.constraint_length(3),
        tui.constraint_min(0),
      ],
      children: [
        nil,
        tui.center(
          width_percent: 80,
          child: tui.overlay(
            layers: [
              tui.clear,
              tui.block(
                title: "Run Command",
                titles: [
                  { content: "ESC: Cancel", position: :bottom, alignment: :left },
                  { content: "ENTER: Run", position: :bottom, alignment: :right },
                ],
                borders: [:all],
                children: [content]
              ),
            ]
          )
        ),
        nil,
      ]
    )
  end

  UPDATE = lambda do |message, model|
    case message
    in _ if message.respond_to?(:esc?) && message.esc?
      [model.with(cancelled: true), nil]

    in _ if message.respond_to?(:enter?) && message.enter?
      return [model.with(cancelled: true), nil] if model.text.strip.empty?
      [model.with(submitted: true), nil]

    in _ if message.respond_to?(:backspace?) && message.backspace?
      [model.with(text: model.text.chop.freeze), nil]

    in RatatuiRuby::Event::Paste
      # Handle continuation backslashes: "foo \\\nbar" → "foo bar"
      normalized = message.content.gsub(/\\\r?\n/, "").gsub(/[\r\n]/, " ")
      [model.with(text: "#{model.text}#{normalized}".freeze), nil]

    in RatatuiRuby::Event::Key if message.text? && message.code.length == 1
      [model.with(text: "#{model.text}#{message.code}".freeze), nil]

    else
      [model, nil]
    end
  end
end

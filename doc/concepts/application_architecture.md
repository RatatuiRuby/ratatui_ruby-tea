<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Application Architecture

Build robust TUI applications with Tea patterns.

## Core Concepts

_This section is incomplete. Check the source files._

## Thread and Ractor Safety

### The Strategic Context

Ruby 4.0 introduces [Ractors](https://docs.ruby-lang.org/en/4.0/Ractor.html)—
true parallel actors that forbid shared mutable state. Code that passes
mutable objects between threads crashes in a Ractor world.

Tea prepares you today. The runtime enforces Ractor-shareability on every
Model and Message *now*, using standard threads. Pass a mutable object,
and it raises an error immediately. Write Ractor-safe code today; upgrade
to Ruby 4.0 without changes tomorrow.

Enforce immutability rules before you strictly need them, and the migration
is invisible.

### The Problem

Ruby's Ractor model prevents data races by forbidding shared mutable state.
Mutable objects cause runtime errors:

```
RatatuiRuby::Error::Invariant: Model is not Ractor-shareable.
```

### The Solution

Use `Ractor.make_shareable`. It recursively freezes everything:

```ruby
Ractor.make_shareable(model.with(text: "#{model.text}#{char}"))
```

For constants, wrap INITIAL:

```ruby
INITIAL = Ractor.make_shareable(
  Model.new(text: "", running: false, chunks: [])
)
```

For collection updates:

```ruby
new_chunks = Ractor.make_shareable([*model.chunks, new_item])
```

### The Lightweight Alternative

When you know exactly what's mutable, `.freeze` is shorter:

```ruby
[model.with(text: "#{model.text}#{char}".freeze), nil]
```

### Foot-Guns

#### frozen_string_literal Only Affects Literals

The magic comment freezes strings that appear directly in source code.
Computed strings are mutable.

```ruby
# frozen_string_literal: true

"literal"        # frozen ✓
"#{var}"         # mutable ✗
str.chop         # mutable ✗
str + other      # mutable ✗
```

#### Data.define Needs Shareable Values

`Data.define` creates frozen instances. The instance is Ractor-shareable
only when all its values are shareable.

### Quick Reference

| Pattern | Code |
|---------|------|
| Make anything shareable | `Ractor.make_shareable(obj)` |
| Freeze a string | `str.freeze` |
| INITIAL constant | `Ractor.make_shareable(Model.new(...))` |
| Array update | `Ractor.make_shareable([*old, new])` |

### Debugging

See this error?

```
RatatuiRuby::Error::Invariant: Model is not Ractor-shareable.
```

Wrap the returned model with `Ractor.make_shareable`.

## Modals and Command Result Routing

Modals capture keyboard input. They overlay the main UI and intercept keypresses until dismissed. But async commands keep running in the background. When their results arrive, they look like any other message.

It's tempting to intercept *all* messages when the modal is active. This swallows those command results.

### The Scenario

1. User presses "u" to fetch uptime. The runtime dispatches an async command.
2. User presses "c" to open a modal dialog.
3. The uptime command completes. It sends `[:network, :uptime, { stdout:, ... }]`.
4. The modal intercept sees the modal is active. It routes that message to the modal.
5. The modal ignores it.
6. The uptime panel never updates.

### The Fix

Route command results before modal interception. Modals intercept user input, not async results.

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long
  SPDX-License-Identifier: MIT-0
-->
```ruby
# Wrong: modal intercepts everything
UPDATE = lambda do |message, model|
  if Modal.active?(model.modal)
    # Swallows command results
    return Modal::UPDATE.call(message, model.modal)
  end

  case message
  in [:network, *rest]
    # Never reached while modal is open
  end
end

# Correct: route command results first
UPDATE = lambda do |message, model|
  # 1. Route async command results (always)
  case message
  in [:network, *rest]
    return [model.with(network: new_network), command]
  in [:stats, *rest]
    return [model.with(stats: new_stats), command]
  else
    nil
  end

  # 2. Modal intercepts user input
  if Modal.active?(model.modal)
    return Modal::UPDATE.call(message, model.modal)
  end

  # 3. Handle other input
  case message
  in _ if message.q? then Command.exit
  end
end
```
<!-- SPDX-SnippetEnd -->

### The Router DSL

`Tea::Router` handles this correctly. Routes declared with `route :prefix, to: ChildModule` process before keymap handlers. Command results flow through even when guards block keyboard input.

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long
  SPDX-License-Identifier: MIT-0
-->
```ruby
module Dashboard
  include Tea::Router

  route :stats, to: StatsPanel
  route :network, to: NetworkPanel

  keymap do
    only when: MODAL_INACTIVE do
      key "u", -> { Uptime.fetch_command }
    end
  end
end
```
<!-- SPDX-SnippetEnd -->

<!--
SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Why Kit Doesn't Need Outlet

> **Context**: The `unified-draft.md` specifies `Tea::Command::Outlet` for message passing from custom commands to the Tea runtime. This document explains why Kit (the component-based runtime) does not need this abstraction.

---

## The Core Insight: Immediate-Mode Rendering

RatatuiRuby's Engine is **immediate-mode**:

> "Each frame, your code describes the entire UI from scratch. The Engine draws it and immediately forgets it, holding no application state between renders."

This means Kit walks the entire component tree and calls `render` **every frame**. Components don't need to notify anyone of state changes—the next frame automatically sees updated state.

---

## Tea vs Kit: Different Problems

| Concern | Tea | Kit |
|---------|-----|-----|
| **State model** | Immutable (Ractor-safe) | Mutable (encapsulated) |
| **State location** | Single Model in runtime | Distributed in components |
| **Async results** | Message → Queue → Update | Callback → mutate state |
| **Render trigger** | After update function | **Every frame** |
| **Re-render notification** | Implicit (update always renders) | **Not needed** (always renders) |

---

## WebSocket Example: Tea vs Kit

### Tea: Outlet Required

```ruby
class WebSocketCommand
  include Tea::Command::Custom

  def call(out, token)
    ws = WebSocket::Client.new(@url)
    ws.on_message { |msg| out.put(:ws, :message, data: msg) }
    ws.connect

    until token.cancelled?
      sleep 1
    end

    ws.close
  end
end

def update(msg, model)
  case msg
  in [:ws, :message, data:]
    model.with(messages: model.messages + [data])
  end
end
```

Tea needs Outlet because:
1. Command runs in a separate thread
2. Model is immutable—can't mutate from callback
3. Runtime must receive messages to call `update`

### Kit: Direct Mutation

```ruby
class WebSocketTab
  include Kit::Component

  def initialize(url:)
    @url = url
    @messages = []
  end

  def mount
    @ws = WebSocket::Client.new(@url)
    @ws.on_message { |msg| @messages << msg }
    @ws.connect_async
  end

  def unmount
    @ws&.close
  end

  def render(frame, area)
    frame.render_widget(tui.list(items: @messages.last(10)), area)
  end
end
```

Kit doesn't need Outlet because:
1. Component owns the WebSocket directly
2. State is mutable—callbacks mutate `@messages`
3. Next frame's `render` sees updated state automatically

---

## Why Each Tea Concept Is Unnecessary in Kit

### Outlet (Message Gateway)

**Tea**: Routes messages from command thread → runtime queue → update function.

**Kit**: Not needed. Callbacks mutate component state directly. Immediate-mode rendering sees changes next frame.

### CancellationToken

**Tea**: Runtime signals command to stop cooperatively, since commands run in spawned threads tracked by the runtime.

**Kit**: Not needed. Components have `unmount` lifecycle hook. Component stops its own resources:

```ruby
def unmount
  @ws&.close
  @polling_thread&.kill
end
```

### Ractor Safety

**Tea**: Messages cross thread boundaries and must be Ractor-shareable for future Ruby 4.0 compatibility.

**Kit**: Not needed. Components are mutable by design. State stays within the component. No Ractor isolation required.

### Thread Tracking

**Tea**: Runtime tracks spawned command threads to ensure clean shutdown.

**Kit**: Not needed. Each component tracks its own resources. Tree traversal during shutdown calls `unmount` on each component.

---

## What Kit DOES Need

### 1. Lifecycle Hooks

```ruby
module Kit::Component
  def mount
    # Called when component enters tree
  end

  def unmount
    # Called when component leaves tree
  end
end
```

These replace Tea's command spawning and cancellation.

### 2. Thread Safety for Complex Mutations

For simple mutations (array append, boolean toggle), Ruby's GIL is sufficient.

For complex mutations:

```ruby
def mount
  @mutex = Mutex.new
  @ws = WebSocket::Client.new(@url)
  @ws.on_message do |msg|
    @mutex.synchronize { @messages << msg }
  end
end

def render(frame, area)
  messages = @mutex.synchronize { @messages.dup }
  # render with messages
end
```

### 3. Error Handling

Components should rescue and surface errors:

```ruby
def mount
  @ws = WebSocket::Client.new(@url)
  @ws.on_error { |e| @error = e.message }
rescue => e
  @error = e.message
end
```

---

## Comparison Table

| Abstraction | Tea | Kit | Why Different |
|-------------|-----|-----|---------------|
| **Outlet** | ✓ Required | ✗ Not needed | Kit mutates directly |
| **CancellationToken** | ✓ Required | ✗ Not needed | Kit has `unmount` |
| **Ractor safety** | ✓ Required | ✗ Not needed | Kit is mutable |
| **Thread tracking** | ✓ Runtime tracks | ✗ Not needed | Components self-manage |
| **Lifecycle hooks** | ✗ Not applicable | ✓ Required | Kit needs mount/unmount |
| **Mutex** | ✗ Uses Outlet | ⚠ If complex | Kit needs manual locking |

---

## Architectural Summary

```
┌─────────────────────────────────────────────────────────────────┐
│                          ENGINE                                  │
│               (Immediate-mode, renders every frame)              │
├─────────────────────────────┬───────────────────────────────────┤
│            TEA              │              KIT                   │
│                             │                                    │
│  Immutable Model            │  Mutable Components                │
│  Commands spawn threads     │  Components own resources          │
│  Outlet sends messages      │  Callbacks mutate state            │
│  Runtime tracks threads     │  unmount cleans up                 │
│  Ractor-safe required       │  GIL + Mutex sufficient            │
│                             │                                    │
│  NEEDS OUTLET               │  DOESN'T NEED OUTLET               │
└─────────────────────────────┴───────────────────────────────────┘
```

---

## Conclusion

**Outlet is Tea-specific.** It solves the problem of getting async results into an immutable, unidirectional data flow.

Kit's paradigm—mutable components with immediate-mode rendering—makes Outlet unnecessary:

1. **Callbacks mutate state** → No message routing needed
2. **Render every frame** → No change notification needed
3. **`unmount` hook** → No external cancellation needed
4. **Components own resources** → No runtime tracking needed

The Outlet stays in `Tea::Command::Outlet`. Kit needs no equivalent.

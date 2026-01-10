<!--
SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Custom Commands: Unified Design Specification

> **Status**: Final Design  
> **Decision**: Option 2 (Tea::Outlet) + Solution C Hybrid (Thread Tracking + Cancellation Token)

This document specifies the architecture for user-defined custom commands in `ratatui_ruby-tea`, synthesizing the decisions from `queue-mailbox-draft.md` and `command-plugin-draft.md`.

---

## Executive Summary

Custom commands enable developers to extend Tea with custom side effects (WebSockets, gRPC, background tasks). The design provides:

1. **`Tea::Command::Custom`** — Mixin for command identification
2. **`Tea::Command::Outlet`** — Ractor-safe message passing abstraction
3. **`Tea::Command::CancellationToken`** — Cooperative cancellation mechanism
4. **Thread Tracking** — Runtime safety net for resource cleanup

---

## Core Abstractions

### Command::Custom Mixin

```ruby
module RatatuiRuby::Tea::Command
  module Custom
    # Brand predicate for update return disambiguation.
    def tea_command? = true

    # Cooperative cancellation grace period (seconds).
    # Override in your command to specify cleanup time needed.
    # Default: 2.0 seconds
    # Use Float::INFINITY to never be force-killed.
    def tea_cancellation_grace_period
      2.0
    end
  end
end
```

### Outlet (Messaging Gateway)

The Outlet wraps the internal queue, providing Ractor-safety and domain-specific API:

```ruby
module RatatuiRuby::Tea::Command
  class Outlet
    def initialize(queue)
      @queue = queue
    end

    # Push a message to the runtime.
    #
    # @param tag [Symbol] Message type identifier
    # @param payload [Array] Message payload (should be Ractor-shareable)
    # @raise [RatatuiRuby::Error::Invariant] If payload is not shareable (debug mode only)
    def put(tag, *payload)
      message = [tag, *payload]
      
      if RatatuiRuby::Debug.enabled? && !Ractor.shareable?(message)
        raise RatatuiRuby::Error::Invariant,
          "Message is not Ractor-shareable: #{message.inspect}\n" \
          "Use Ractor.make_shareable or Object#freeze."
      end
      
      @queue << message
    end
  end
end
```

### CancellationToken

Cooperative cancellation mechanism for long-running commands:

```ruby
module RatatuiRuby::Tea::Command
  class CancellationToken
    def initialize
      @cancelled = false
      @mutex = Mutex.new
    end

    # Signal cancellation. Thread-safe.
    def cancel!
      @mutex.synchronize { @cancelled = true }
    end

    # Check if cancellation was requested. Thread-safe.
    def cancelled?
      @mutex.synchronize { @cancelled }
    end

    # Null object for commands that don't support cancellation
    NONE = Class.new do
      def cancelled? = false
      def cancel! = nil
    end.new.freeze
  end
end
```

---

## The _Command Interface

```rbs
# sig/ratatui_ruby/tea/command.rbs
interface _Command
  # Brand predicate for update return disambiguation.
  def tea_command?: () -> true

  # Execute the command's side effect.
  # Push result messages via the outlet.
  def call: (Command::Outlet out, Command::CancellationToken token) -> void

  # Grace period for cooperative cancellation (seconds).
  # Runtime waits this long before force-killing the thread.
  def tea_cancellation_grace_period: () -> Float
end
```

---

## Runtime Integration

### Dispatch Logic

```ruby
class Runtime
  def initialize
    @queue = Thread::Queue.new
    @active_commands = {}  # id => { thread:, token: Command::CancellationToken, command: }
    @next_command_id = 0
  end

  private def dispatch(command)
    case command
    when Command::System
      dispatch_system(command)
    when Command::Mapped
      dispatch_mapped(command)
    else
      dispatch_custom(command) if custom_command?(command)
    end
  end

  private def custom_command?(value)
    value.respond_to?(:call) &&
      value.respond_to?(:tea_command?) &&
      value.tea_command?
  end

  private def dispatch_custom(command)
    id = @next_command_id += 1
    token = Command::CancellationToken.new
    outlet = Command::Outlet.new(@queue)

    thread = Thread.new do
      command.call(outlet, token)
    rescue => e
      outlet.put(:command_error, id: id, error: e.message)
    end

    @active_commands[id] = { thread: thread, token: token, command: command }
    id
  end
end
```

### Cancellation Logic (Hybrid Approach)

```ruby
class Runtime
  # Cancel a running command by ID.
  # Uses cooperative cancellation with configurable timeout.
  def cancel_command(id)
    entry = @active_commands[id]
    return unless entry

    command = entry[:command]
    token = entry[:token]
    thread = entry[:thread]

    return unless thread.alive?

    # 1. Request cooperative cancellation
    token.cancel!

    # 2. Wait for grace period (respect Float::INFINITY)
    grace = command.tea_cancellation_grace_period
    if grace.finite?
      deadline = Time.now + grace
      while thread.alive? && Time.now < deadline
        sleep 0.05
      end
    else
      # Infinite grace: wait indefinitely for cooperative stop
      thread.join
    end

    # 3. Force-kill if still alive and grace was finite
    if thread.alive? && grace.finite?
      warn "[Tea] Command #{command.class} did not stop within #{grace}s, killing"
      thread.kill
    end

    @active_commands.delete(id)
  end

  # Shutdown all commands (app exit).
  # Ignores grace periods for fast shutdown.
  def shutdown
    @active_commands.each_value do |entry|
      entry[:token].cancel!
    end

    # Brief cooperative window
    sleep 0.1

    # Force-kill any survivors
    @active_commands.each_value do |entry|
      entry[:thread].kill if entry[:thread].alive?
    end

    @active_commands.clear
  end
end
```

---

## Usage Examples

### Lambda with Singleton Methods (Lightweight)

Ruby allows defining singleton methods on any object, including Procs. This enables a lightweight command style without classes:

```ruby
# Simple one-shot command
Ping = ->(out, _token) { out.put(:pong) }
def Ping.tea_command? = true

# With custom grace period
SlowFetch = ->(out, token) {
  until token.cancelled?
    data = fetch_batch
    out.put(:batch, data)
    sleep 5
  end
}
def SlowFetch.tea_command? = true
def SlowFetch.tea_cancellation_grace_period = 10.0

# In update function
[model, Ping]
[model, SlowFetch]
```

This satisfies the `_Command` interface through pure duck typing—no wrappers, no special cases.

**All callable types support singleton methods:**

| Type | Example |
|------|---------|
| Lambda | `CMD = ->(out, token) { ... }` |
| Proc | `CMD = proc { \|out, token\| ... }` |
| Method object | `CMD = method(:fetch_data)` |
| Callable instance | `CMD = MyFetcher.new` |

```ruby
# Method object with singleton methods
def fetch_data(out, token)
  response = HTTP.get(url)
  out.put(:fetched, response)
end

FetchData = method(:fetch_data)
def FetchData.tea_command? = true
def FetchData.tea_cancellation_grace_period = 5.0
```

> **Future consideration**: A unified factory that accepts any callable or block:
> ```ruby
> # With callables
> Command.custom(->(out) { out.put(:done) })
> Command.custom(method(:fetch_data), grace_period: 5.0)
> Command.custom(MyFetcher.new)
>
> # With block (more idiomatic)
> Command.custom(grace_period: 10.0) do |out, token|
>   until token.cancelled?
>     out.put(:tick, Time.now)
>     sleep 1
>   end
> end
> ```
> This would attach singleton methods automatically. One method, multiple styles.

### Class-Based Command (Full Control)

```ruby
class FetchUserCommand
  include RatatuiRuby::Tea::Command::Custom

  def initialize(user_id)
    @user_id = user_id
  end

  def call(out, _token)
    response = Net::HTTP.get_response(URI("https://api.example.com/users/#{@user_id}"))
    user = JSON.parse(response.body)
    out.put(:user_fetched, user: user)
  rescue => e
    out.put(:user_fetch_failed, error: e.message)
  end
end
```

### Long-Running with Cooperative Cancellation

```ruby
class WebSocketCommand
  include RatatuiRuby::Tea::Command::Custom

  def initialize(url)
    @url = url
  end

  # Need extra time for WebSocket close handshake
  def tea_cancellation_grace_period
    5.0
  end

  def call(out, token)
    ws = WebSocket::Client.new(@url)
    ws.on_open { out.put(:ws, :connected) }
    ws.on_message { |msg| out.put(:ws, :message, data: msg) }
    ws.connect

    # Main loop with cancellation check
    until token.cancelled?
      ws.ping
      sleep 1
    end

    # Graceful shutdown
    ws.close(code: 1000, reason: "User cancelled")
    out.put(:ws, :closed)
  end
end
```

### Background Ticker (Never Force-Kill)

```ruby
class DatabasePollerCommand
  include RatatuiRuby::Tea::Command::Custom

  # Database transactions should never be interrupted
  def tea_cancellation_grace_period
    Float::INFINITY
  end

  def call(out, token)
    loop do
      break if token.cancelled?

      ActiveRecord::Base.transaction do
        records = SomeModel.where(processed: false).limit(100)
        records.each do |record|
          process(record)
          record.update!(processed: true)
        end
        out.put(:batch_complete, count: records.size)
      end

      sleep 5 unless token.cancelled?
    end

    out.put(:poller_stopped)
  end
end
```

---

## Update Function Integration

```ruby
def update(msg, model)
  case msg
  in [:connect_ws]
    command = WebSocketCommand.new("wss://example.com/socket")
    [model.with(ws_command_id: nil), command]

  in [:ws, :connected]
    model.with(connected: true)

  in [:ws, :message, data:]
    model.with(messages: model.messages + [data])

  in [:disconnect_ws]
    # Trigger cancellation via runtime
    # (Requires runtime reference or message-based cancellation)
    model.with(ws_should_disconnect: true)

  in [:ws, :closed]
    model.with(connected: false, ws_command_id: nil)
  end
end
```

---

## Design Rationale

### Why Outlet over Raw Queue?

| Aspect | Raw Queue | Outlet |
|--------|-----------|--------|
| Ractor safety | Manual | Automatic |
| Error messages | Generic | Contextual |
| API | `queue << Ractor.make_shareable([...])` | `out.put(:tag, data)` |
| Pattern | Implementation detail | **Messaging Gateway** (EIP) |

### Why Cancellation Token over Thread#kill?

| Aspect | Thread#kill | Cancellation Token |
|--------|-------------|-------------------|
| Cleanup | None (immediate termination) | Command controls cleanup |
| Resource safety | May corrupt state | Clean shutdown |
| Mutexes | May deadlock | Released properly |
| Pattern | Forceful | **Cooperative** |

### Why Configurable Grace Period?

Different commands have different cleanup needs:

- HTTP request: 0.5s (just abort)
- WebSocket: 5s (close handshake)
- Database transaction: ∞ (never interrupt)

The module provides a sensible default (2s) that works for most cases.

---

## RBS Type Definitions

```rbs
# sig/ratatui_ruby/tea/command/outlet.rbs
module RatatuiRuby::Tea::Command
  class Outlet
    def initialize: (Thread::Queue[untyped]) -> void
    def put: (Symbol tag, *untyped payload) -> void
  end

  class RactorSafetyError < StandardError
  end
end

# sig/ratatui_ruby/tea/command/cancellation_token.rbs
module RatatuiRuby::Tea::Command
  class CancellationToken
    def initialize: () -> void
    def cancel!: () -> void
    def cancelled?: () -> bool

    NONE: CancellationToken
  end
end

# sig/ratatui_ruby/tea/command/custom.rbs
module RatatuiRuby::Tea::Command
  module Custom
    def tea_command?: () -> true
    def tea_cancellation_grace_period: () -> Float
  end
end
```

---

## Pattern Lineage

This design implements several established patterns:

| Component | Pattern | Source |
|-----------|---------|--------|
| Outlet | **Messaging Gateway** | Enterprise Integration Patterns |
| Outlet | **Facade** | Gang of Four |
| CancellationToken | **Cooperative Cancellation** | .NET CancellationToken, Go context.Context |
| Thread Tracking | **Thread Pool** (simplified) | Patterns of Distributed Systems |
| Custom Mixin | **Brand Predicate** | Tea-specific (duck typing + identification) |

---

## Migration Path

### From Existing Code

Existing built-in commands (`Command::System`, `Command::Mapped`) continue to work unchanged. Custom commands are additive.

### For New Commands

1. Include `Tea::Command::Custom`
2. Implement `#call(out, token)`
3. Override `#tea_cancellation_grace_period` if needed

---

## Open Questions (For Future Consideration)

1. **Message-based cancellation**: Should cancellation be triggered via update function returning a special value, rather than direct runtime API?

2. **Command IDs**: Should command IDs be exposed to the update function for tracking?

3. **Error propagation**: Should `out.put(:command_error, ...)` be automatic, or left to the command?

4. **Completion signal**: Should we add `out.complete` as syntactic sugar for `out.put(:complete)`?

---

## Appendix: Prior Art

This design synthesizes patterns, publications, and implementations from multiple sources.

---

### Design Patterns

| Component | Pattern | Source |
|-----------|---------|--------|
| **Outlet** | Messaging Gateway | Enterprise Integration Patterns (Hohpe & Woolf) |
| **Outlet** | Facade | Design Patterns (GoF) |
| **Outlet** | Channel Adapter | Enterprise Integration Patterns |
| **Outlet** | Message Translator | Enterprise Integration Patterns |
| **CancellationToken** | Cooperative Cancellation | .NET Framework, Go context.Context |
| **Thread Tracking** | Thread Pool (simplified) | Patterns of Distributed Systems (Joshi) |
| **Queue** | Point-to-Point Channel | Enterprise Integration Patterns |
| **Queue** | Message Queue | Enterprise Integration Patterns |
| **Custom Mixin** | Command | Design Patterns (GoF) |
| **Runtime** | Mediator | Design Patterns (GoF) |
| **Update Function** | State | Design Patterns (GoF) |
| **tea_command?** | Brand Predicate | Tea-specific pattern |

---

### Publications

1. **Gamma, Helm, Johnson, Vlissides** (1994). *Design Patterns: Elements of Reusable Object-Oriented Software*. Addison-Wesley.
   - Command, Facade, Mediator, State patterns

2. **Fowler, M.** (2002). *Patterns of Enterprise Application Architecture*. Addison-Wesley.
   - Gateway pattern

3. **Hohpe, G. & Woolf, B.** (2003). *Enterprise Integration Patterns*. Addison-Wesley.
   - Messaging Gateway, Message Channel, Point-to-Point Channel, Channel Adapter

4. **Erl, T.** (2009). *SOA Design Patterns*. Prentice Hall.
   - Asynchronous Queuing, Service Messaging

5. **Daigneau, R.** (2011). *Service Design Patterns*. Addison-Wesley.
   - Service Gateway

6. **Joshi, U.** (2023). *Patterns of Distributed Systems*. Addison-Wesley.
   - Write-Ahead Log, Thread Pool

---

### TEA Implementations

| Framework | Language | Relevance |
|-----------|----------|-----------|
| **Elm** | Elm | Original TEA; Cmd + Sub primitives |
| **BubbleTea** | Go | TUI TEA; "Subscriptions are Loops" philosophy |
| **Iced** | Rust | GUI TEA with Command + Subscription |
| **Miso** | Haskell | Web TEA with Effect + Sub |
| **Bolero** | F# | Web TEA with Cmd + Sub |

---

### Redux Ecosystem

| Library | Pattern | Mapping |
|---------|---------|---------|
| **Redux Thunk** | Raw dispatch access | Option 1 (Raw Queue) |
| **Redux Saga** | `put()` effect dispatches actions | **Option 2 (Outlet)** ← adopted |
| **Redux Observable** | RxJS Observables | Option -2 (RxRuby) |
| **redux-loop** | Elm-style Cmd | Option 0 (Recursive) |

Redux Saga's `put()` is the direct inspiration for `out.put()`.

---

### Cancellation Patterns

| Platform | Mechanism | Relationship |
|----------|-----------|--------------|
| **.NET** | `CancellationToken` | Direct inspiration |
| **Go** | `context.Context` | Cooperative cancellation with `ctx.Done()` |
| **JavaScript** | `AbortController` | Web Fetch API cancellation |
| **Java** | `Thread.interrupt()` | Flag-based cooperative cancellation |
| **Kotlin** | `Job.cancel()` | Coroutine cancellation |

---

### ReactiveX Family

| Library | Language | Relationship |
|---------|----------|--------------|
| **RxJS** | JavaScript | Full reactive; Angular moved away from for state |
| **RxJava** | Java | Full reactive |
| **RxRuby** | Ruby | Option -2 (rejected for complexity/maintenance) |
| **TC39 Signals** | JavaScript (proposed) | Different abstraction (reactive values, not effects) |

---

### Ruby Ecosystem

| Library | Pattern | Relationship |
|---------|---------|--------------|
| **Observable** (stdlib) | Observer pattern | Similar push semantics, lacks thread-safety |
| **Concurrent Ruby** | Actor, Promises | More complex than needed |
| **Celluloid** | Actor mailboxes | Inspiration for "mailbox" terminology |
| **Sidekiq** | Background jobs | Similar "fire command, receive result" model |
| **ActionMailer** | Delivery abstraction | Inspiration for "deliver" terminology (rejected) |

---

### Key Influences

| Influence | What We Took |
|-----------|--------------|
| **Elm** | MVU architecture, Cmd/Msg pattern |
| **BubbleTea** | "Subscriptions are Loops" philosophy |
| **Redux Saga** | `put()` for message dispatch |
| **.NET CancellationToken** | Cooperative cancellation with grace periods |
| **EIP Messaging Gateway** | Outlet as infrastructure abstraction |
| **Go context.Context** | Cancellation propagation pattern |

---

### Further Reading

- [queue-mailbox-draft.md](./queue-mailbox-draft.md) — Full analysis of 8 messaging options
- [command-plugin-draft.md](./command-plugin-draft.md) — Command identification proposals
- [Elm Guide: Commands](https://guide.elm-lang.org/effects/commands.html)
- [BubbleTea Tutorials](https://github.com/charmbracelet/bubbletea)
- [Redux Saga Documentation](https://redux-saga.js.org/)
- [Enterprise Integration Patterns (online)](https://www.enterpriseintegrationpatterns.com/)

---

## Appendix: Implementation Roadmap

This specification can be implemented in four discrete, independently-testable units. Each builds on the previous.

### Unit 1: CancellationToken

**Scope**: `Command::CancellationToken` class + `NONE` constant

| Criteria | Assessment |
|----------|------------|
| Self-contained | ✅ No dependencies on other new abstractions |
| Independently testable | ✅ Pure Ruby, no TUI/Runtime needed |
| Required by later units | ✅ Runtime dispatch and `cancel_command` need it |
| Surface area | 3 methods (`initialize`, `cancel!`, `cancelled?`) + 1 constant (`NONE`) |

---

### Unit 2: Command::Custom Mixin

**Scope**: `Command::Custom` module with brand predicate and grace period

| Criteria | Assessment |
|----------|------------|
| Self-contained | ✅ Module with default implementations |
| Independently testable | ✅ Include in test class, verify behavior |
| Required by later units | ✅ Runtime's `custom_command?` check needs it |
| Surface area | 2 methods (`tea_command?`, `tea_cancellation_grace_period`) |

---

### Unit 3: Outlet

**Scope**: `Command::Outlet` messaging gateway

| Criteria | Assessment |
|----------|------------|
| Self-contained | ✅ Wraps Queue, validates shareability |
| Independently testable | ✅ Pass mock queue, verify `put` behavior |
| Required by later units | ✅ Runtime creates Outlet for custom dispatch |
| Surface area | 2 methods (`initialize`, `put`) |

---

### Unit 4: Runtime Custom Dispatch

**Scope**: Integration into `Runtime.run`

| Criteria | Assessment |
|----------|------------|
| Depends on | Units 1–3 |
| Changes | Add `@active_commands`, extend `dispatch`, add `cancel_command`, add `shutdown` |
| Testable | ✅ Full integration tests with custom commands |

**Sub-tasks**:
1. Add `custom_command?` detection to `valid_command?`
2. Add `dispatch_custom` case to `dispatch`
3. Add thread tracking (`@active_commands`)
4. Add `cancel_command(id)` method
5. Add `shutdown` method for app exit

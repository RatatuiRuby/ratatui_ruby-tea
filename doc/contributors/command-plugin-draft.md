<!--
SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Command Plugin Architecture Proposals

> **Context**: The wiki states that "Specialized clients (WebSockets, gRPC) can be wrapped using the same pattern" as the built-in commands. However, there is currently no easy or obvious way for app developers or third-party library authors to create custom commands. This document proposes several architectural approaches, evaluated through the lens of Rubyist philosophy.

---

## The Problem

The current Tea runtime recognizes commands via a closed `case-when` switch in `Runtime.dispatch`:

```ruby
case command
when Command::System
  Thread.new { ... }
when Command::Mapped
  Thread.new { ... }
end
```

Adding a new command type (like `Command.websocket` or `Command.grpc`) requires modifying the core library. This is:

- **Closed** — Third parties cannot extend without forking
- **Monolithic** — All command logic lives in one method
- **Anti-Ruby** — Violates the Open/Closed Principle and duck-typing traditions

---

## Design Principles (Rubyist Alignment)

These proposals are guided by the `/rubyist` workflow:

| Principle | Source | Application |
|-----------|--------|-------------|
| **Programmer Happiness** | Matz | Commands should be joyful to write and read |
| **TIMTOWTDI** | Perl/Ruby roots | Multiple valid patterns, not one "right way" |
| **DWIM** | Perl roots | Convention over configuration; "just works" |
| **Duck Typing** | Smalltalk/Ruby | Interface over inheritance; `respond_to?` not `is_a?` |
| **Pure OOP** | Smalltalk roots | Objects encapsulate behavior, not just data |
| **Omakase** | DHH/Rails | Curated defaults with escape hatches |
| **SOLID** | Robert C. Martin | Open/Closed Principle especially |
| **Eloquent Ruby** | Russ Olsen | Clear, readable, intention-revealing code |
| **POODR** | Sandi Metz | Composition over inheritance; dependency injection |

---

## Proposal A: Branded Duck-Typed Commands (Recommended)

> **Philosophy**: Duck Typing meets Ecosystem Branding. "Quack like a command, declare yourself a command."

### The Problem: Update Return Disambiguation

The Tea runtime's `normalize_update_result` must distinguish between:

1. `[model, command]` tuples
2. Plain model returns
3. Command-only returns
4. `nil` (no-op)

The current heuristic uses namespace checking:

```ruby
def self.valid_command?(value)
  value.nil? || value.class.name&.start_with?("RatatuiRuby::Tea::Command::")
end
```

This **breaks** for custom commands defined outside the `RatatuiRuby::Tea::Command::` namespace.

### Design: The Branded Predicate Pattern

Custom commands self-identify via a `tea_command?` predicate. The `Command::Custom` mixin provides this brand automatically, but pure duck-typing also works.

```ruby
# sig/ratatui_ruby/tea/command.rbs
interface _Command
  # Execute the command's side effect.
  # Push result messages to the queue.
  def call: (Queue[untyped] queue) -> void
  
  # Brand predicate: identifies this object as a Tea command.
  # Required for update return disambiguation.
  def tea_command?: () -> true
end
```

The mixin provides both the brand and conveniences:

```ruby
module RatatuiRuby::Tea::Command
  # Include this module to identify your class as a Tea command.
  # Provides the required `tea_command?` brand and helper methods.
  module Custom
    # Brand predicate for update return disambiguation.
    def tea_command? = true

    # Convenience: Ractor-safe message push
    def push(queue, tag, *payload)
      queue << Ractor.make_shareable([tag, *payload])
    end
  end
end
```

### Implementation (Runtime)

Two changes are required:

**1. Update `valid_command?` to recognize branded commands:**

```ruby
private_class_method def self.valid_command?(value)
  return true if value.nil?
  return true if value.class.name&.start_with?("RatatuiRuby::Tea::Command::")
  
  # NEW: Branded custom commands
  value.respond_to?(:tea_command?) && value.tea_command?
end
```

**2. Update `dispatch` to execute custom commands:**

```ruby
private_class_method def self.dispatch(command, queue)
  case command
  when Command::System
    # ... existing logic
  when Command::Mapped
    # ... existing logic
  else
    # NEW: Duck-typed custom commands with brand
    if command.respond_to?(:call) && command.respond_to?(:tea_command?)
      Thread.new { command.call(queue) }
    end
  end
end
```

### App Developer Usage

**Option 1: With Mixin (Recommended)**

```ruby
class WebSocketCommand
  include RatatuiRuby::Tea::Command::Custom

  def initialize(url, tag)
    @url = url
    @tag = tag
  end

  def call(queue)
    ws = WebSocket::Client.new(@url)
    ws.on_message do |msg|
      push(queue, @tag, :message, msg)  # Convenience helper
    end
    ws.connect
  end
end

# In update function
[model, WebSocketCommand.new("wss://example.com", :ws)]
```

**Option 2: Pure Duck Typing (No Mixin)**

```ruby
class WebSocketCommand
  def initialize(url, tag)
    @url = url
    @tag = tag
  end

  # Brand predicate (required for disambiguation)
  def tea_command? = true

  def call(queue)
    ws = WebSocket::Client.new(@url)
    ws.on_message do |msg|
      queue << Ractor.make_shareable([@tag, :message, msg])
    end
    ws.connect
  end
end
```

**Option 3: Factory Module Pattern**

```ruby
module MyApp::Command
  class Websocket
    include RatatuiRuby::Tea::Command::Custom
    
    def initialize(url:, tag:)
      @url = url
      @tag = tag
    end

    def call(queue)
      # ... implementation
    end
  end

  def self.websocket(url, tag)
    Websocket.new(url:, tag:)
  end
end

# In update function
[model, MyApp::Command.websocket("wss://example.com", :ws)]
```

### Ecosystem Future-Proofing

The brand pattern enables future compatibility with other RatatuiRuby runtimes:

```ruby
# Hypothetical Kit command (future)
class MyKitCommand
  def kit_command? = true  # Different brand for different runtime
  def call(context)
    # ...
  end
end

# Runtime can check which ecosystem owns the command
def self.valid_command?(value)
  value.respond_to?(:tea_command?) && value.tea_command?
end

# Kit would check:
def self.valid_command?(value)
  value.respond_to?(:kit_command?) && value.kit_command?
end
```

This separation prevents cross-runtime confusion when sharing code across Tea and Kit applications.

### Pros

- **Backward Compatible** — Built-in commands unchanged
- **Rubyist** — Duck-typed with explicit opt-in brand
- **Testable** — Commands are plain objects
- **Composable** — Works with `Command.map`
- **Discoverable** — `include Command::Custom` is self-documenting
- **Future-Proof** — Brand pattern scales to Kit and other runtimes

### Cons

- **Requires Brand** — Pure `#call` objects need `tea_command?` method
- **Slight Ceremony** — One extra method vs pure duck typing

### Verdict

**Best for**: Production applications. Recommended as the core primitive with `Command::Custom` mixin for convenience.

---

## Proposal B: Registrable Command Handlers

> **Philosophy**: Rails-style Omakase. "Built-in commands for common cases, extension points for edge cases."

### Design

A registry maps command classes to handler procs. Third parties register handlers.

```ruby
module RatatuiRuby::Tea
  module Command
    class << self
      def handlers
        @handlers ||= {}
      end

      def register(command_class, &handler)
        handlers[command_class] = handler
      end
    end
  end
end
```

### Built-in Registration

```ruby
# In lib/ratatui_ruby/tea/command.rb
Command.register(Command::System) do |command, queue|
  require "open3"
  # ... existing logic
end
```

### App/Library Developer Usage

```ruby
# Define the command type
module MyApp::Command
  Websocket = Data.define(:url, :tag)

  def self.websocket(url, tag)
    Websocket.new(url:, tag:)
  end
end

# Register the handler (e.g., in a Railtie or initializer)
RatatuiRuby::Tea::Command.register(MyApp::Command::Websocket) do |cmd, queue|
  ws = WebSocket::Client.new(cmd.url)
  ws.on_message { |msg| queue << Ractor.make_shareable([cmd.tag, :message, msg]) }
  ws.connect
end
```

### Runtime Implementation

```ruby
def self.dispatch(command, queue)
  handler = Command.handlers[command.class]
  if handler
    Thread.new { handler.call(command, queue) }
  else
    raise RatatuiRuby::Error::Invariant,
      "No handler registered for #{command.class}. Use Command.register."
  end
end
```

### Pros

- **Discoverable** — Clear registration API
- **Structured** — `Data.define` commands are self-documenting
- **Omakase** — Built-in commands bundled; extensions opt-in
- **Framework-Friendly** — Libraries can ship handlers (gems)

### Cons

- **Global State** — Registry is mutable; ordering concerns
- **Boot-Time Coupling** — Handlers must be registered before use
- **Class-Based** — Less flexible than duck-typing

### Verdict

**Best for**: Library authors shipping command gems.

---

## Proposal C: Module Mixin (`Command::Custom`)

> **Philosophy**: POODR-style composition. "Include behavior, don't inherit it."

### Design

A mixin provides the contract and conveniences. Include it and implement `#execute`.

```ruby
module RatatuiRuby::Tea::Command
  module Custom
    # Subclasses implement this
    def execute(queue)
      raise NotImplementedError, "#{self.class} must implement #execute"
    end

    # Convenience: Ractor-safe message push
    def push(queue, tag, *payload)
      queue << Ractor.make_shareable([tag, *payload])
    end
  end
end
```

### App Developer Usage

```ruby
class WebSocketCommand
  include RatatuiRuby::Tea::Command::Custom

  def initialize(url, tag)
    @url = url
    @tag = tag
  end

  def execute(queue)
    ws = WebSocket::Client.new(@url)
    ws.on_message { |msg| push(queue, @tag, :message, msg) }
    ws.connect
  end
end
```

### Runtime Check

```ruby
def self.dispatch(command, queue)
  if command.is_a?(Command::Custom)
    Thread.new { command.execute(queue) }
  elsif # ... fallback to built-ins
  end
end
```

### Pros

- **Self-Documenting** — Developers see `include Command::Custom`
- **Conveniences** — `push` helper enforces Ractor safety
- **Testable** — `#execute` is a clear integration point
- **POODR** — Composition over inheritance

### Cons

- **Slightly Coupled** — Requires `include` (not pure duck-typing)
- **Mixin Overload** — Another module to learn

### Verdict

**Best for**: Teams wanting structure without classes.

---

## Proposal D: Proc-Based Commands (Closure Capture)

> **Philosophy**: "Just Ruby." Lambdas are the simplest abstraction.

### Design

Commands can be procs accepting `queue`. The runtime invokes them directly.

```ruby
# Any callable accepting (queue) is a command
websocket_cmd = ->(queue) do
  ws = WebSocket::Client.new("wss://example.com")
  ws.on_message { |msg| queue << Ractor.make_shareable([:ws, :message, msg]) }
  ws.connect
end

[model, websocket_cmd]
```

### Runtime Implementation

```ruby
def self.dispatch(command, queue)
  case command
  when Proc
    Thread.new { command.call(queue) }
  when Command::System
    # ... existing
  end
end
```

### Pros

- **Zero Ceremony** — No classes, no registration
- **Inline Flexibility** — Define in `update` directly
- **TIMTOWTDI** — Alternative to object commands

### Cons

-  **Ractor Safety Concern** — Blocks capturing `self` are not shareable
   - **Mitigation**: Runtime executes in Thread (same process), so captures work
- **No Reuse** — Logic duplicated if same command used in multiple places
- **No Introspection** — Can't pattern-match on proc "type"

### Verdict

**Best for**: Quick one-off side effects. Not recommended as primary API.

---

## Proposal E: Protocol (RBS Interface + Duck Typing)

> **Philosophy**: Static typing for library authors, duck typing for app developers.

### Design

Define the `_Command` interface in RBS. Runtime uses `respond_to?` at runtime but Steep validates types at development time.

```ruby
# sig/ratatui_ruby/tea/command.rbs
interface _Command
  def call: (Queue[untyped] queue) -> Thread
end

type execution = _Command | System | Mapped | Exit | nil
```

### Runtime

```ruby
def self.dispatch(command, queue)
  return command.call(queue) if command.respond_to?(:call)
  # ... fallback for legacy types
end
```

### Library Author Experience

```ruby
# Steep catches this at development time:
class BadCommand
  def execute(queue) # Wrong method name!
  end
end
```

### App Developer Experience

No change from Proposal A—duck typing "just works."

### Pros

- **Best of Both Worlds** — Type safety for library authors, flexibility for app developers
- **Gradual Typing** — Opt-in strictness
- **RBS Ecosystem** — Aligns with existing `sig/` conventions

### Cons

- **Steep Dependency** — Only useful if developers run `steep check`
- **RBS Learning Curve** — Interface definitions are advanced

### Verdict

**Best for**: Ecosystem maturity. Combine with Proposal A as the implementation.

---

## Proposal F: Inheritance (`Command::Base`)

> **Philosophy**: Traditional OOP. Clear hierarchy for those who want it.

### Design

An abstract base class provides threading, error handling, and lifecycle hooks.

```ruby
module RatatuiRuby::Tea
  class Command::Base
    def initialize(tag)
      @tag = tag
    end

    # Subclasses implement this
    def perform(queue)
      raise NotImplementedError
    end

    # Runtime calls this
    def call(queue)
      perform(queue)
    rescue => e
      queue << Ractor.make_shareable([@tag, :error, { message: e.message }])
    end
  end
end
```

### App Developer Usage

```ruby
class WebSocketCommand < RatatuiRuby::Tea::Command::Base
  def initialize(url, tag)
    super(tag)
    @url = url
  end

  def perform(queue)
    ws = WebSocket::Client.new(@url)
    ws.on_message { |msg| push(queue, :message, msg) }
    ws.connect
  end

  private

  def push(queue, *payload)
    queue << Ractor.make_shareable([@tag, *payload])
  end
end
```

### Pros

- **Error Handling Built-In** — Rescue wraps `perform`
- **Familiar Pattern** — Rails developers know `ActiveJob::Base`
- **Lifecycle Hooks** — Easy to add `before_perform`, `after_perform`

### Cons

- **Inheritance Tax** — Tight coupling to base class
- **Anti-Rubyist** — Duck typing is preferred over `is_a?`
- **Inflexible** — Single inheritance limits composition

### Verdict

**Best for**: Teams from Rails/Java backgrounds. Not recommended as primary API.

---

## Synthesis: The Layered Architecture

> **Recommended Approach**: Combine proposals for different audiences.

```
┌─────────────────────────────────────────────────────────────────┐
│                     App Developer (Simple)                      │
│  Use built-in commands: Command.system, Command.http, etc.      │
└─────────────────────────────────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                   App Developer (Advanced)                      │
│  Write Proc commands: ->(queue) { ... }                         │
│  Or callable objects: MyCommand.new(...) with #call(queue)      │
└─────────────────────────────────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Library Author                             │
│  Define Data.define commands + register handler                 │
│  Or include Command::Custom mixin                           │
│  Ship as gem: ratatui_ruby-websocket                            │
└─────────────────────────────────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                         RBS/Steep                               │
│  Type-safe interface: _Command with #call                       │
│  Validated at development time via steep check                  │
└─────────────────────────────────────────────────────────────────┘
```

### Implementation Phases

1. **Phase 1 (MVP)**: Proposal A — Duck-typed `#call(queue)`
   - Minimal change to `Runtime.dispatch`
   - Enables all other patterns
   - Document in wiki as "Custom Commands"

2. **Phase 2 (Convenience)**: Proposal C — `Command::Custom` mixin
   - Provides `push` helper for Ractor safety
   - Optional adoption

3. **Phase 3 (Ecosystem)**: Proposal B — Registry for gem authors
   - Enables `ratatui_ruby-websocket`, `ratatui_ruby-grpc` gems
   - Discoverable via `Command.handlers.keys`

4. **Phase 4 (Type Safety)**: Proposal E — RBS interface
   - Formalize `_Command` in `sig/`
   - Steep validates library implementations

---

## The Recommended Implementation

Given the Rubyist principles, I recommend **Proposal A (Branded Duck-Typed)** as the foundation, with `Command::Custom` as the convenience mixin.

### Runtime Changes Required

**1. Update `valid_command?` for disambiguation:**

```ruby
private_class_method def self.valid_command?(value)
  return true if value.nil?
  return true if value.class.name&.start_with?("RatatuiRuby::Tea::Command::")
  
  # NEW: Branded custom commands
  value.respond_to?(:tea_command?) && value.tea_command?
end
```

**2. Update `dispatch` to execute custom commands:**

```ruby
private_class_method def self.dispatch(command, queue)
  case command
  # Existing built-ins (unchanged)
  when Command::System
    # ... existing logic
  when Command::Mapped
    # ... existing logic
  else
    # NEW: Duck-typed custom commands with brand
    if command.respond_to?(:call) && command.respond_to?(:tea_command?)
      Thread.new { command.call(queue) }
    end
  end
end
```

### The Mixin

```ruby
module RatatuiRuby::Tea::Command
  # Include this module to create custom commands.
  # Provides the required brand and convenience helpers.
  module Custom
    # Brand predicate for update return disambiguation.
    def tea_command? = true

    # Push a Ractor-safe message to the queue.
    def push(queue, tag, *payload)
      queue << Ractor.make_shareable([tag, *payload])
    end
  end
end
```

### Documentation Example

```ruby
# == Custom Commands
#
# Any object with <tt>#call(queue)</tt> and <tt>#tea_command?</tt> is a command.
# The runtime spawns a thread and invokes your method.
#
# === Example: WebSocket Subscription
#
#   class WebSocketCommand
#     include RatatuiRuby::Tea::Command::Custom
#
#     def initialize(url, tag)
#       @url = url
#       @tag = tag
#     end
#
#     def call(queue)
#       ws = WebSocket::Client.new(@url)
#       ws.on_message { |msg| push(queue, @tag, :message, msg) }
#       ws.connect
#     end
#   end
#
#   # In your update function:
#   [model, WebSocketCommand.new("wss://api.example.com", :prices)]
```

---

## Open Questions

1. **Thread vs Fiber**: Should custom commands support non-threaded execution (e.g., Async gem)?

2. **Cancellation**: How does a long-running command (WebSocket) get cancelled when the app exits?

3. **Error Propagation**: Should the runtime rescue errors and wrap them in `[:tag, :error, {...}]`?

4. **Ractor Future**: When Ractors are production-ready, how do callable commands adapt?

5. **Testing Helpers**: Should `with_test_terminal` provide a fake queue for command testing?

---

## Appendix: Command Type Reference

| Type | Built-in? | Pattern | When to Use |
|------|-----------|---------|-------------|
| `Command.exit` | ✓ | Sentinel | Terminate application |
| `Command.system` | ✓ | Data + dispatch | Shell commands |
| `Command.map` | ✓ | Wrapper | Fractal routing |
| `Command.http` | ✓ (planned) | Data + dispatch | HTTP requests |
| `Command.wait` | ✓ (planned) | Data + dispatch | One-shot timers |
| `Command.tick` | ✓ (planned) | Recursive | Recurring timers |
| Custom callable | ✗ | Duck-typed | WebSocket, gRPC, etc. |
| Custom + mixin | ✗ | Include | Structured custom commands |
| Custom + registry | ✗ | Register | Gem-distributed commands |

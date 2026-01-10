<!--
SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Queue vs Outlet: Custom Command Message Passing

> **Context**: Custom commands need to send messages back to the Tea runtime's update loop. Should we expose the raw `Queue` or wrap it in a `Tea::Outlet` abstraction?

---

## Background: How Messages Flow Today

The Tea runtime uses a `Thread::Queue` internally:

```ruby
# In Runtime.run
queue = Queue.new

# In Runtime.dispatch (for Command::System)
Thread.new do
  stdout, stderr, status = Open3.capture3(command.command)
  message = [command.tag, { stdout:, stderr:, status: status.exitstatus }]
  queue << Ractor.make_shareable(message)
end

# Back in Runtime.run
until queue.empty?
  background_message = queue.pop
  model, command = update.call(background_message, model)
end
```

The queue is the **outlet** between worker threads and the main event loop. It's an implementation detail—not documented in the wiki, emerged from real need during async implementation.

---

## The Question

For custom commands, should we:

1. **Pass the raw `Queue`** — `def call(queue)`
2. **Wrap it in `Tea::Outlet`** — `def call(out)`
3. **Use a different pattern entirely** — Return values, Enumerators, etc.

---

## Option -2: RxRuby (Reactive Extensions)

> **Philosophy**: Full reactive streams library with operators, schedulers, and composition.

[RxRuby](https://github.com/ReactiveX/RxRuby) is the Ruby implementation of ReactiveX (same family as RxJS, RxJava, Rx.NET). It provides a complete solution for observable streams with rich operator support.

### How It Would Work

```ruby
# Commands return Observables instead of single values
class WebSocketCommand
  def call
    Rx::Observable.create do |observer|
      ws = WebSocket::Client.new(@url)
      ws.on_message { |msg| observer.on_next([:ws, :message, msg]) }
      ws.on_close { observer.on_completed }
      ws.on_error { |e| observer.on_error(e) }
      ws.connect
      
      # Return disposal logic
      Rx::Subscription.create { ws.close }
    end
  end
end

# Runtime subscribes to the Observable
observable = command.call
subscription = observable.subscribe(
  ->(msg) { queue << Ractor.make_shareable(msg) },  # on_next
  ->(err) { queue << [:error, err.message] },        # on_error
  -> { queue << [:complete] }                        # on_completed
)

# Cancellation is built-in
subscription.unsubscribe
```

### Rich Operator Support

RxRuby includes the full ReactiveX operator library:

```ruby
# Debounce, throttle, retry, combine streams
websocket_observable
  .select { |msg| msg[:type] == :price }
  .map { |msg| [:price_update, msg[:value]] }
  .debounce(0.5)  # Don't flood update loop
  .retry(3)       # Auto-retry on error
  .subscribe { |msg| queue << msg }
```

### Scenario Coverage

**Simple Synchronous** ✅

```ruby
Rx::Observable.just([:done, result])
```

**Long-Lived Blocking** ✅

```ruby
Rx::Observable.create do |observer|
  # Blocking code in scheduler
  result = blocking_operation
  observer.on_next(result)
  observer.on_completed
end
```

**Long-Lived Non-Blocking** ✅

```ruby
Rx::Observable.create do |observer|
  ws.on_message { |msg| observer.on_next(msg) }
  ws.connect
  Rx::Subscription.create { ws.close }
end
```

**Cancellation** ✅

```ruby
subscription = observable.subscribe(...)
subscription.unsubscribe  # Clean teardown, runs disposal logic
```

### Why This Wasn't Chosen

1. **External Dependency** — Tea's "batteries included" philosophy uses stdlib only
2. **Learning Curve** — ReactiveX has 100+ operators; steep for simple use cases
3. **Overkill** — Most Tea apps don't need `debounce`, `retry`, `combineLatest`, etc.
4. **Ruby Adoption** — RxRuby is less popular than RxJS/RxJava; smaller ecosystem
5. **Maintenance** — RxRuby shows signs of low activity (last release 2016)

### Trade-off Analysis

| Aspect | RxRuby | Tea Outlet |
|--------|--------|------------|
| Operator library | ✅ 100+ operators | ✗ Just `map` |
| Cancellation | ✅ Built-in unsubscribe | ⚠️ Manual |
| Error handling | ✅ `on_error` + `retry` | ⚠️ Manual |
| Backpressure | ✅ Operators for this | ✗ Unbounded queue |
| Learning curve | ✗ Steep | ✅ Minimal |
| Dependencies | ✗ External gem | ✅ None |
| Maintenance | ⚠️ Unclear future | ✅ You control it |

### When RxRuby Makes Sense

- Complex stream transformations (merge, zip, combineLatest)
- Retry/backoff patterns needed
- Team already knows ReactiveX from Angular/RxJS
- Building a reactive data pipeline, not just TUI

### Relevance to Current Discussion

RxRuby represents the **maximum power** end of the spectrum. If Tea apps need full reactive semantics, users can integrate RxRuby themselves:

```ruby
class RxCommand
  include RatatuiRuby::Tea::Command::Custom

  def call(out)
    @observable.subscribe(
      ->(msg) { out.put(*msg) },
      ->(err) { out.put(:error, message: err.message) },
      -> { out.put(:complete) }
    )
  end
end
```

The Outlet becomes the bridge between RxRuby's world and Tea's update loop.

---

## Option -1: Subscriptions (Cut Pre-Pizza Summit)

> **Philosophy**: First-class runtime primitive for long-lived event streams.

Before the Pizza Summit, multiple ecosystem drafts proposed a **Subscription** primitive alongside Commands. This was cut in favor of "Recursive Commands" to reduce API surface.

### The Original Design

```ruby
# Jujube proposal (1FD9EF8A)
RatatuiRuby::TEA::Program.new(
  model: initial_state,
  update: ->(msg, model) { ... },
  view: ->(model) { ... },
  subscriptions: ->(model) { ... }  # NEW: Fourth parameter
)
```

The `subscriptions` function would be called after each update, returning which subscriptions should be active based on current model state.

### Proposed Sub Primitives

Different drafts proposed slightly different APIs:

**Jujube (1FD9EF8A):**
```ruby
Sub.batch([sub1, sub2])
Sub.on_resize(MsgClass)
Sub.every(interval, MsgClass)
```

**Gold Master (CFA475A7):**
> "A long-lived listener (Timer, Socket). The Runtime spawns a dedicated thread that pushes messages into the main queue indefinitely."

**Directory structure included:**
```
lib/ratatui_ruby/tea/
├── sub.rb            # Subscription primitives
```

### How It Would Work

1. After each update, runtime calls `subscriptions(model)`
2. Runtime **diffs** returned subs against currently active subs
3. New subs: spawn dedicated thread
4. Removed subs: kill thread
5. Unchanged subs: keep running

```ruby
# Hypothetical usage
def subscriptions(model)
  subs = []
  subs << Sub.every(1, :tick) if model.timer_enabled
  subs << Sub.websocket(model.ws_url, :ws_msg) if model.connected
  Sub.batch(subs)
end
```

### Scenario Coverage

**Simple Synchronous** — N/A (Subscriptions are for long-lived streams; use Commands for one-shot work)

**Long-Lived Blocking** ✅

```ruby
# Hypothetical: blocking socket read in a Sub thread
Sub.tcp_server(port, :client_msg)  # Thread blocks on accept/read
```

Runtime spawns dedicated thread that blocks; messages pushed when events occur.

**Long-Lived Non-Blocking** ✅

```ruby
Sub.websocket(url, :ws_msg)  # Runtime manages async connection
Sub.every(1, :tick)           # Runtime manages timer
```

**Cancellation** ✅

```ruby
# Runtime diffs: if Sub disappears from return value, thread is killed
def subscriptions(model)
  model.timer_enabled ? Sub.every(1, :tick) : Sub.none
end
```

Cancellation is automatic via diffing—no user code needed to stop subscriptions.

### Why It Was Cut (Pizza Summit)

1. **API Complexity** — Fourth parameter, new primitive type, diffing logic
2. **"Just Ruby" Pivot** — Commands are Procs, Batches are Arrays, Subscriptions are Loops
3. **Runtime Complexity** — Subscription diffing, lifecycle management, thread tracking
4. **Edge Cases** — What if subscription changes mid-update? Race conditions?

### Trade-off Analysis

| Aspect | Subscriptions | Recursive Commands |
|--------|---------------|-------------------|
| API Surface | Higher (new primitive) | Lower (reuses Commands) |
| Runtime Complexity | Higher (diffing) | Lower (fire-and-forget) |
| Long-lived Streams | ✅ First-class support | ❌ Awkward/impossible |
| Cancellation | ✅ Automatic via diff | ✅ Manual via update logic |
| WebSocket/gRPC | ✅ Natural fit | ❌ Doesn't fit pattern |

### Relevance to Current Discussion

Option -1 (Subscriptions) sits between **Option -2 (RxRuby)** and the simpler options:

| Approach | Abstraction Level | Lifecycle Management |
|----------|-------------------|---------------------|
| **-2 RxRuby** | High (full reactive) | User via `unsubscribe` |
| **-1 Subscriptions** | Medium (declarative) | **Runtime via diffing** |
| **0-2 Outlet/Queue** | Low (imperative) | User via convention |

The **Outlet** proposal (Options 1-2) partially re-introduces Subscription semantics:
- Both solve "command produces many messages over time"
- But Outlet puts lifecycle management on the **user**, not the runtime
- RxRuby provides full Rx operators but with external dependency and steep learning curve
- Subscriptions were an **abstraction**; Outlet is a **mechanism**

If the Pizza Summit had chosen Subscriptions, we wouldn't need this document—long-lived streams would be first-class. The choice to cut them created the gap we're now filling with Outlet.

---

## Option 0: Recursive Commands (Status Quo)

> **Philosophy**: "Subscriptions are just Loops." — Pizza Summit Decision

The current Tea architecture has no special mechanism for long-lived streams. Instead, the **Recursive Command** pattern handles timers, polling, and subscriptions:

```ruby
# A "tick" command that fires every second
def update(msg, model)
  case msg
  in [:tick, time]
    new_model = model.with(last_tick: time)
    [new_model, Command.wait(1, :tick)]  # Fire the same command again
  in :stop_ticking
    [model, nil]  # Stop by not returning the command
  end
end
```

### How It Works

1. Command executes, returns a message (e.g., `[:tick, Time.now]`)
2. Runtime pushes message to update loop
3. Update handler receives message
4. Update handler **decides** whether to return the same command again
5. If yes: loop continues. If no: loop stops.

### Scenario Coverage

**Simple Synchronous** ✅

```ruby
# One-shot command - no recursion needed
[model, Command.system("ls", :got_files)]
```

**Long-Lived Blocking** ⚠️ (Partial)

```ruby
# Blocking commands work, but only return ONE message
# E.g., a long-running shell command that blocks
[model, Command.system("sleep 60 && echo done", :finished)]
```

The command blocks in its thread, but can only return a single message when complete. Not suitable for commands that need to send messages *while* blocking.

**Long-Lived Non-Blocking** ❌

This is where Recursive Commands **break down**:

```ruby
# WebSocket - command returns ONCE, but we need MANY messages over time
# How does the WebSocket keep sending messages after the first return?
```

A single command return = a single message. WebSockets, gRPC streams, and other long-lived connections need to send **multiple messages** from a single command invocation.

**Cancellation** ✅

```ruby
# Stop by not returning the command
in :stop_ticking
  [model, nil]  # No more ticks
```

### Why This Was Chosen (Pizza Summit Rationale)

1. **Zero API Surface** — No `Sub` primitive needed
2. **Just Ruby** — Commands are Procs, Batches are Arrays, Subscriptions are Loops
3. **Simple Runtime** — No subscription diffing, no lifecycle management

### Why It's Insufficient for Custom Commands

The Recursive Command pattern works for **runtime-controlled** commands where:
- Each "tick" is a separate command invocation
- The update function decides continuation

It **doesn't work** for **user-controlled** long-lived streams where:
- A single command invocation produces many messages over time
- The command (not update) controls when messages are sent
- External events (WebSocket, file watcher) trigger messages

This gap is what Options 1-4 address.

---

## Option 1: Raw `Queue`

```ruby
def call(queue)
  ws = WebSocket::Client.new(@url)
  ws.on_message do |msg|
    queue << Ractor.make_shareable([@tag, :message, msg])
  end
  ws.connect
end
```

### Upsides

| Benefit | Explanation |
|---------|-------------|
| **Zero abstraction** | Developers know `Queue`—it's Ruby stdlib |
| **No coupling** | Commands work outside Tea (testing, other frameworks) |
| **TIMTOWTDI** | Use `push`, `<<`, `enq`—whatever you prefer |
| **Debuggable** | Standard Ruby object, no magic methods |
| **Minimal API surface** | Nothing new to learn |

### Downsides

| Problem | Explanation |
|---------|-------------|
| **Leaky abstraction** | Exposes internal concurrency mechanism |
| **Ractor footgun** | Easy to forget `Ractor.make_shareable` |
| **No validation** | Push malformed messages, get cryptic errors later |
| **Tight coupling** | If runtime changes queue impl, custom commands break |
| **Wrong mental model** | "Queue" is infrastructure, not domain language |

### Scenario Coverage

**Simple Synchronous** ✅

```ruby
def call(queue)
  result = fetch_data
  queue << Ractor.make_shareable([:done, result])
end
```

**Long-Lived Blocking** ✅

```ruby
def call(queue)
  ws = WebSocket::Client.new(@url)
  ws.on_message { |msg| queue << Ractor.make_shareable([:ws, :message, msg]) }
  ws.connect  # Blocks until close
end
```

**Long-Lived Non-Blocking** ✅

```ruby
def call(queue)
  ws = WebSocket::Client.new(@url)
  ws.on_message { |msg| queue << Ractor.make_shareable([:ws, :message, msg]) }
  ws.connect  # Returns immediately
  # Queue is captured in closure—callbacks continue pushing after call returns
end
```

**Cancellation** ✅

```ruby
def call(queue)
  @running = true
  while @running
    queue << Ractor.make_shareable([:tick, Time.now])
    sleep 1
  end
end

def cancel
  @running = false
end
```

---

## Option 2: `Tea::Outlet` Wrapper

```ruby
module RatatuiRuby
  module Tea
    # Thread-safe message delivery to the Tea update loop.
    #
    # Custom commands receive an Outlet instead of a raw Queue. This provides
    # a domain-appropriate API and ensures Ractor-safety.
    #
    # === Example
    #
    #   def call(out)
    #     out.put(:got_data, status: 200, body: "...")
    #   end
    #
    class Outlet
      def initialize(queue)
        @queue = queue
      end

      # Deliver a tagged message to the update loop.
      #
      # The message is automatically made Ractor-shareable (deeply frozen).
      # If freezing fails, raises an error with a helpful diagnostic.
      #
      # [tag] Symbol identifying the message type for pattern matching
      # [payload] Additional message data (will be frozen)
      #
      # === Example
      #
      #   out.put(:user_loaded, id: 42, name: "Alice")
      #   # Produces message: [:user_loaded, {id: 42, name: "Alice"}]
      #
      #   out.put(:stdout_line, "Hello, world!")
      #   # Produces message: [:stdout_line, "Hello, world!"]
      #
      def put(tag, *payload)
        message = payload.size == 1 ? [tag, payload.first] : [tag, *payload]
        @queue << Ractor.make_shareable(message)
      rescue Ractor::IsolationError => e
        raise RatatuiRuby::Error::Invariant,
          "Message payload must be Ractor-shareable. " \
          "Use frozen values or Ractor.make_shareable. " \
          "Original error: #{e.message}"
      end
    end
  end
end
```

### Usage

```ruby
class WebSocketCommand
  include RatatuiRuby::Tea::Command::Custom

  def initialize(url, tag)
    @url = url
    @tag = tag
  end

  def call(out)
    ws = WebSocket::Client.new(@url)
    ws.on_message do |msg|
      out.put(@tag, :message, msg)
    end
    ws.connect
  end
end
```

### Upsides

| Benefit | Explanation |
|---------|-------------|
| **Ractor safety built-in** | `put` always freezes messages |
| **Clear contract** | "Deliver a message" not "push to queue" |
| **Better errors** | Catch `IsolationError` with helpful diagnostics |
| **Extensible** | Add validation, logging, metrics later |
| **Future-proof** | Swap queue implementation without breaking API |
| **Domain language** | "Outlet" aligns with MVU terminology |

### Downsides

| Problem | Explanation |
|---------|-------------|
| **Another abstraction** | Developers must learn `Outlet` API |
| **Less flexible** | Can't use raw queue tricks |
| **Slight overhead** | Extra method call + rescue block (negligible) |
| **Coupling to Tea** | Commands become Tea-specific |

### Scenario Coverage

**Simple Synchronous** ✅

```ruby
def call(out)
  result = fetch_data
  out.put(:done, result)
end
```

**Long-Lived Blocking** ✅

```ruby
def call(out)
  ws = WebSocket::Client.new(@url)
  ws.on_message { |msg| out.put(:ws, :message, msg) }
  ws.connect  # Blocks until close
end
```

**Long-Lived Non-Blocking** ✅

```ruby
def call(out)
  ws = WebSocket::Client.new(@url)
  ws.on_message { |msg| out.put(:ws, :message, msg) }
  ws.connect  # Returns immediately
  # out is captured in closure—callbacks continue putting after call returns
end
```

**Cancellation** ✅

```ruby
def call(out)
  @running = true
  while @running
    out.put(:tick, Time.now)
    sleep 1
  end
end

def cancel
  @running = false
end
```

---

## Option 3: Hybrid (Facade + Escape Hatch)

Provide the abstraction but allow advanced users to access the raw queue:

```ruby
class Tea::Outlet
  def initialize(queue)
    @queue = queue
  end

  # Primary API: safe message delivery
  def put(tag, *payload)
    message = payload.size == 1 ? [tag, payload.first] : [tag, *payload]
    @queue << Ractor.make_shareable(message)
  rescue Ractor::IsolationError => e
    raise RatatuiRuby::Error::Invariant,
      "Message payload must be Ractor-shareable: #{e.message}"
  end

  # Escape hatch for advanced use cases.
  # You are responsible for Ractor-safety!
  #
  # === Example
  #
  #   outlet.raw_queue << Ractor.make_shareable(custom_message)
  #
  attr_reader :raw_queue
end
```

### When Would You Need `raw_queue`?

- Pushing pre-frozen messages (performance optimization)
- Interoperating with other libraries that expect `Queue`
- Testing with mock queues

---

## Option 4: Return-Value Based (Enumerator)

Avoid passing the queue at all. Commands return messages; the runtime handles queuing:

```ruby
class WebSocketCommand
  include RatatuiRuby::Tea::Command::Custom

  def call
    Enumerator.new do |yielder|
      ws = WebSocket::Client.new(@url)
      ws.on_message { |msg| yielder << [@tag, :message, msg] }
      ws.connect
    end
  end
end

# Runtime wraps it:
Thread.new do
  command.call.each { |msg| queue << Ractor.make_shareable(msg) }
end
```

### Upsides

| Benefit | Explanation |
|---------|-------------|
| **No injection** | Commands don't receive external objects |
| **Testable** | Just iterate the Enumerator in tests |
| **Lazy** | Messages generated on demand |

### Downsides

| Problem | Explanation |
|---------|-------------|
| **Complex for streaming** | Enumerator blocks until `each` is called |
| **Less intuitive** | Developers expect to "send" messages, not "yield" |
| **Completion semantics** | How do you signal "done" vs "error"? |
| **Blocking concerns** | What if WebSocket blocks forever? |

### Deep Dive: Long-Lived Streams

The example above works IF `ws.connect` **blocks** until the connection closes. Many Ruby WebSocket libraries are **non-blocking**:

```ruby
def call
  Enumerator.new do |yielder|
    ws = WebSocket::Client.new(@url)
    ws.on_message { |msg| yielder << msg }
    ws.connect  # Returns immediately!
    # ❌ Enumerator block ends before any callbacks fire
  end
end
```

**Workaround**: Bridge with an internal Queue:

```ruby
def call
  Enumerator.new do |yielder|
    internal = Queue.new
    
    ws = WebSocket::Client.new(@url)
    ws.on_message { |msg| internal << [:message, msg] }
    ws.on_close { internal << [:closed] }
    ws.connect
    
    loop do
      event = internal.pop  # Blocks until callback fires
      break if event == [:closed]
      yielder << [:ws, event.first, event.last]
    end
  end
end
```

This works but adds complexity—you're essentially building the Outlet pattern inside the Enumerator.

### Deep Dive: The Cancellation Problem

Enumerators have no built-in cancellation mechanism. With Outlet, checking cancellation is easy:

```ruby
# Outlet pattern - easy cancellation
def call(out)
  loop do
    break if @cancelled
    out.put(:tick, Time.now)
    sleep 1
  end
end

# Enumerator pattern - how to cancel?
def call
  Enumerator.new do |yielder|
    loop do
      # No way to check "should I stop?" without external state
      yielder << [:tick, Time.now]
      sleep 1
    end
  end
end
```

**Possible solution**: Pass a cancellation token:

```ruby
def call(cancel)
  Enumerator.new do |yielder|
    until cancel.cancelled?
      yielder << [:tick, Time.now]
      sleep 1
    end
  end
end
```

But now we're back to passing something in, losing the "pure return" elegance.

---

## Option 5: TC39 Signals (Wrong Abstraction)

> **Philosophy**: Synchronous, pull-based reactive values with automatic dependency tracking.

[TC39 Proposal Signals](https://github.com/tc39/proposal-signals) is a Stage 1 JavaScript proposal that Angular, Vue, Solid, Svelte, Preact, and others are collaborating on. Angular replaced RxJS-heavy patterns with Signals because developers found RxJS's learning curve prohibitive.

### What Signals Are

Signals are **reactive cells**—values that automatically notify dependents when they change:

```javascript
const counter = new Signal.State(0);
const isEven = new Signal.Computed(() => (counter.get() & 1) == 0);
const parity = new Signal.Computed(() => isEven.get() ? "even" : "odd");

effect(() => element.innerText = parity.get());

counter.set(counter.get() + 1);  // Effect automatically re-runs
```

Key properties:
- **Pull-based / Lazy**: Computed signals only evaluate when read
- **Synchronous**: No scheduling, no Promises
- **Memoized**: Cached until dependencies change
- **Auto-tracking**: Dependencies discovered automatically during evaluation

### Why Signals Don't Fit Tea Commands

Signals solve **"what is the current derived value?"** not **"do work and send events."**

| Aspect | Signals | Tea Commands |
|--------|---------|--------------|
| **Question answered** | "What is X now?" | "Do Y and tell me when done" |
| **Timing** | Synchronous, immediate | Asynchronous, later |
| **Data flow** | Pull (compute on demand) | Push (events arrive) |
| **Multiplicity** | One value (current) | Many messages over time |
| **Use case** | Derived state, UI binding | I/O, side effects, streams |

### Scenario Coverage

**Simple Synchronous** — N/A

Signals don't "do work." They derive values. There's no equivalent to "fetch this URL."

**Long-Lived Blocking** — N/A

Signals are synchronous. Blocking I/O would freeze the UI.

**Long-Lived Non-Blocking** — N/A

Signals represent a **single current value**, not a stream of events. A WebSocket produces many messages—there's no natural Signal representation.

**Cancellation** — N/A

Nothing to cancel. Signals are values, not ongoing processes.

### Where Signals COULD Apply to Tea

Signals might make sense for Tea's **View layer**, not Commands:

```ruby
# Hypothetical: View as Signal derivation
class MyApp
  def initialize
    @count = Signal::State.new(0)
    @doubled = Signal::Computed.new { @count.get * 2 }
  end
  
  def view
    # Only re-render parts that depend on changed signals
    Paragraph.new(text: "Count: #{@count.get}, Doubled: #{@doubled.get}")
  end
end
```

This would enable fine-grained reactivity in the View—only re-rendering UI elements whose dependencies changed. But this is **orthogonal** to the Command message-passing problem.

### The Angular Story

Angular moved **away** from RxJS for state management precisely because:
1. RxJS's operator learning curve was too steep
2. Most state is synchronous—streams are overkill
3. Signals give predictable, synchronous behavior

But Angular still uses RxJS for **HTTP calls and effects**—the analog to Tea Commands!

```typescript
// Angular: Signals for state
count = signal(0);
doubled = computed(() => this.count() * 2);

// Angular: RxJS for async effects
http.get('/api/data').subscribe(data => this.data.set(data));
```

### Relevance to Current Discussion

**Signals don't solve the Command message-passing problem.** They're a different abstraction for a different layer (reactive state/View vs. async effects).

However, a future Tea evolution might:
1. Use **Outlet** for Commands (async, push, multi-message)
2. Use **Signals** for Model→View reactivity (sync, pull, derived values)

This would mirror Angular's "Signals + RxJS for effects" pattern.

---

## Ruby Library Precedents

| Library | Pattern | Abstraction Level |
|---------|---------|-------------------|
| **Rails ActionMailer** | `deliver_now` / `deliver_later` | High (hides queue entirely) |
| **Sidekiq** | `MyWorker.perform_async(args)` | High (hides Redis) |
| **Concurrent Ruby Actor** | `actor.tell(message)` | Medium (actor terminology) |
| **Celluloid** | `mailbox.send(message)` | Medium (explicit mailbox) |
| **Ractor** | `ractor.send(obj)` | Low (direct, requires shareable) |
| **Ruby stdlib Queue** | `queue << item` | Low (raw data structure) |

**Pattern**: Mature Ruby libraries use high-level abstractions with domain-appropriate naming, hiding infrastructure details.

---

## Recommendation

**Use `Tea::Outlet`** (Option 2) with these refinements:

### 1. The Outlet Class

```ruby
module RatatuiRuby::Tea
  class Outlet
    def initialize(queue)
      @queue = queue
    end

    def put(tag, *payload)
      message = payload.size == 1 ? [tag, payload.first] : [tag, *payload]
      @queue << Ractor.make_shareable(message)
    rescue Ractor::IsolationError => e
      raise RatatuiRuby::Error::Invariant,
        "Message must be Ractor-shareable: #{e.message}"
    end
  end
end
```

### 2. Simplified Command::Custom Mixin

With Outlet handling Ractor-safety, the mixin becomes trivial:

```ruby
module RatatuiRuby::Tea::Command
  module Custom
    def tea_command? = true
    # No push helper needed—out.put handles it
  end
end
```

### 3. Runtime Dispatch Change

```ruby
private_class_method def self.dispatch(command, queue)
  case command
  when Command::System
    # ... existing (uses raw queue internally)
  when Command::Mapped
    # ... existing
  else
    if command.respond_to?(:call) && command.respond_to?(:tea_command?)
      outlet = Outlet.new(queue)
      Thread.new { command.call(out) }
    end
  end
end
```

### 4. RBS Signature

```ruby
# sig/ratatui_ruby/tea/outlet.rbs
module RatatuiRuby
  module Tea
    class Outlet
      def initialize: (Queue[untyped] queue) -> void
      def put: (Symbol tag, *untyped payload) -> void
    end
  end
end

# sig/ratatui_ruby/tea/command.rbs
interface _Command
  def call: (Outlet out) -> void
  def tea_command?: () -> true
end
```

---

## Migration Path

If we adopt Outlet, built-in commands (`Command::System`, etc.) can continue using the raw queue internally—they're not affected. Only the public API for custom commands uses Outlet.

This means:
- **No breaking changes** to existing code
- **New pattern** only applies to custom commands
- **Gradual adoption** as developers write new commands

---

## Open Questions

1. **Should Outlet expose `raw_queue` as an escape hatch?**
   - Pro: Flexibility for advanced users
   - Con: Encourages bypassing safety

2. **Should `put` return something?**
   - `nil` (current) — Simple, no expectations
   - `self` — Enables chaining: `out.put(:a).put(:b)`
   - Message count — Debugging aid

3. **Should we validate `tag` is a Symbol?**
   - Pattern matching works with symbols
   - But strings/classes also pattern-match fine
   - Probably: warn in debug mode, allow anything

4. **Terminology: "Outlet" vs alternatives?**
   - `Outlet` — Actor/MVU terminology ✓
   - `Dispatcher` — Sounds like it does more
   - `MessageBus` — Implies pub/sub
   - `Sender` — Too generic

---

## Summary

| Approach | Long-Lived Streams | Ractor Safety | Simplicity | Recommended? |
|----------|-------------------|---------------|------------|--------------|
| RxRuby | ✓ First-class | ⚠️ Manual | ✗ Steep learning | External option |
| Subscriptions (cut) | ✓ First-class | ✓ Runtime enforced | ✗ Complex runtime | Historical |
| Recursive Commands | ✗ Single message | ✓ Runtime enforced | ✓ High | Status quo |
| Raw `Queue` | ✓ Multi-message | ✗ Manual | ✓ High | No |
| **`Tea::Outlet`** | ✓ Multi-message | ✓ Built-in | ✓ High | **Yes** |
| Hybrid (+ escape) | ✓ Multi-message | ✓ Built-in | Medium | Maybe |
| Enumerator-based | ⚠️ Awkward | ✓ Runtime | ✗ Complex | No |
| TC39 Signals | N/A (wrong abstraction) | — | — | No (different problem) |

**Verdict**: Use `Tea::Outlet`. It provides Ractor-safety, clear domain language, better error messages, and room for future extension—all while keeping the API simple.

---

## Appendix: The Completion Problem

For long-lived commands (WebSockets, subscriptions, tickers), the runtime spawns a thread that may run indefinitely. **How does the runtime know when a command is "done"?**

### How Previous Approaches Handled This

**Option -2 (RxRuby)**: Completion is first-class. Observables have three signals: `on_next` (data), `on_error` (failure), and `on_completed` (done). The `subscribe` call returns a Subscription object with `unsubscribe()` for explicit teardown. Disposal logic defined in `Observable.create` runs on unsubscribe.

**Option -1 (Subscriptions)**: Runtime handled completion automatically via diffing. When `subscriptions(model)` stopped returning a subscription, the runtime killed its thread. Completion was implicit in the subscription's absence.

**Option 0 (Recursive Commands)**: Completion is handled by the update function. When update stops returning the recursive command, no more messages are produced. The "subscription" simply ends. No thread management needed because each tick is a separate command invocation.

### The New Problem with Outlet

Options 1-4 (Outlet-based) introduce a **new** completion challenge. The runtime spawns a thread for the command, but unlike Subscriptions, there's no diffing to detect when it should stop. Unlike Recursive Commands, the thread stays alive producing multiple messages.

Currently, the thread runs until:
- The command's internal loop breaks
- The app exits (and threads are killed)
- Ruby's GC cleans up (unreliable)

This creates resource leaks for commands that don't clean up after themselves.

### Solution A: Completion Message Convention

Commands signal completion via a reserved message:

```ruby
def call(out)
  ws = WebSocket::Client.new(@url)
  ws.on_message { |msg| out.put(:ws, :message, msg) }
  ws.on_close { out.put(:ws, :complete) }  # Signal done
  ws.on_error { |e| out.put(:ws, :error, message: e.message) }
  ws.connect
end
```

**Runtime behavior**: Optionally track `:complete` messages for cleanup/metrics.

**Pros**: Simple, explicit, no new API  
**Cons**: Convention, not contract—easy to forget

### Solution B: Return Cleanup Proc

Commands return a cleanup callable:

```ruby
def call(out)
  ws = WebSocket::Client.new(@url)
  ws.on_message { |msg| out.put(:ws, :message, msg) }
  ws.connect
  
  -> { ws.close }  # Cleanup proc
end

# Runtime:
cleanup = command.call(out)
at_exit { cleanup&.call }
```

**Pros**: Explicit cleanup, runtime can manage lifecycle  
**Cons**: Awkward return value (not the messages themselves)

### Solution C: Runtime Thread Tracking

Runtime tracks threads and kills them on exit:

```ruby
def self.dispatch(command, queue)
  if command.respond_to?(:call) && command.respond_to?(:tea_command?)
    outlet = Outlet.new(queue)
    thread = Thread.new { command.call(outlet) }
    @pending_threads << thread
  end
end

at_exit do
  @pending_threads.each { |t| t.kill }
end
```

**Pros**: No changes to command API  
**Cons**: Forceful `Thread#kill` can leave resources in bad state

### Solution D: Outlet Completion Signal

Outlet provides a `complete` method that signals the runtime:

```ruby
def call(out)
  ws = WebSocket::Client.new(@url)
  ws.on_message { |msg| out.put(:ws, :message, msg) }
  ws.on_close { out.complete }  # Built-in signal
  ws.connect
end
```

**Pros**: Part of the API, hard to forget  
**Cons**: More surface area on Outlet

### Recommendation

Start with **Solution A** (convention) + **Solution C** (thread tracking for safety). Document that long-lived commands SHOULD send `:complete` messages, but don't crash if they don't.

---

## Appendix B: Observer Patterns Comparison

JavaScript's event-driven model (EventTarget/addEventListener) and Ruby's Observable mixin both implement the Observer pattern. How do they compare, and how does Tea's Outlet relate?

### JavaScript's EventTarget

```javascript
// DOM EventTarget pattern
button.addEventListener('click', (event) => console.log('clicked!'));

// Custom EventTarget
const emitter = new EventTarget();
emitter.addEventListener('message', (e) => console.log(e.detail));
emitter.dispatchEvent(new CustomEvent('message', { detail: 'hello' }));
```

**Properties**: Push-based, multiple named event types, synchronous dispatch, `removeEventListener` for cleanup.

### Ruby's Observable Mixin (stdlib)

```ruby
require 'observer'

class Ticker
  include Observable
  
  def tick
    changed              # Mark as changed
    notify_observers(Time.now)  # Push to all observers
  end
end

class Display
  def update(time)
    puts "The time is #{time}"
  end
end

ticker = Ticker.new
ticker.add_observer(Display.new)
ticker.tick  # Display prints
```

**Properties**: Push-based, single notification channel, duck-typed observers (`#update`), manual `changed` tracking.

### Side-by-Side Comparison

| Aspect | JS EventTarget | Ruby Observable | Tea Outlet |
|--------|----------------|-----------------|------------|
| Add observer | `addEventListener(type, fn)` | `add_observer(obj)` | N/A (single consumer) |
| Dispatch | `dispatchEvent(event)` | `notify_observers(*args)` | `out.put(tag, *data)` |
| Event types | Named (e.g., 'click') | Single channel | Tag-based via first arg |
| Thread-safe | ✗ | ✗ | ✓ (Queue-backed) |
| Ractor-safe | — | ✗ | ✓ (auto `make_shareable`) |
| Multiple consumers | ✓ | ✓ | ✗ (runtime only) |
| Cleanup | `removeEventListener` | `delete_observer` | Thread tracking |

### The Key Difference: Event Types

**JS EventTarget** supports multiple named event types per emitter:

```javascript
emitter.addEventListener('open', onOpen);
emitter.addEventListener('message', onMessage);
emitter.addEventListener('close', onClose);
```

**Ruby Observable** has ONE notification channel per object:

```ruby
# All observers get ALL notifications
ticker.add_observer(display)
ticker.add_observer(logger)
ticker.notify_observers(data)  # Both receive same data
```

**Tea Outlet** uses tag-based discrimination (like EventTarget, but simpler):

```ruby
out.put(:open, connection_id: id)
out.put(:message, data: payload)
out.put(:close, reason: reason)
# Update function pattern-matches on first element
```

### Why Not Use Ruby Observable for Commands?

```ruby
class WebSocketCommand
  include Observable
  
  def run
    ws = WebSocket::Client.new(@url)
    ws.on_message { |msg| changed; notify_observers(:message, msg) }
    ws.connect
  end
end

command.add_observer(runtime)
```

**Problems**:
1. **Thread-safety**: Observable isn't thread-safe—concurrent `notify_observers` can corrupt observer list
2. **Ractor-safety**: No automatic `Ractor.make_shareable` on messages
3. **Coupling**: Runtime must be passed as observer (command knows about runtime)
4. **Error handling**: Observer exceptions propagate to notifier
5. **Lifetime management**: Who calls `delete_observer`? Memory leak risk.

### What Outlet Actually Is

The Outlet is a **simplified, Ractor-safe, thread-safe, single-consumer Observable**:

| Observable | Outlet Equivalent |
|------------|-------------------|
| `changed; notify_observers(:tag, data)` | `out.put(:tag, data)` |
| Observer list | Thread-safe Queue |
| `add_observer(obs)` | N/A (runtime is the only consumer) |
| `delete_observer(obs)` | N/A (command lifecycle handles cleanup) |

### The Abstraction Spectrum

```
Low-level                                                   High-level
   |                                                             |
   v                                                             v
Queue/Channel  ->  Observable  ->  EventTarget  ->  RxJS  ->  Signals
   |                  |               |              |            |
   |                  |               |              |            |
 Raw push       Push to N         Named events    Operators    Derived
 to queue       observers         w/types         transforms   values
```

Tea's **Outlet** sits at the **Queue/Channel** level—the simplest possible message passing with just enough safety for the Ractor-threaded runtime.

### Verdict

Ruby's Observable is conceptually similar but lacks thread-safety, Ractor-safety, and the cleanup semantics Tea needs. The Outlet is a purpose-built, constrained Observable optimized for the Tea runtime's specific single-consumer, cross-thread, Ractor-safe requirements.

---

## Appendix C: TEA Ecosystem Comparison

How do our proposed options compare to real-world implementations of The Elm Architecture? This appendix maps each option to established frameworks.

### Comprehensive Comparison Table

| Framework | Language | Domain | One-Shot Commands | Long-Lived Streams | Stream Mechanism | Lifecycle Mgmt | Custom Commands | Maps To Our Option |
|-----------|----------|--------|-------------------|-------------------|------------------|----------------|-----------------|-------------------|
| **Elm** | Elm | Web | ✓ `Cmd Msg` | ✓ `Sub Msg` | Runtime diffing | Runtime | ✓ Via Ports | -1 (Subscriptions) |
| **BubbleTea** | Go | TUI | ✓ `tea.Cmd` | ⚠️ Recursive only | Command returns Cmd | User | ✓ `func() Msg` | 0 (Recursive) |
| **Iced** | Rust | GUI | ✓ `Command` | ✓ `Subscription` | Stream trait | Runtime | ✓ `Command::perform` | -1 (Subscriptions) |
| **Miso** | Haskell | Web | ✓ `Effect` | ✓ `Sub` | Runtime diffing | Runtime | ✓ Via FFI | -1 (Subscriptions) |
| **Bolero** | F# | Web | ✓ `Cmd` | ✓ `Sub` | Runtime diffing | Runtime | ✓ `Cmd.ofMsg` | -1 (Subscriptions) |
| **redux-loop** | JS | Web | ✓ `Cmd` | ✗ None | — | — | ✓ `Cmd.run` | 0 (Recursive) |
| **Redux Thunk** | JS | Web | ✓ thunk fn | ✗ None | — | User | ✓ `(dispatch) => {}` | 1 (Raw Queue) |
| **Redux Saga** | JS | Web | ✓ saga | ✓ Channels | `take`/`put` effects | Saga middleware | ✓ Generator fns | **2 (Outlet)** |
| **Redux Observable** | JS | Web | ✓ Observable | ✓ Observable | RxJS streams | User | ✓ Epics | -2 (RxRuby) |
| **Vuex** | JS | Web | ✓ Actions | ✓ Subscriptions | Store subscribe | User | ✓ Actions | 1 (Raw Queue) |
| **Pinia** | JS | Web | ✓ Actions | ✓ `$subscribe` | Store subscribe | User | ✓ Actions | 1 (Raw Queue) |
| **NgRx Effects** | TS | Web | ✓ Effects | ✓ Effects | RxJS streams | Decorator | ✓ `createEffect` | -2 (RxRuby) |
| **Hyperapp** | JS | Web | ✓ Effects | ✓ Subscriptions | Runtime diffing | Runtime | ✓ Effect tuple | -1 (Subscriptions) |
| **Seed** | Rust | Web | ✓ `Orders` | ✓ `Sub` | Runtime | Runtime | ✓ `orders.perform_cmd` | -1 (Subscriptions) |

### Detailed Analysis by Framework

#### Elm (The Original)

Elm is the canonical TEA implementation. It has **two distinct primitives**:

```elm
-- Commands: one-shot, returned from update
update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
    case msg of
        FetchClicked ->
            ( { model | loading = True }
            , Http.get { url = "/api/data", expect = Http.expectJson GotData decoder }
            )

-- Subscriptions: long-lived, separate function
subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Time.every 1000 Tick
        , Browser.Events.onResize WindowResized
        , WebSocket.listen "ws://..." GotSocketMessage
        ]
```

**Key design decisions:**
- `Cmd` and `Sub` are **opaque types**—you can't peek inside
- Runtime manages subscription lifecycle via diffing
- Custom commands only via **Ports** (JS interop)
- No direct queue access—everything is declarative

**Maps to:** Option -1 (Subscriptions). Elm is the gold standard for runtime-managed subscriptions.

---

#### BubbleTea (Go)

BubbleTea deliberately simplified Elm's model by **removing Subscriptions entirely**:

```go
type Cmd func() Msg

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
    switch msg := msg.(type) {
    case tickMsg:
        return m, tea.Tick(time.Second, func(t time.Time) tea.Msg {
            return tickMsg(t)
        })
    }
    return m, nil
}
```

**Key design decisions:**
- Only `tea.Cmd` exists—no `Sub` equivalent
- Long-lived streams via **Recursive Commands** (command returns command)
- For complex streams: use Go channels with `tea.Batch`
- Custom commands are just `func() Msg`

**Maps to:** Option 0 (Recursive Commands). This is exactly the "Subscriptions are just Loops" pattern from our Pizza Summit.

---

#### Iced (Rust)

Iced brings Elm's full model to Rust, including proper Subscriptions:

```rust
impl Application for MyApp {
    fn update(&mut self, message: Message) -> Command<Message> {
        match message {
            Message::Fetch => Command::perform(fetch_data(), Message::DataFetched),
            _ => Command::none(),
        }
    }

    fn subscription(&self) -> Subscription<Message> {
        iced::time::every(Duration::from_secs(1)).map(Message::Tick)
    }
}
```

**Key design decisions:**
- `Command` for one-shot effects
- `Subscription` for streams (implemented as Rust `Stream` trait)
- Runtime diffs subscriptions automatically
- Strong type safety via Rust's type system

**Maps to:** Option -1 (Subscriptions). Iced is Elm-faithful with Rust performance.

---

#### Redux Thunk

Thunks are the simplest Redux side-effect pattern:

```javascript
// Thunk action creator
const fetchUser = (id) => async (dispatch, getState) => {
    dispatch({ type: 'FETCH_START' });
    try {
        const user = await api.getUser(id);
        dispatch({ type: 'FETCH_SUCCESS', payload: user });
    } catch (error) {
        dispatch({ type: 'FETCH_ERROR', error });
    }
};
```

**Key design decisions:**
- Thunk receives raw `dispatch` function
- User manually calls `dispatch()` whenever
- No lifecycle management—thunk runs to completion
- No long-lived stream support built-in

**Maps to:** Option 1 (Raw Queue). The thunk gets direct access to the dispatch mechanism, like passing a raw queue.

---

#### Redux Saga

Sagas use generator functions with effect descriptors:

```javascript
function* watchWebSocket() {
    const channel = yield call(createSocketChannel, url);
    try {
        while (true) {
            const message = yield take(channel);
            yield put({ type: 'WS_MESSAGE', payload: message });
        }
    } finally {
        channel.close();
    }
}

function* rootSaga() {
    yield takeEvery('CONNECT_WS', watchWebSocket);
}
```

**Key design decisions:**
- `put()` dispatches actions—**this is exactly our `out.put()`!**
- `take()` waits for actions/channel messages
- Sagas can be cancelled via `cancel()` effect
- Middleware manages saga lifecycle

**Maps to:** Option 2 (Outlet). Redux Saga's `put()` is the proven pattern we're adopting.

---

#### Redux Observable (RxJS)

Full reactive streams with operator composition:

```javascript
const fetchUserEpic = (action$) =>
    action$.pipe(
        ofType('FETCH_USER'),
        mergeMap(action =>
            ajax.getJSON(`/api/user/${action.id}`).pipe(
                map(response => ({ type: 'FETCH_SUCCESS', payload: response })),
                catchError(error => of({ type: 'FETCH_ERROR', error }))
            )
        )
    );
```

**Key design decisions:**
- Full RxJS operator library available
- Epics are Observable → Observable transformations
- Built-in cancellation, retry, debounce, etc.
- Steep learning curve

**Maps to:** Option -2 (RxRuby). Maximum power, maximum complexity.

---

#### NgRx Effects (Angular)

Angular's Redux-inspired state management with RxJS:

```typescript
@Injectable()
export class UserEffects {
    loadUsers$ = createEffect(() =>
        this.actions$.pipe(
            ofType(UserActions.loadUsers),
            mergeMap(() =>
                this.userService.getAll().pipe(
                    map(users => UserActions.loadUsersSuccess({ users })),
                    catchError(error => of(UserActions.loadUsersFailure({ error })))
                )
            )
        )
    );
}
```

**Maps to:** Option -2 (RxRuby). NgRx is what Angular is moving AWAY from with Signals (for simple state), though Effects remain for async.

---

### Pattern Prevalence

| Pattern | Frameworks Using It | Popularity |
|---------|---------------------|------------|
| **Cmd + Sub (diffing)** | Elm, Iced, Miso, Bolero, Hyperapp, Seed | Common in pure TEA |
| **Recursive Commands only** | BubbleTea, redux-loop | Common in simplified TEA |
| **Raw dispatch access** | Redux Thunk, Vuex, Pinia | Very common (simplest) |
| **put()-style messaging** | Redux Saga | Common in complex apps |
| **Full Reactive Streams** | Redux Observable, NgRx Effects | Less common (steep curve) |

### What This Means for Tea (Ruby)

1. **Pure TEA (Elm, Iced)** uses Option -1 (Subscriptions with runtime diffing)
    - Most elegant, but most runtime complexity
    - Runtime must track subscription identity and diff

2. **Simplified TEA (BubbleTea)** uses Option 0 (Recursive Commands)
    - Simplest runtime, but awkward for WebSockets/streams
    - This is our current "just Loops" approach

3. **Redux Ecosystem** offers a spectrum:
    - Thunk = Option 1 (raw access, simple)
    - Saga = Option 2 (put() pattern, balanced)
    - Observable = Option -2 (full RxJS, complex)

4. **Redux Saga's `put()` is battle-tested** at massive scale (Facebook, Airbnb, etc.)

### Recommendation Based on Ecosystem Analysis

| Phase | Approach | Rationale |
|-------|----------|-----------|
| **v1.0** | Option 2 (Outlet with `out.put`) | Redux Saga pattern, proven at scale |
| **v1.x** | Add Solution A+C (completion convention + thread tracking) | Safety net for long-lived commands |
| **v2.0 (maybe)** | Consider Option -1 (Subscriptions) | If users demand runtime lifecycle management |
| **Never** | Option -2 (RxRuby) | Angular explicitly moved away from this |

### The Historical Arc

```
2012: Elm introduces Cmd + Sub
          ↓
2016: Redux adds middleware (Thunk simple, Saga medium, Observable complex)
          ↓
2019: BubbleTea simplifies to Cmd-only ("Subs are Loops")
          ↓
2022: Angular moves FROM RxJS TO Signals for state
          ↓
2025: Tea (Ruby) chooses Outlet (Saga-style put())
```

The Outlet pattern represents the **consensus middle ground**: more flexible than BubbleTea's recursive-only approach, simpler than Elm's dual Cmd/Sub with runtime diffing, and battle-tested at massive scale through Redux Saga.

---

## Appendix D: Design Pattern Lineage

How do our proposed options map to canonical software design pattern literature? Understanding this lineage helps with communication, anticipating problems, and finding existing solutions.

### Pattern Catalog References

- **GoF**: Gamma, Helm, Johnson, Vlissides — *Design Patterns: Elements of Reusable Object-Oriented Software* (1994)
- **PoEAA**: Fowler — *Patterns of Enterprise Application Architecture* (2002)
- **EIP**: Hohpe & Woolf — *Enterprise Integration Patterns* (2003)
- **SOA Patterns**: Erl — *SOA Design Patterns* (2009)
- **Service Patterns**: Daigneau — *Service Design Patterns* (2011)
- **PoDS**: Joshi — *Patterns of Distributed Systems* (2023)

### Comprehensive Mapping Table

| Option | Primary GoF | PoEAA | EIP | SOA/Service | PoDS |
|--------|-------------|-------|-----|-------------|------|
| **-2 RxRuby** | Observer, Iterator | — | Event-Driven Consumer, Message Channel | Reactive Messaging | Event Sourcing |
| **-1 Subscriptions** | Observer, Mediator | Unit of Work | Publish-Subscribe Channel | — | — |
| **0 Recursive** | Command, State | Transaction Script | Polling Consumer | — | Request Pipeline |
| **1 Raw Queue** | Command | — | Message Queue, Point-to-Point Channel | Async Queuing | Write-Ahead Log |
| **2 Outlet** | **Facade** | **Gateway** | **Messaging Gateway**, Channel Adapter | **Service Gateway** | — |
| **3 Hybrid** | Adapter, Strategy | Gateway | Wire Tap | — | — |
| **4 Enumerator** | Iterator | — | Pipes and Filters, Message Sequence | — | Ordered Log |
| **5 Signals** | Observer, Proxy | Identity Map, Lazy Load | — | — | — |

---

### Detailed Pattern Mappings by Option

#### Option -2: RxRuby — Observer + Iterator Fusion

| Source | Pattern | How It Applies |
|--------|---------|----------------|
| **GoF** | **Observer** | Observables notify subscribers of values |
| **GoF** | **Iterator** | Rx is mathematically the "dual" of Iterator—push vs. pull |
| **EIP** | **Event-Driven Consumer** | Subscribes to and processes event stream |
| **EIP** | **Message Channel** | Observable IS a typed message channel |
| **PoDS** | **Event Sourcing** | Immutable stream of events with replay capability |

RxJS creator Erik Meijer described Observables as the categorical dual of Iterables. Where Iterator pulls values synchronously, Observable pushes values asynchronously.

#### Option -1: Subscriptions — Observer + Mediator

| Source | Pattern | How It Applies |
|--------|---------|----------------|
| **GoF** | **Observer** | Subscriptions notify the update function |
| **GoF** | **Mediator** | Runtime mediates subscription lifecycle |
| **EIP** | **Publish-Subscribe Channel** | Model state determines active subscriptions |
| **PoEAA** | **Unit of Work** | Runtime tracks subscription state changes for diffing |

The diffing mechanism is key: runtime maintains a set of "active subscriptions" and diffs against the new set after each update, spawning/killing threads as needed.

#### Option 0: Recursive Commands — Command + State Machine

| Source | Pattern | How It Applies |
|--------|---------|----------------|
| **GoF** | **Command** | Each command encapsulates a request |
| **GoF** | **State** | Update function is a finite state machine |
| **EIP** | **Polling Consumer** | Repeated commands poll/wait for changes |
| **PoEAA** | **Transaction Script** | Each update cycle is a discrete transaction |
| **PoDS** | **Request Pipeline** | Commands flow through the update pipeline |

The "Subscriptions are just Loops" pattern is essentially using the Command pattern recursively to simulate ongoing subscriptions.

#### Option 1: Raw Queue — Producer-Consumer

| Source | Pattern | How It Applies |
|--------|---------|----------------|
| **GoF** | **Command** | Messages are command objects in the queue |
| **EIP** | **Message Queue** | Thread-safe queue between producer/consumer |
| **EIP** | **Point-to-Point Channel** | Exactly one producer, one consumer |
| **EIP** | **Guaranteed Delivery** | Queue persists messages until consumed |
| **SOA** | **Asynchronous Queuing** | Fire-and-forget with reliable queuing |
| **PoDS** | **Write-Ahead Log** | Queue is a simplified WAL of pending messages |

This is the most fundamental messaging pattern—used internally by almost every other option.

#### Option 2: Outlet — Gateway + Message Channel

| Source | Pattern | How It Applies |
|--------|---------|----------------|
| **GoF** | **Facade** | Outlet simplifies queue interaction |
| **PoEAA** | **Gateway** | Outlet is a gateway to the messaging subsystem |
| **EIP** | **Messaging Gateway** | Encapsulates messaging, exposes domain methods |
| **EIP** | **Channel Adapter** | Adapts command semantics to queue protocol |
| **EIP** | **Message Translator** | `make_shareable` transforms message format |
| **Service Patterns** | **Service Gateway** | Domain-oriented facade over infrastructure |

**This is the core insight**: The Outlet is a textbook **Messaging Gateway**.

From Hohpe & Woolf:

> **Messaging Gateway**: Encapsulate access to the messaging system from the rest of the application.
>
> A Messaging Gateway is a class that wraps messaging-specific method calls and exposes domain-specific methods to the application. This way, the application doesn't need to know about the messaging infrastructure.

Compare:
- **Messaging-specific**: `queue << Ractor.make_shareable([tag, *payload])`
- **Domain-specific**: `out.put(:tag, data)`

The Outlet hides Ractor serialization, queue mechanics, and error handling behind a clean domain interface.

#### Option 3: Hybrid — Adapter + Strategy

| Source | Pattern | How It Applies |
|--------|---------|----------------|
| **GoF** | **Adapter** | Wraps queue with Outlet interface |
| **GoF** | **Strategy** | Choose between safe (Outlet) and raw (Queue) strategies |
| **PoEAA** | **Gateway** | Primary interface remains the gateway |
| **EIP** | **Wire Tap** | `raw_queue` is an escape hatch for inspection |

The Wire Tap pattern is notable: it allows tapping into the message flow without disrupting the primary channel.

#### Option 4: Enumerator — Iterator + Pipes and Filters

| Source | Pattern | How It Applies |
|--------|---------|----------------|
| **GoF** | **Iterator** | Enumerator IS Ruby's Iterator pattern |
| **EIP** | **Pipes and Filters** | Each `yield` produces output for next stage |
| **EIP** | **Message Sequence** | Ordered sequence of related messages |
| **PoDS** | **Ordered Log** | Messages maintain ordering guarantees |

The appeal of Enumerators is their composability—Ruby's `Enumerable` methods work directly on the stream.

#### Option 5: Signals — Observer + Memoization

| Source | Pattern | How It Applies |
|--------|---------|----------------|
| **GoF** | **Observer** | Watchers observe signal changes |
| **GoF** | **Proxy** | Computed signals proxy access to dependencies |
| **PoEAA** | **Identity Map** | Memoized computed values avoid recomputation |
| **PoEAA** | **Lazy Load** | Pull-based evaluation on demand |

Signals combine Observer (for notification) with caching patterns (for efficiency).

---

### Pattern Composition in Tea Architecture

The full Tea runtime composes multiple patterns:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                            MEDIATOR PATTERN                              │
│                           (Tea::Runtime)                                 │
│                                                                          │
│  ┌─────────────┐    ┌────────────────────┐    ┌────────────────────────┐│
│  │   COMMAND   │───▶│ MESSAGING GATEWAY  │───▶│    STATE MACHINE       ││
│  │   PATTERN   │    │ (Tea::Outlet)      │    │    (update function)   ││
│  │             │    │                    │    │                        ││
│  │ Custom Cmd  │    │ out.put(:tag,data) │    │ case msg               ││
│  │ #call(out)  │    │                    │    │ in [:tag, data]        ││
│  └─────────────┘    └────────────────────┘    └────────────────────────┘│
│         │                    │                          │               │
│         │                    ▼                          │               │
│         │         ┌────────────────────┐                │               │
│         │         │ POINT-TO-POINT     │                │               │
│         │         │ CHANNEL            │                │               │
│         │         │ (Thread::Queue)    │                │               │
│         │         └────────────────────┘                │               │
│         │                                               ▼               │
│         │                                    ┌────────────────────────┐ │
│         │                                    │      OBSERVER          │ │
│         └───────────────────────────────────▶│   (View reacts to      │ │
│                                              │    Model changes)      │ │
│                                              └────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────┘
```

---

### EIP Patterns We Might Add Later

The Enterprise Integration Patterns book contains patterns we might adopt as Tea evolves:

| EIP Pattern | Potential Tea Application |
|-------------|---------------------------|
| **Message Filter** | Outlet filters messages based on criteria |
| **Content Enricher** | Outlet adds metadata (timestamp, source) |
| **Aggregator** | Combine multiple command results |
| **Splitter** | One command produces multiple message streams |
| **Resequencer** | Guarantee message ordering |
| **Dead Letter Channel** | Handle failed/rejected messages |
| **Message Expiration** | TTL for queued messages |
| **Idempotent Receiver** | Deduplicate repeated messages |

---

### Why Pattern Recognition Matters

1. **Communication**: "The Outlet is a Messaging Gateway" immediately conveys intent to pattern-literate developers

2. **Prior Art**: Decades of solutions for Gateway error handling, retry logic, connection pooling, etc.

3. **Anticipating Issues**: EIP discusses Message Expiration—should old messages be discarded if the queue backs up?

4. **Design Reviews**: Pattern names provide shared vocabulary for architecture discussions

5. **Documentation**: "See EIP Chapter 10: Messaging Gateway" is more authoritative than "see our custom docs"

---

### Pattern-Based Design Questions

Viewing our options through pattern lenses raises questions:

| Pattern Lens | Question for Tea |
|--------------|------------------|
| **Gateway** | Should Outlet support connection pooling for heavy command workloads? |
| **Message Translator** | Should `make_shareable` failures have custom recovery strategies? |
| **Wire Tap** | Should debug mode log all messages without affecting delivery? |
| **Dead Letter** | What happens to messages after runtime shutdown? |
| **Guaranteed Delivery** | Is queue durability needed for crash recovery? |
| **Message Expiration** | Should stale tick messages be discarded? |

These questions—raised by pattern analysis—are exactly the kinds of issues the Completion Problem appendix addresses.

---

### Bibliography

For deeper exploration of these patterns:

1. **Gamma et al.** (1994). *Design Patterns: Elements of Reusable Object-Oriented Software*. Addison-Wesley.
   - Command, Observer, Mediator, Iterator, State, Facade, Adapter, Strategy, Proxy

2. **Fowler, M.** (2002). *Patterns of Enterprise Application Architecture*. Addison-Wesley.
   - Gateway, Unit of Work, Transaction Script, Identity Map, Lazy Load

3. **Hohpe, G. & Woolf, B.** (2003). *Enterprise Integration Patterns*. Addison-Wesley.
   - Messaging Gateway, Message Channel, Point-to-Point, Publish-Subscribe, Pipes and Filters

4. **Erl, T.** (2009). *SOA Design Patterns*. Prentice Hall.
   - Asynchronous Queuing, Service Messaging, Event-Driven Messaging

5. **Daigneau, R.** (2011). *Service Design Patterns*. Addison-Wesley.
   - Service Gateway, Request Mapper, Response Mapper

6. **Joshi, U.** (2023). *Patterns of Distributed Systems*. Addison-Wesley.
   - Write-Ahead Log, Request Pipeline, Ordered Log, Event Sourcing

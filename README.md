# GenLoop

<!-- rdmx :badges
    hexpm         : "gen_loop?color=4e2a8e"
    github_action : "lud/gen_loop/elixir.yaml?label=CI&branch=main"
    license       : gen_loop
    -->
[![hex.pm Version](https://img.shields.io/hexpm/v/gen_loop?color=4e2a8e)](https://hex.pm/packages/gen_loop)
[![Build Status](https://img.shields.io/github/actions/workflow/status/lud/gen_loop/elixir.yaml?label=CI&branch=main)](https://github.com/lud/gen_loop/actions/workflows/elixir.yaml?query=branch%3Amain)
[![License](https://img.shields.io/hexpm/l/gen_loop.svg)](https://hex.pm/packages/gen_loop)
<!-- rdmx /:badges -->


**GenLoop** provides a safe, OTP-compliant way to write processes using the "plain receive loop" pattern. It is built directly on top of Ulf Wiger's `:plain_fsm` but adapted for Elixir with some additional conveniences.

It allows you to write processes that use selective receive (unlike `GenServer`) while still handling system messages, parent exits, and other OTP requirements automatically.

## Installation

Add `gen_loop` to your list of dependencies in `mix.exs`:

<!-- rdmx :app_dep vsn:$app_vsn -->
```elixir
def deps do
  [
    {:gen_loop, "~> 1.0"},
  ]
end
```
<!-- rdmx /:app_dep -->

<!-- doc_start -->

## Features

- **OTP Compliant**: Handles system messages (`sys` module), parent supervision, and debugging.
- **Selective Receive**: Use `receive` blocks to pick messages when you want them, enabling complex state machines or protocols to be implemented more naturally.
- **Convenient Macros**: `rcall/2` and `rcast/1` macros to easily match on `GenLoop.call/2` and `GenLoop.cast/2` messages.
- **Familiar API**: Uses `start_link/3`, `call/3`, `cast/2` similar to `GenServer`.

## Usage

To use `GenLoop`, `use GenLoop` in your module. You need to define an entry point function (default is `enter_loop/1` or specified via `enter: :function_name`).

### Basic Example

Here is a simple Stack implementation:

```elixir
defmodule Stack do
  use GenLoop

  # Client API

  def start_link(initial_stack) do
    GenLoop.start_link(__MODULE__, initial_stack, name: __MODULE__)
  end

  def push(item) do
    GenLoop.cast(__MODULE__, {:push, item})
  end

  def pop do
    GenLoop.call(__MODULE__, :pop)
  end

  # Server Callbacks

  # Optional: init/1 can be used to validate args or set up initial state.
  # It should return {:ok, state}, {:stop, reason}, or :ignore.
  def init(initial_stack) do
    {:ok, initial_stack}
  end

  # The main loop.
  # The `receive/2` macro (provided by GenLoop) is used instead of `receive/1`.
  # It takes the current state as the first argument to handle system messages automatically.
  def enter_loop(stack) do
    receive stack do
      # Match a synchronous call
      rcall(from, :pop) ->
        case stack do
          [head | tail] ->
            reply(from, head) # Helper to send reply
            enter_loop(tail)  # Loop with new state
          [] ->
            reply(from, nil)
            enter_loop([])
        end

      # Match an asynchronous cast
      rcast({:push, item}) ->
        enter_loop([item | stack])

      # Match standard messages
      other ->
        IO.inspect(other, label: "Unexpected message")
        enter_loop(stack)
    end
  end
end
```

### Using the Process

```elixir
{:ok, _pid} = Stack.start_link([1, 2])

Stack.pop()
#=> 1

Stack.push(3)
#=> :ok

Stack.pop()
#=> 3
```

## Why GenLoop?

### vs GenServer

`GenServer` is the standard abstraction for client-server relations. However, it forces you to handle every message in a callback (`handle_call`, `handle_info`, etc.). This is great for most cases, but can be cumbersome for complex state machines where the set of expected messages changes depending on the state.

`GenLoop` allows you to write a "plain" recursive loop with `receive`, so you can wait for specific messages at specific times (selective receive).

### vs :gen_statem

`:gen_statem` is the OTP standard for state machines. It is very powerful but can be verbose. `GenLoop` offers a middle ground: it's simpler and feels more like writing a raw Elixir process, but with the safety net of OTP compliance.

## Advanced Usage

### Custom Entry Point

You can specify a different entry function name:

```elixir
use GenLoop, enter: :my_loop

def my_loop(state) do
  # ...
end
```

### Handling System Messages

The `receive state do ... end` macro is the magic that makes your loop OTP-compliant. It expands to a `receive` block that also includes clauses for handling system messages (like `sys.get_state`, `sys.suspend`, etc.) and parent exit signals.

If you want to handle everything manually (not recommended unless you know what you are doing), you can use the standard `receive do ... end`, but your process will not respond to standard OTP system calls.

## Acknowledgements

This library is built on top of [`:plain_fsm`](https://github.com/uwiger/plain_fsm) by Ulf Wiger.
It also draws inspiration from [`plain_fsm_ex`](https://github.com/ashneyderman/plain_fsm_ex) by ashneyderman.

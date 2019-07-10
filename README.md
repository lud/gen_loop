# GenLoop

This library is an adaptation of awesome Ulf Wiger's erlang library `:plain_fsm` for
Elixir. It reuses as `:plain_fsm` code as possible, but adds some features :

- Elixir-like OTP system behaviours for starting processes, stopping processes and name
  registering. That means that you can use the classic naming conventions as in
  `GenServer`:
  ```elixir
  name = atom_key
  name = {:global, key}
  name = {:via, Registry, {AppRegistry, key}}
  GenLoop.start_link(module, args, name: name)
  GenLoop.send(name, message)
  GenLoop.stop(name)
  ```
- `receive/2` macro inspired from
  [ashneyderman/plain_fsm_ex](https://github.com/ashneyderman/plain_fsm_ex) that
  automatically handles system messages. It handles parent `:EXIT` messages if
  your process traps exits too.

This is still a work in progress, notably the documentation must be completed.

## Installation

The package can be installed by adding `gen_loop` to your list
of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:gen_loop, "~> 1.0"},
  ]
end
```

As of version 1.0.0, [plain_fsm](https://hex.pm/packages/plain_fsm) is
a normal dependency pulled from hex.pm.

## Why ?

This library is a direct concurrent to `GenServer` or `:gen_statem` : it provides
selective receive and more freedom but makes it easier to shoot yourself in the
foot.

More info in [`plain_fsm` rationale](https://github.com/uwiger/plain_fsm/blob/master/doc/plain_fsm.md).

## How To ?

This section is to be polished, but basically :

- First, `use GenLoop, enter: :my_loop` in your module, where `:my_loop` is the
  name of a function in your module.
- Call `GenLoop.start_link(__MODULE__, init_arg)`, you can also give options like
  `name`, just like a `GenServer`.
- Maybe `def init(init_arg)` . It should return `{:ok, state}, {:stop, reason} or :ignore`.
- Define your `my_loop(init_arg)` function where your code now runs in a
  supervised process.
- In your state functions, you can use `receive/1` blocks just as normal
  but you can also use the `receive/2` macro in your main state function.
  It's best to use the latter on a base state where the most time is spent,
  in order to handle system messages automatically and keep the classic
  `receive/1` blocks for transient states.

  ```elixir
  def my_loop(state)
    my_state = change_stuf(state)
    receive my_state do   # Pass the state if you want to handle system messages
      rcall(from, msg) -> # Match a message from GenLoop.call/2
        reply(from, :ok)  # Reply with GenLoop.reply (automatically imported)
        my_loop(state)    # Don't forget to re-enter the loop
      rcast(msg) ->       # Match a message from GenLoop.cast
        state = do_stuff(msg)
        my_loop(state)
      msg ->              # Match a mere message from Kernel.send/2 or GenLoop.send/2
        state = do_stuff(msg)
        other_loop(state) # You can go to another loop to change state
    after
      1000 -> my_loop(state)
    end
    # You must not have any code after receive.
  end
  ```
- `rcall` and `rcast` work also with normal `receive/1`.
- `receive/1` or `receive/2` must be the last expression in the function. 
- If you add the `get_state` option when using GenLoop, your module
  will automatically define a `get_state(pid_or_name)` function
  and any `receive/2` block will answer to this call with the current
  process state. 
  Currently only the `:all` option is supported.
  It's better to keep this functionality for debug
  purposes.

 ```
 use GenLoop, get_state: :all
 ```


Have a look at [loop_example.ex](https://github.com/niahoo/gen_loop/blob/master/lib/loop_example.ex).

## Alternative

GenLoop is designed for communicating processes : servers, FSMs, etc. Have a
look at the [Task](https://hexdocs.pm/elixir/Task.html) module if you just want
to supervise autonomous processes.

GenLoop is not a replacement for GenServer : if your have only one loop in your
module with a "catch all messages" clause, you woud better use GenServer
instead of GenLoop.

You may also use :gen_statem as a good replacement to selective receives.

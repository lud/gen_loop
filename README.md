# GenLoop

This library is an adaptation of awesome Ulf Wiger's library `:plain_fsm` for
Elixir. It reuses as `:plain_fsm` code as possible, but adds some features :

- OTP system behaviours for starting processes, stopping processes and name
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

The package can be installed by adding `gen_loop` and `plain_fsm` to your list
of dependencies in `mix.exs`: We need to add `plain_fsm` because it is old on
Hex repository, we use a more up-to-date version of the library (mainly to
handle `terminate/2` callback).

```elixir
def deps do
  [
    {:gen_loop, "~> 0.1.0"},
    {:plain_fsm, github: "uwiger/plain_fsm", commit: "ae9eca8a8df8f61a32185b06882a55d60e62e904"},
  ]
end
```


## Why ?

This library is a direct concurrent to GenServer and GenFsm : it provides
selective receive and more freedom but makes it easier to shoot yourself in the
foot.

More info in [`plain_fsm` rationale](https://github.com/uwiger/plain_fsm/blob/master/doc/plain_fsm.md).

## How To ?

This section is still to be done, but basically :

- First, `use GenLoop, enter: :my_loop` in your module, where `:my_loop` is the
  name of a function in your module.
- Call `GenLoop.start_link(__MODULE__, args)`, you can also give options like
  `name`.
- Maybe `def init(args_list_from_start_link)` function that will return as in
  GenServer behaviour : `{:ok, state}`.
- Define your `my_loop(state_from_init)` function where your code now runs in a
  supervised process.
- Use the `receive/2` macro in your main state function (classic `receive/1` is
  fine in transient states):
  ```elixir
  def my_loop(state)
    my_state = change_stuf(state)
    receive my_state do   # Pass the state to use the macro
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
- `receive` must be the last expression in the function.


Have a look at [gen_loop_example.ex](https://github.com/niahoo/gen_loop/blob/master/lib/gen_loop_example.ex).

## Alternative

GenLoop is designed for communicating processes : servers, FSMs, etc. Have a
look at the [Task](https://hexdocs.pm/elixir/Task.html) module if you just want
to supervise autonomous processes.

GenLoop is not a replacement for GenServer : if your have only one loop in your
module with a "catch all messages" clauses, you woud better use GenServer
instead of GenLoop.

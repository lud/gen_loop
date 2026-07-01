defmodule PlainFsmRecords do
  @moduledoc false
  # We use the same records as in plain_fsm code, so a plain_fsm module and a
  # GenLoop module are compatible.

  # Extracting records with from_lib: "plain_fsm/src/plain_fsm.erl" does not
  # work, so we redefine them here. But we have to be in syc with plain_fsm
  # developers.
  require Record

  Record.defrecord(:fsm_sys, :sys,
    cont: :undefined,
    mod: :undefined,
    name: :undefined
  )

  Record.defrecord(:fsm_info, :info,
    parent: :undefined,
    debug: [],
    # fsm_sys() does not work (macro)
    sys: {:undefined, :undefined, :undefined}
  )
end

defmodule GenLoop do
  @moduledoc "README.md"
             |> File.read!()
             |> String.split("<!-- doc_start -->")
             |> Enum.at(1)
             |> String.trim()

  @typedoc "Return values of `start*` functions"
  @type on_start :: {:ok, pid} | :ignore | {:error, {:already_started, pid} | term}

  @typedoc "The GenLoop name"
  @type name :: atom | {:global, term} | {:via, module, term}

  @typedoc "Options used by the `start*` functions"
  @type options :: [option]

  @typedoc "Option values used by the `start*` functions"
  @type option ::
          {:debug, debug}
          | {:name, name}
          | {:timeout, timeout}
          | {:spawn_opt, Process.spawn_opt()}

  @typedoc "Debug options supported by the `start*` functions"
  @type debug :: [:trace | :log | :statistics | {:log_to_file, Path.t()}]

  @typedoc "The server reference"
  @type server :: pid | name | {atom, node}

  @typedoc """
  Tuple describing the client of a call request.
  `pid` is the PID of the caller and `tag` is a unique term used to identify the
  call.
  """
  @type from :: {pid, tag :: term}

  @callback init(args :: term) ::
              {:ok, state}
              | {:ok, state, timeout | :hibernate}
              | :ignore
              | {:stop, reason :: any}
            when state: any

  @callback data_vsn() :: term

  @doc false
  def __fsm_meta_key__, do: {:plain_fsm, :info}

  @doc """
  Sends an asynchronous broadcast to the named server on all connected nodes
  and the local node.

  Delegates to `GenServer.abcast/2`. Always returns `:abcast`.
  """
  @spec abcast([node], name :: atom, term) :: :abcast
  defdelegate abcast(server, term), to: GenServer

  @doc """
  Sends an asynchronous broadcast to the named server on the given `nodes`.

  Delegates to `GenServer.abcast/3`. Always returns `:abcast`.
  """
  defdelegate abcast(nodes, server, term), to: GenServer

  @doc """
  Sends a synchronous request to the `server` and waits for its reply.

  Works like `GenServer.call/3`, but the request is delivered to a `GenLoop`
  process where it is matched with the `rcall/2` macro inside a `receive/2`
  block, and answered with `reply/2`.

  `server` can be a pid, a registered name, or any of the `t:server/0` forms.
  The call raises if `server` resolves to the calling process itself, and
  exits if no process is found or if the callee does not reply within
  `timeout` milliseconds (defaults to `5000`).
  """
  @spec call(server, term, timeout) :: term
  def call(server, request, timeout \\ 5000) do
    case whereis(server) do
      nil ->
        exit({:noproc, {__MODULE__, :call, [server, request, timeout]}})

      pid when pid == self() ->
        exit({:calling_self, {__MODULE__, :call, [server, request, timeout]}})

      pid ->
        try do
          :gen.call(pid, :"$gen_call", request, timeout)
        catch
          :exit, reason ->
            exit({reason, {__MODULE__, :call, [server, request, timeout]}})
        else
          {:ok, res} -> res
        end
    end
  end

  @doc """
  Behaves just like Kernel.send but accepts atoms or registry tuples on top of
  pids to identify a process.
  """
  @spec send(server, term) :: term
  def send(server, message) do
    case whereis(server) do
      nil ->
        exit({:noproc, {__MODULE__, :send_to, [server, message]}})

      pid when pid == self() ->
        exit({:sending_to_self, {__MODULE__, :send_to, [server, message]}})

      pid ->
        Kernel.send(pid, message)
    end
  end

  @doc """
  Sends an asynchronous request to the `server`.

  Delegates to `GenServer.cast/2` and returns `:ok` immediately. The message is
  matched with the `rcast/1` macro inside the target loop's `receive/2` block.
  """
  @spec cast(server, term) :: term
  defdelegate cast(server, term), to: GenServer

  @doc """
  Sends a synchronous request to the named server on several nodes and collects
  their replies.

  `nodes` defaults to the local node plus every connected node. `name` must be
  the locally registered name of the server on each node. Returns a tuple of the
  gathered `{node, reply}` pairs and the list of nodes that did not reply within
  `timeout` (defaults to `:infinity`).
  """
  @spec multi_call([node], name :: atom, term, timeout) ::
          {replies :: [{node, term}], bad_nodes :: [node]}
  def multi_call(nodes \\ [node() | Node.list()], name, request, timeout \\ :infinity) do
    :gen_server.multi_call(nodes, name, request, timeout)
  end

  @doc """
  Replies to a `call/3` request.

  `from` is the client reference bound by the `rcall/2` macro on the server side.
  Delegates to `GenServer.reply/2` and returns `:ok`.
  """
  @spec reply(from, term) :: :ok
  defdelegate reply(from, term), to: GenServer

  @doc """
  Starts a `GenLoop` process without linking it to the caller.

  Takes the callback `module`, the `args` term passed to its `c:init/1`
  callback, and the start `t:options/0` (such as `:name`, `:timeout`, or
  `:debug`). Returns a `t:on_start/0` value.

  Use `start_link/3` instead when the process should be supervised.
  """
  @spec start(module, any, options) :: on_start
  def start(module, args, options \\ []) when is_atom(module) and is_list(options) do
    do_start(:nolink, module, args, options)
  end

  @doc """
  Starts a `GenLoop` process linked to the caller.

  Takes the callback `module`, the `args` term passed to its `c:init/1`
  callback, and the start `t:options/0` (such as `:name`, `:timeout`, or
  `:debug`). Returns a `t:on_start/0` value.

  This is the function to call from a supervisor child spec.
  """
  @spec start_link(module, any, options) :: on_start
  def start_link(module, args, options \\ []) when is_atom(module) and is_list(options) do
    do_start(:link, module, args, options)
  end

  defp do_start(link, module, args, options) do
    case Keyword.pop(options, :name) do
      {nil, opts} ->
        :gen.start(__MODULE__, link, module, args, opts)

      {atom, opts} when is_atom(atom) ->
        :gen.start(__MODULE__, link, {:local, atom}, module, args, opts)

      {{:global, _term} = tuple, opts} ->
        :gen.start(__MODULE__, link, tuple, module, args, opts)

      {{:via, via_module, _term} = tuple, opts} when is_atom(via_module) ->
        :gen.start(__MODULE__, link, tuple, module, args, opts)

      {other, _} ->
        raise ArgumentError, """
        expected :name option to be one of:
          * nil
          * atom
          * {:global, term}
          * {:via, module, term}
        Got: #{inspect(other)}
        """
    end
  end

  @doc """
  Stops the `server` with reason `:normal`.

  Delegates to `GenServer.stop/1` and returns `:ok` once the process has
  terminated.
  """
  @spec stop(server, reason :: term, timeout) :: :ok
  defdelegate stop(server), to: GenServer

  @doc """
  Stops the `server` with the given exit `reason`.

  Delegates to `GenServer.stop/2` and returns `:ok` once the process has
  terminated.
  """
  defdelegate stop(server, reason), to: GenServer

  @doc """
  Stops the `server` with the given exit `reason`, waiting at most `timeout`
  milliseconds.

  Delegates to `GenServer.stop/3`. Exits with `:timeout` if the process does not
  terminate in time.
  """
  defdelegate stop(server, reason, timeout), to: GenServer

  @doc """
  Returns the pid of the process registered under `name`, or `nil` when no such
  process exists.

  Delegates to `GenServer.whereis/1` and accepts the same name forms.
  """
  @spec whereis(server) :: pid | {atom, node} | nil
  defdelegate whereis(name), to: GenServer

  # -- plain_fsm wrapper ------------------------------------------------------

  import PlainFsmRecords

  # -- Macros -----------------------------------------------------------------

  @doc """
  Matches a message sent by `call/3` inside a `receive/2` block.

  Binds the client reference to `from`, which is later passed to `reply/2`, and
  matches the request against `msg`.

      receive state do
        rcall(from, :pop) ->
          reply(from, hd(state))
          loop(tl(state))
      end
  """
  defmacro rcall(from, msg) do
    quote do
      {:"$gen_call", unquote(from), unquote(msg)}
    end
  end

  @doc """
  Matches a message sent by `cast/2` inside a `receive/2` block.

  Matches the cast payload against `msg`.

      receive state do
        rcast({:push, item}) ->
          loop([item | state])
      end
  """
  defmacro rcast(msg) do
    quote do
      {:"$gen_cast", unquote(msg)}
    end
  end

  @doc """
  Returns the pid of the client from a `t:from/0` reference bound by `rcall/2`.

  Useful when the loop needs the caller's pid, for instance to monitor it,
  rather than only replying to it with `reply/2`.
  """
  defmacro from_pid(from) do
    quote do
      elem(unquote(from), 0)
    end
  end

  defmacro __using__(opts \\ []) do
    {enter_loop_name, opts} = Keyword.pop(opts, :enter, :enter_loop)

    quote location: :keep, bind_quoted: [opts: opts, enter_loop_name: enter_loop_name] do
      @behaviour GenLoop

      # Import the macros/funs for receive
      import GenLoop,
        only: [
          from_pid: 1,
          hibernate: 3,
          rcall: 2,
          rcast: 1,
          receive: 2,
          reply: 2
        ]

      enter_loop_name = opts[:enter] || :enter_loop

      default_child_spec = [
        id: opts[:id] || __MODULE__,
        start: Macro.escape(opts[:start]) || quote(do: {__MODULE__, :start_link, [arg]}),
        restart: opts[:restart] || :permanent,
        shutdown: opts[:shutdown] || 5000,
        type: :worker
      ]

      @doc false

      def child_spec(init_arg) do
        default = %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, [init_arg]}
        }

        Supervisor.child_spec(default, unquote(Macro.escape(opts)))
      end

      @doc false
      def init(args) do
        {:ok, args}
      end

      # We set the same default version as in plain_fsm transforms
      @doc false
      def data_vsn do
        0
      end

      @doc false
      def unquote(enter_loop_name)(_) do
        fsm_info(sys: fsm_sys(mod: mod)) = Process.get(GenLoop.__fsm_meta_key__())

        raise """
        According to GenLoop behaviour,
        you must define the #{unquote(enter_loop_name)}/1 function
        in module #{inspect(mod)} to accept the state returned by
        in your init/1 callback.

          def #{unquote(enter_loop_name)}(arg) do
            # Transition to state
          end

        You can otherwise give the name of your main loop (or any
        other function of arity 1) when using GenLoop

          use GenLoop, enter: :main_loop

        """
      end

      def __gen_loop_enter_loop__(state) do
        unquote(enter_loop_name)(state)
      end

      defoverridable init: 1,
                     data_vsn: 0,
                     child_spec: 1

      defoverridable [
        {enter_loop_name, 1}
      ]
    end
  end

  # This macro is heavily inspired (i mean stolen) from
  # ashneyderman/plain_fsm_ex from Github. The main difference is that
  # we do not use a reference to the argument of the function, but
  # rather require the state variable to be passed.
  #
  # It allows to change the state variable before entering the receive
  # block and keep the changes when a system message is handled or
  # when a parent EXIT is received.
  @doc """
  Waits for messages while keeping the process OTP-compliant.

  Use this macro in place of the standard `Kernel.SpecialForms.receive/1` inside
  a loop function of arity 1. `state_var` is the current process state, and
  `blocks` holds the usual `do`/`after` clauses.

  On top of the clauses you write, the macro injects clauses that handle system
  messages (the `:sys` protocol used by `call/3`, debugging, and code change)
  and parent exit signals, passing `state_var` along so those handlers can
  resume the loop with the current state. Match `call/3` and `cast/2` messages
  with the `rcall/2` and `rcast/1` macros.

  The enclosing function must take exactly one argument, the state, otherwise a
  compile-time `ArgumentError` is raised.

      def loop(state) do
        receive state do
          rcast({:push, item}) ->
            loop([item | state])
        after
          5000 ->
            loop(state)
        end
      end
  """
  defmacro receive(state_var, blocks) do
    {loop_name, arity} = __CALLER__.function

    if arity !== 1 do
      raise ArgumentError, bad_arity_msg(__CALLER__)
    end

    define_parent =
      quote do
        plain_fsm_parent = :plain_fsm.info(:parent)
      end

    [parent_exit_clause] =
      quote do
        {:EXIT, ^plain_fsm_parent, reason} ->
          :plain_fsm.parent_EXIT(reason, unquote(state_var))
      end

    [other_exit_clause] =
      quote do
        {:EXIT, _from, reason} = msg ->
          exit(reason)
      end

    [system_message_clause] =
      quote do
        {:system, from, req} ->
          :plain_fsm.handle_system_msg(
            req,
            from,
            unquote(state_var),
            &(unquote(Macro.var(loop_name, Elixir)) / 1)
          )
      end

    receive_clauses =
      case blocks[:do] do
        # empty receive statement
        {:__block__, [], []} -> []
        list -> list
      end

    do_block =
      receive_clauses
      |> List.insert_at(0, other_exit_clause)
      |> List.insert_at(0, parent_exit_clause)
      |> List.insert_at(0, system_message_clause)

    # Put the clauses back together with the 'after' clauses
    new_blocks = Keyword.put(blocks, :do, do_block)
    whole_receive = {:receive, [], [new_blocks]}

    _ast =
      quote do
        unquote(define_parent)
        unquote(whole_receive)
      end
  end

  defp bad_arity_msg(caller) do
    %{module: mod, function: {fun, _arity}} = caller

    """
    Error when calling #{:receive} in module #{inspect(mod)}:

    The calling function must be of arity 1. It should only accept the current
    state of the process.

      def #{fun}(state) do
        # ... maybe change state ...
        receive state do
          # ... clauses ...
        end
      end
    """
  end

  # This macro comes from plain_fsm_ex too. It's just a call to the plain_fsm
  # form of hibernate, i.e. calling the plain_fsm:wake_up function that will
  # look into the process dictionary to get back the state.

  # plain_fsm require that the function has only one argument in order to call
  # code_change with state.
  @doc """
  Hibernates the process and resumes in a loop function when a message arrives.

  Wraps `:erlang.hibernate/3` through `:plain_fsm`, so the process state is
  restored (running `c:code_change/3` when the code version changed) before the
  loop continues. `module` and `function` name the loop function to wake up in,
  and `args` must be a one-element list holding the state to resume with.

      def loop(state) do
        receive state do
          rcast(:idle) ->
            hibernate(__MODULE__, :loop, [state])
        end
      end

  Passing an `args` list with anything other than one element raises an
  `ArgumentError`.
  """
  defmacro hibernate(module, function, [_] = args) do
    quote do
      :erlang.hibernate(:plain_fsm, :wake_up, [
        # The old version of code
        data_vsn(),
        # Module to call data_vsn() for new version of code
        unquote(module),
        # Module …
        unquote(module),
        # … Function …
        unquote(function),
        # … Arguments to call after wakeup
        unquote(args)
      ])
    end
  end

  defmacro hibernate(_module, _function, arguments) do
    raise ArgumentError, """
    GenLoop.hibernate(module, function, arguments) accepts only one element in arguments.
        Got: #{Macro.to_string(arguments)} (#{length(arguments)} arguments)
    """
  end

  ## -- Server side handler ---------------------------------------------------

  @doc false
  def init_it(starter, :self, name, mod, args, options),
    do: init_it(starter, self(), name, mod, args, options)

  def init_it(starter, parent, name0, mod, args, _options) do
    reg_name = name(name0)
    # Copy pasta of plain_fsm init code  storing meta into process dictionary
    #
    #    info = fsm_info(parent: parent)
    #    sys = fsm_info(info, :sys)
    #    Process.put(@fsm_meta_key, fsm_info(info, sys: fsm_sys(sys, mod: mod)))
    #
    # but everything is empty so we not just write this
    Process.put(__fsm_meta_key__(), fsm_info(parent: parent, sys: fsm_sys(mod: mod, name: reg_name)))
    # Call the behaviour init function
    case mod.init(args) do
      {:ok, state} ->
        :proc_lib.init_ack(starter, {:ok, self()})
        mod.__gen_loop_enter_loop__(state)

      {:stop, reason} ->
        unregister_name(name0)
        :proc_lib.init_ack(starter, {:error, reason})
        exit(reason)

      :ignore ->
        unregister_name(name0)
        :proc_lib.init_ack(starter, :ignore)
        exit(:normal)

      other ->
        err = {:error, {:bad_return_value, other}}
        :proc_lib.init_ack(starter, err)
        exit(other)
    end
  end

  defp name({:local, name}),
    do: name

  defp name({:global, name}),
    do: name

  defp name({:via, _, name}),
    do: name

  defp name(pid) when is_pid(pid),
    do: pid

  defp unregister_name({:global, name}),
    do: :global.unregister_name(name)

  defp unregister_name({:via, mod, name}),
    do: mod.unregister_name(name)

  defp unregister_name(pid) when is_pid(pid),
    do: pid

  defp unregister_name({:local, name}) do
    Process.unregister(name)
  rescue
    _ -> :ok
  catch
    _ -> :ok
  end
end

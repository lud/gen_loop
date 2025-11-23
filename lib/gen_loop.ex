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

  @spec abcast([node], name :: atom, term) :: :abcast
  defdelegate abcast(server, term), to: GenServer
  defdelegate abcast(nodes, server, term), to: GenServer

  # Cannot defdelegate because of __MODULE__
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

  @spec cast(server, term) :: term
  defdelegate cast(server, term), to: GenServer

  @spec multi_call([node], name :: atom, term, timeout) ::
          {replies :: [{node, term}], bad_nodes :: [node]}
  def multi_call(nodes \\ [node() | Node.list()], name, request, timeout \\ :infinity) do
    :gen_server.multi_call(nodes, name, request, timeout)
  end

  @spec reply(from, term) :: :ok
  defdelegate reply(from, term), to: GenServer

  @spec start(module, any, options) :: on_start
  def start(module, args, options \\ []) when is_atom(module) and is_list(options) do
    do_start(:nolink, module, args, options)
  end

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

  @spec stop(server, reason :: term, timeout) :: :ok
  defdelegate stop(server), to: GenServer
  defdelegate stop(server, reason), to: GenServer
  defdelegate stop(server, reason, timeout), to: GenServer

  @spec whereis(server) :: pid | {atom, node} | nil
  defdelegate whereis(name), to: GenServer

  # -- plain_fsm wrapper ------------------------------------------------------

  import PlainFsmRecords

  # -- Macros -----------------------------------------------------------------

  defmacro rcall(from, msg) do
    quote do
      {:"$gen_call", unquote(from), unquote(msg)}
    end
  end

  defmacro rcast(msg) do
    quote do
      {:"$gen_cast", unquote(msg)}
    end
  end

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

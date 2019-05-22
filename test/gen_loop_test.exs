defmodule GenLoopTest do
  use ExUnit.Case, async: true

  # Copy pasta of the GenSever tests suite

  defmodule Stack do
    use GenLoop

    def enter_loop(stack) do
      receive stack do
        rcall(from, :pop) ->
          [h | t] = stack
          reply(from, h)
          enter_loop(t)

        rcall(_, :noreply) ->
          enter_loop(stack)

        rcast({:push, item}) ->
          enter_loop([item | stack])
      end
    end

    def terminate(_reason, _state) do
      # There is a race condition if the agent is
      # restarted too fast and it is registered.
      try do
        self() |> Process.info(:registered_name) |> elem(1) |> Process.unregister()
      rescue
        _ -> :ok
      end

      :ok
    end
  end

  test "generates child_spec/1" do
    assert Stack.child_spec([:hello]) == %{
             id: Stack,
             restart: :permanent,
             shutdown: 5000,
             start: {Stack, :start_link, [[:hello]]},
             type: :worker
           }

    defmodule CustomStack do
      use GenLoop,
        id: :id,
        restart: :temporary,
        shutdown: :infinity,
        start: {:foo, :bar, []}
    end

    assert CustomStack.child_spec([:hello]) == %{
             id: :id,
             restart: :temporary,
             shutdown: :infinity,
             start: {:foo, :bar, []},
             type: :worker
           }
  end

  test "start_link/3" do
    assert_raise ArgumentError, ~r"expected :name option to be one of:", fn ->
      GenLoop.start_link(Stack, [:hello], name: "my_gen_server_name")
    end

    assert_raise ArgumentError, ~r"expected :name option to be one of:", fn ->
      GenLoop.start_link(Stack, [:hello], name: {:invalid_tuple, "my_gen_server_name"})
    end

    assert_raise ArgumentError, ~r"expected :name option to be one of:", fn ->
      GenLoop.start_link(Stack, [:hello], name: {:via, "Via", "my_gen_server_name"})
    end

    assert_raise ArgumentError, ~r/Got: "my_gen_server_name"/, fn ->
      GenLoop.start_link(Stack, [:hello], name: "my_gen_server_name")
    end
  end

  test "start_link/3 with via" do
    GenLoop.start_link(Stack, [:hello], name: {:via, :global, :via_stack})
    assert GenLoop.call({:via, :global, :via_stack}, :pop) == :hello
  end

  test "start_link/3 with global" do
    GenLoop.start_link(Stack, [:hello], name: {:global, :global_stack})
    assert GenLoop.call({:global, :global_stack}, :pop) == :hello
  end

  test "start_link/3 with local" do
    GenLoop.start_link(Stack, [:hello], name: :stack)
    assert GenLoop.call(:stack, :pop) == :hello
  end

  test "start_link/2, call/2 and cast/2" do
    {:ok, pid} = GenLoop.start_link(Stack, [:hello])

    {:links, links} = Process.info(self(), :links)
    assert pid in links

    assert GenLoop.call(pid, :pop) == :hello
    assert GenLoop.cast(pid, {:push, :world}) == :ok
    assert GenLoop.call(pid, :pop) == :world
    assert GenLoop.stop(pid) == :ok

    assert GenLoop.cast({:global, :foo}, {:push, :world}) == :ok
    assert GenLoop.cast({:via, :foo, :bar}, {:push, :world}) == :ok
    assert GenLoop.cast(:foo, {:push, :world}) == :ok
  end

  @tag capture_log: true
  test "call/3 exit messages" do
    name = :self
    Process.register(self(), name)
    :global.register_name(name, self())
    {:ok, pid} = GenLoop.start_link(Stack, [:hello])
    {:ok, stopped_pid} = GenLoop.start(Stack, [:hello])
    GenLoop.stop(stopped_pid)

    assert catch_exit(GenLoop.call(name, :pop, 5000)) ==
             {:calling_self, {GenLoop, :call, [name, :pop, 5000]}}

    assert catch_exit(GenLoop.call({:global, name}, :pop, 5000)) ==
             {:calling_self, {GenLoop, :call, [{:global, name}, :pop, 5000]}}

    assert catch_exit(GenLoop.call({:via, :global, name}, :pop, 5000)) ==
             {:calling_self, {GenLoop, :call, [{:via, :global, name}, :pop, 5000]}}

    assert catch_exit(GenLoop.call(self(), :pop, 5000)) ==
             {:calling_self, {GenLoop, :call, [self(), :pop, 5000]}}

    assert catch_exit(GenLoop.call(pid, :noreply, 1)) ==
             {:timeout, {GenLoop, :call, [pid, :noreply, 1]}}

    assert catch_exit(GenLoop.call(nil, :pop, 5000)) ==
             {:noproc, {GenLoop, :call, [nil, :pop, 5000]}}

    assert catch_exit(GenLoop.call(stopped_pid, :pop, 5000)) ==
             {:noproc, {GenLoop, :call, [stopped_pid, :pop, 5000]}}

    assert catch_exit(GenLoop.call({:stack, :bogus_node}, :pop, 5000)) ==
             {{:nodedown, :bogus_node}, {GenLoop, :call, [{:stack, :bogus_node}, :pop, 5000]}}
  end

  test "nil name" do
    {:ok, pid} = GenLoop.start_link(Stack, [:hello], name: nil)
    assert Process.info(pid, :registered_name) == {:registered_name, []}
  end

  test "start/2" do
    {:ok, pid} = GenLoop.start(Stack, [:hello])
    {:links, links} = Process.info(self(), :links)
    refute pid in links
    GenLoop.stop(pid)
  end

  test "abcast/3" do
    {:ok, _} = GenLoop.start_link(Stack, [], name: :stack)

    assert GenLoop.abcast(:stack, {:push, :hello}) == :abcast
    assert GenLoop.call({:stack, node()}, :pop) == :hello

    assert GenLoop.abcast([node(), :foo@bar], :stack, {:push, :world}) == :abcast
    assert GenLoop.call(:stack, :pop) == :world

    GenLoop.stop(:stack)
  end

  test "multi_call/4" do
    {:ok, _} = GenLoop.start_link(Stack, [:hello, :world], name: :stack)

    assert GenLoop.multi_call(:stack, :pop) ==
             {[{node(), :hello}], []}

    assert GenLoop.multi_call([node(), :foo@bar], :stack, :pop) ==
             {[{node(), :world}], [:foo@bar]}

    GenLoop.stop(:stack)
  end

  test "whereis/1" do
    name = :whereis_server

    {:ok, pid} = GenLoop.start_link(Stack, [], name: name)
    assert GenLoop.whereis(name) == pid
    assert GenLoop.whereis({name, node()}) == pid
    assert GenLoop.whereis({name, :another_node}) == {name, :another_node}
    assert GenLoop.whereis(pid) == pid
    assert GenLoop.whereis(:whereis_bad_server) == nil

    {:ok, pid} = GenLoop.start_link(Stack, [], name: {:global, name})
    assert GenLoop.whereis({:global, name}) == pid
    assert GenLoop.whereis({:global, :whereis_bad_server}) == nil
    assert GenLoop.whereis({:via, :global, name}) == pid
    assert GenLoop.whereis({:via, :global, :whereis_bad_server}) == nil
  end

  test "stop/3" do
    {:ok, pid} = GenLoop.start(Stack, [])
    assert GenLoop.stop(pid, :normal) == :ok

    {:ok, _} = GenLoop.start(Stack, [], name: :stack_for_stop)
    assert GenLoop.stop(:stack_for_stop, :normal) == :ok
  end

  # Test of the plain_fsm features

  defmodule Fsm do
    use GenLoop

    def enter_loop(state) do
      receive state do
        rcall(from, :test_hibernate) ->
          reply(from, :ok)
          hibernate(__MODULE__, :waking_up, [state])

        rcall(from, :get_state) ->
          reply(from, state)
          enter_loop(state)

        rcall(from, {:setup_terminate_test, fun}) when is_function(fun, 1) ->
          false = Process.flag(:trap_exit, true)
          reply(from, :ok)
          enter_loop({:terminate_test, fun})

        # flush({:terminate_test, fun})
        rcall(from, {:call_fun, fun}) ->
          reply(from, fun.())
          enter_loop(state)
      end
    end

    # used for debug purposes
    def flush(state) do
      IO.puts("state : #{inspect(state)}")
      IO.puts("proc : #{inspect(Process.get())}")

      receive do
        msg ->
          IO.puts("message : #{inspect(msg)}")
          flush(state)
      end
    end

    def waking_up(_state) do
      enter_loop(:awaken)
    end

    def terminate(reason, {:terminate_test, fun}) when is_function(fun, 1) do
      fun.(reason)
    end

    def terminate(reason, state) do
      IO.puts("Bad termination with")
      "\n\treason = #{inspect(reason)}"
      "\n\tstate = #{inspect(state)}"
    end
  end

  test "hibernate and sys messages" do
    name = {:via, :global, :fsm_test}
    {:ok, _pid} = GenLoop.start_link(Fsm, :init_state, name: name, debug: [:trace])
    assert :init_state === GenLoop.call(name, :get_state)
    assert :ok === GenLoop.call(name, :test_hibernate)
    assert :awaken === GenLoop.call(name, :get_state)
    :sys.replace_state(name, fn {opts, _state} -> {opts, :replaced} end)
    assert :replaced === GenLoop.call(name, :get_state)
    assert :status === elem(:sys.get_status(name), 0)
  end

  test "terminate" do
    # We use a parent supervisor to start the Fsm. Then we kill terminate the
    # supervisor. The fsm is trapping exit, so its terminate function will be
    # called We will then wait to receive a message sent from the terminate
    # function
    name = {:via, :global, :fsm_killed}
    this = self()
    # start the process in sync so we wait to receive a ack
    children = [
      Supervisor.Spec.worker(Fsm, [:init_state, [name: name, debug: [:trace]]], id: TestChild)
    ]

    opts = [strategy: :one_for_one, name: GenLoopTest.Supervisor]
    {:ok, sup} = Supervisor.start_link(children, opts)
    # We set to trap exits and give our pid to receive the confirmation
    ref = make_ref()

    GenLoop.call(
      name,
      {:setup_terminate_test,
       fn reason ->
         send(this, {ref, reason})
       end}
    )

    Supervisor.terminate_child(sup, TestChild)

    receive do
      {^ref, :shutdown} -> :ok
      # always fail ;)
      other -> assert(other === {ref, :shutdown})
    after
      2000 -> assert(false = :child_called_terminate)
    end
  end
end

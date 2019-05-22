defmodule GenLoopExample do
  @moduledoc false
  use GenLoop,
    enter: :idle,
    restart: :transient

  require Logger

  def run_example() do
    {:ok, sup} = Supervisor.start_link([], strategy: :one_for_one)
    {:ok, _pid} = Supervisor.start_child(sup, __MODULE__.child_spec([]))
    name = {:global, __MODULE__}
    GenLoop.send(name, :a)
    GenLoop.send(name, :b)
    Process.sleep(600)
    GenLoop.send(name, :a)
    GenLoop.send(name, :b)
    GenLoop.send(name, :a)
    GenLoop.send(name, :b)
    Supervisor.terminate_child(sup, __MODULE__)

    :ignore = __MODULE__.start_link(:test_ignore)
    Process.sleep(3000)
  end

  def start_link(stack \\ []) do
    GenLoop.start_link(__MODULE__, [stack], name: {:global, __MODULE__})
  end

  def init([:test_ignore]) do
    :ignore
  end

  def init([:test_stop]) do
    {:stop, :testing}
  end

  def init([stack]) do
    Process.flag(:trap_exit, true)
    {:ok, stack}
  end

  def idle(stack) do
    Logger.debug("Entered state :idle.")

    receive stack do
      :a ->
        Logger.debug("Going to state hibernate before state :a ...")
        hibernate(__MODULE__, :a, [stack])

      :b ->
        Logger.debug("Going to state :b ...")
        b(stack)

      msg ->
        Logger.debug("Received msg: #{inspect(msg)}")
        idle(stack)
    end
  end

  def a(stack) do
    stack = [:a | stack]
    Logger.debug("Entered state :a.")

    receive do
      :b ->
        Logger.debug("Going to hibernate before state :b ...")
        hibernate(__MODULE__, :wakeup_to_b, [stack])
    after
      500 -> timeout(stack)
    end
  end

  def b(stack) do
    stack = [:b | stack]
    Logger.debug("Entered state :b.")

    receive do
      :a ->
        Logger.debug("Going to state :a ...")
        a(stack)
    after
      500 -> timeout(stack)
    end
  end

  def timeout(stack) do
    Logger.debug("Timeout, going to :idle ...")
    stack = [:timeout | stack]
    idle(stack)
  end

  def wakeup_to_b(stack) do
    stack = [:wake_up | stack]
    b(stack)
  end

  def terminate(reason, stack) do
    Logger.debug("Terminate, reason: #{inspect(reason)}, stack:")

    stack
    |> Enum.reverse()
    |> Enum.map(&IO.puts("  " <> to_string(&1)))
  end
end

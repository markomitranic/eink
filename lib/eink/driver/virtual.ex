if Code.ensure_loaded?(Plug) do
  defmodule EInk.Driver.Virtual do
    @moduledoc """
    A virtual driver that renders images to JPEG and broadcasts them via Registry.
    """
    use EInk.Driver
    require Logger

    alias EInk.Driver.Virtual.Server

    @impl EInk.Driver
    def new(opts \\ []) do
      # Support dynamic naming for tests
      supervisor_name = Keyword.get(opts, :supervisor_name, EInk.Driver.Virtual.Supervisor)

      # Start the virtual driver supervision tree
      case EInk.Driver.Virtual.Supervisor.start_link(opts) do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
      end

      {:ok, %{driver: :virtual, supervisor: supervisor_name}}
    end

    @impl EInk.Driver
    def close(state) do
      # Stop the supervision tree when closing
      if pid = Process.whereis(state.supervisor) do
        try do
          Supervisor.stop(pid)
        catch
          :exit, _ -> :ok
        end
      end

      :ok
    end

    @impl EInk.Driver
    def reset(state), do: {:ok, state}

    @impl EInk.Driver
    def init(state, _opts), do: {:ok, state}

    @impl EInk.Driver
    def draw(state, image, opts \\ []) do
      mode = Keyword.get(opts, :mode, :full)
      dither_enabled? = Keyword.get(opts, :dither, true)
      server_name = Keyword.get(opts, :server_name, EInk.Driver.Virtual.Server)

      # In virtual mode, we encode the %Dither{} to JPEG
      case image do
        %Dither{} = dither ->
          # Apply dithering to match hardware driver's behavior
          bit_depth = if mode == :grayscale, do: 2, else: 1

          dithered =
            if dither_enabled?, do: Dither.dither!(dither, bit_depth: bit_depth), else: dither

          {:ok, jpeg} = Dither.encode(dithered, :jpeg)
          Server.broadcast(server_name, jpeg)

        binary when is_binary(binary) ->
          Logger.debug("Virtual driver received binary data, skipping JPEG broadcast")
      end

      {:ok, state}
    end

    @impl EInk.Driver
    def sleep(state), do: {:ok, state}

    @impl EInk.Driver
    def wake(state), do: {:ok, state}
  end

  defmodule EInk.Driver.Virtual.Supervisor do
    use Supervisor

    def start_link(opts) do
      name = Keyword.get(opts, :supervisor_name, __MODULE__)
      Supervisor.start_link(__MODULE__, opts, name: name)
    end

    @impl true
    def init(opts) do
      registry_name = Keyword.get(opts, :registry_name, EInk.Driver.Virtual.Registry)
      server_name = Keyword.get(opts, :server_name, EInk.Driver.Virtual.Server)

      children = [
        {Registry, keys: :duplicate, name: registry_name},
        {EInk.Driver.Virtual.Server,
         Keyword.put(opts, :server_name, server_name)
         |> Keyword.put(:registry_name, registry_name)}
      ]

      Supervisor.init(children, strategy: :one_for_one)
    end
  end

  defmodule EInk.Driver.Virtual.Server do
    use GenServer
    require Logger

    @keepalive_interval 15_000

    def start_link(opts) do
      name = Keyword.get(opts, :server_name, __MODULE__)
      GenServer.start_link(__MODULE__, opts, name: name)
    end

    def broadcast(server, jpeg) do
      GenServer.cast(server, {:broadcast, jpeg})
    end

    def get_latest_frame(server) do
      GenServer.call(server, :get_latest_frame)
    end

    @impl true
    def init(opts) do
      registry_name = Keyword.get(opts, :registry_name, EInk.Driver.Virtual.Registry)
      schedule_keepalive()
      {:ok, %{latest_frame: nil, registry: registry_name}}
    end

    @impl true
    def handle_cast({:broadcast, jpeg}, state) do
      do_broadcast(jpeg, state.registry)
      {:noreply, %{state | latest_frame: jpeg}}
    end

    @impl true
    def handle_call(:get_latest_frame, _from, state) do
      {:reply, state.latest_frame, state}
    end

    @impl true
    def handle_info(:keepalive, state) do
      if state.latest_frame do
        do_broadcast(state.latest_frame, state.registry)
      end

      schedule_keepalive()
      {:noreply, state}
    end

    defp do_broadcast(jpeg, registry) do
      Registry.dispatch(registry, "frames", fn entries ->
        for {pid, _} <- entries, do: send(pid, {:frame, jpeg})
      end)
    end

    defp schedule_keepalive do
      Process.send_after(self(), :keepalive, @keepalive_interval)
    end
  end
end

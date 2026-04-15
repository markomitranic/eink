defmodule EInk do
  @moduledoc """
  EInk GenServer that manages the display driver and state.
  """
  use GenServer

  require Logger

  defstruct [:driver_mod, :driver_state, :width, :height, :palette]

  # Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def draw(image, opts \\ []) do
    GenServer.call(__MODULE__, {:draw, image, opts})
  end

  def clear(color \\ :white, opts \\ []) do
    GenServer.call(__MODULE__, {:clear, color, opts})
  end

  def sleep() do
    GenServer.call(__MODULE__, :sleep)
  end

  def wake() do
    GenServer.call(__MODULE__, :wake)
  end

  def capabilities() do
    GenServer.call(__MODULE__, :capabilities)
  end

  # GenServer Callbacks

  @impl true
  def init(_opts) do
    config = Application.get_all_env(:eink)
    driver_mod = Keyword.fetch!(config, :driver)
    width = Keyword.fetch!(config, :width)
    height = Keyword.fetch!(config, :height)
    palette = Keyword.get(config, :palette, :bw)
    driver_config = Keyword.get(config, :driver_config, [])

    {:ok, driver_state} = driver_mod.new(driver_config)

    state = %__MODULE__{
      driver_mod: driver_mod,
      driver_state: driver_state,
      width: width,
      height: height,
      palette: palette
    }

    # Initialize the hardware
    {:ok, driver_state} = driver_mod.reset(driver_state)
    {:ok, driver_state} = driver_mod.init(driver_state, config)

    {:ok, %{state | driver_state: driver_state}}
  end

  @impl true
  def handle_call({:draw, drawable, opts}, _from, state) do
    # Polymorphic transformation into a hardware-ready binary
    binary_data = EInk.Drawable.to_binary(drawable, state, opts)

    # Ensure width/height are in opts for driver consumption
    opts = 
      opts
      |> Keyword.put_new(:width, state.width)
      |> Keyword.put_new(:height, state.height)

    {:ok, driver_state} = state.driver_mod.draw(state.driver_state, binary_data, opts)
    {:reply, :ok, %{state | driver_state: driver_state}}
  end

  @impl true
  def handle_call({:clear, color, opts}, _from, state) do
    num_pixels = state.width * state.height

    {num_bytes, white_byte, black_byte} =
      case state.palette do
        :bw ->
          {div(num_pixels, 8), 0xFF, 0x00}

        :grayscale2 ->
          # 2 bits per pixel, 4 pixels per byte.
          # White is 3 (11), Black is 0 (00).
          # 0xFF is 11111111 (4 white pixels), 0x00 is 00000000 (4 black pixels).
          {div(num_pixels, 4), 0xFF, 0x00}

        _ ->
          {div(num_pixels, 8), 0xFF, 0x00}
      end

    data =
      case color do
        :white -> :binary.copy(<<white_byte>>, num_bytes)
        :black -> :binary.copy(<<black_byte>>, num_bytes)
        other -> raise "Invalid color `#{other}`. Supported colors are `:white` and `:black`"
      end

    Logger.debug("Clearing screen to #{color} using #{state.palette} palette")

    # Ensure width/height are in opts for driver consumption
    opts =
      opts
      |> Keyword.put_new(:width, state.width)
      |> Keyword.put_new(:height, state.height)

    {:ok, driver_state} = state.driver_mod.draw(state.driver_state, data, opts)
    {:reply, :ok, %{state | driver_state: driver_state}}
  end

  @impl true
  def handle_call(:sleep, _from, state) do
    {:ok, driver_state} = state.driver_mod.sleep(state.driver_state)
    {:reply, :ok, %{state | driver_state: driver_state}}
  end

  @impl true
  def handle_call(:wake, _from, state) do
    {:ok, driver_state} = state.driver_mod.wake(state.driver_state)
    {:reply, :ok, %{state | driver_state: driver_state}}
  end

  @impl true
  def handle_call(:capabilities, _from, state) do
    {:reply, %{width: state.width, height: state.height, palette: state.palette}, state}
  end

  @impl true
  def terminate(_reason, state) do
    if state.driver_mod && state.driver_state do
      state.driver_mod.close(state.driver_state)
    end
    :ok
  end
end

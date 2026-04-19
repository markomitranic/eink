defmodule EInk do
  @moduledoc """
  EInk GenServer that manages the display driver and state.
  """
  use GenServer

  require Logger

  defstruct [:driver_mod, :driver_state, :width, :height, :orientation, :dither]

  @type image_input :: {:file, Path.t()} | binary() | %Dither{}
  @type draw_opts :: [
          mode: :full | :fast | :grayscale,
          orientation: 0 | 90 | 180 | 270,
          dither: boolean()
        ]

  # Public API

  @doc """
  Starts the EInk GenServer.

  Options passed here override global application configuration.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Draws an image file from the given path.
  """
  @spec draw_file(Path.t(), draw_opts()) :: :ok | {:error, :file_not_found}
  def draw_file(path, opts \\ []) do
    if File.exists?(path) do
      path
      |> Dither.load!()
      |> draw(opts)
    else
      {:error, :file_not_found}
    end
  end

  @doc """
  Draws the provided image to the display.

  The image can be a raw (packed) binary or a `%Dither{}` struct.
  """
  @spec draw(image_input(), draw_opts()) :: :ok
  def draw(image, opts \\ []) do
    GenServer.call(__MODULE__, {:draw, image, opts})
  end

  @doc """
  Clears the screen to the specified color (defaults to `:white`).
  """
  @spec clear(:white | :black, draw_opts()) :: :ok
  def clear(color \\ :white, opts \\ []) do
    GenServer.call(__MODULE__, {:clear, color, opts})
  end

  @doc """
  Puts the display driver into deep sleep mode to save power.
  """
  @spec sleep() :: :ok
  def sleep() do
    GenServer.call(__MODULE__, :sleep)
  end

  @doc """
  Wakes the display driver from deep sleep mode.
  """
  @spec wake() :: :ok
  def wake() do
    GenServer.call(__MODULE__, :wake)
  end

  @doc """
  Returns the current capabilities and configuration of the display.
  """
  @spec capabilities() :: %{width: integer(), height: integer()}
  def capabilities() do
    GenServer.call(__MODULE__, :capabilities)
  end

  # GenServer Callbacks

  @doc false
  @impl true
  def init(opts) do
    # Merge global application env with local opts (passed to start_link)
    config =
      Application.get_all_env(:eink)
      |> Keyword.merge(opts)

    driver_mod = Keyword.fetch!(config, :driver)
    width = Keyword.fetch!(config, :width)
    height = Keyword.fetch!(config, :height)
    orientation = Keyword.get(config, :orientation, 0)
    dither = Keyword.get(config, :dither, true)
    driver_config = Keyword.get(config, :driver_config, [])

    {:ok, driver_state} = driver_mod.new(driver_config)

    state = %__MODULE__{
      driver_mod: driver_mod,
      driver_state: driver_state,
      width: width,
      height: height,
      orientation: orientation,
      dither: dither
    }

    # Initialize the hardware
    {:ok, driver_state} = driver_mod.reset(driver_state)

    init_opts = Keyword.merge(config, driver_config)
    {:ok, driver_state} = driver_mod.init(driver_state, init_opts)

    {:ok, %{state | driver_state: driver_state}}
  end

  @doc false
  @impl true
  def handle_call({:draw, image, opts}, _from, state) do
    # Resolve mode: default to :full
    mode = Keyword.get(opts, :mode, :full)

    # Merge state defaults with call-time overrides
    opts =
      [orientation: state.orientation, dither: state.dither]
      |> Keyword.merge(opts)

    # Preprocess image into binary or %Dither{}
    processed =
      case image do
        binary when is_binary(binary) ->
          binary

        %Dither{} = dither ->
          preprocess_dither(dither, state, opts)

        other ->
          raise "Unsupported image type for EInk.draw: #{inspect(other)}"
      end

    # Pass mode, width, height to driver
    opts =
      opts
      |> Keyword.put(:mode, mode)
      |> Keyword.put_new(:width, state.width)
      |> Keyword.put_new(:height, state.height)

    {:ok, driver_state} = state.driver_mod.draw(state.driver_state, processed, opts)
    {:reply, :ok, %{state | driver_state: driver_state}}
  end

  @doc false
  @impl true
  def handle_call({:clear, color, opts}, _from, state) do
    mode = Keyword.get(opts, :mode, :full)
    num_pixels = state.width * state.height

    # Merge state defaults with call-time overrides
    opts =
      [orientation: state.orientation, dither: state.dither]
      |> Keyword.merge(opts)

    # For clear, we generate raw binaries based on mode
    data =
      case mode do
        :grayscale ->
          # For grayscale, we return a %Dither{} struct so the driver/utils can handle the mapping
          val = if color == :white, do: 255, else: 0
          raw = :binary.copy(<<val>>, num_pixels)
          Dither.from_raw!(raw, state.width, state.height)

        _ ->
          num_bytes = div(num_pixels, 8)
          byte = if color == :white, do: 0xFF, else: 0x00
          :binary.copy(<<byte>>, num_bytes)
      end

    Logger.debug("Clearing screen to #{color} using #{mode} mode")

    opts =
      opts
      |> Keyword.put(:mode, mode)
      |> Keyword.put_new(:width, state.width)
      |> Keyword.put_new(:height, state.height)

    {:ok, driver_state} = state.driver_mod.draw(state.driver_state, data, opts)
    {:reply, :ok, %{state | driver_state: driver_state}}
  end

  @doc false
  @impl true
  def handle_call(:sleep, _from, state) do
    {:ok, driver_state} = state.driver_mod.sleep(state.driver_state)
    {:reply, :ok, %{state | driver_state: driver_state}}
  end

  @doc false
  @impl true
  def handle_call(:wake, _from, state) do
    {:ok, driver_state} = state.driver_mod.wake(state.driver_state)
    {:reply, :ok, %{state | driver_state: driver_state}}
  end

  @doc false
  @impl true
  def handle_call(:capabilities, _from, state) do
    {:reply, %{width: state.width, height: state.height}, state}
  end

  @doc false
  defp preprocess_dither(dither, state, opts) do
    orientation = Keyword.get(opts, :orientation, state.orientation)

    dither
    |> maybe_rotate(orientation)
    |> Dither.resize!(state.width, state.height)
    |> Dither.grayscale!()
  end

  @doc false
  defp maybe_rotate(dither, 0), do: dither

  @doc false
  defp maybe_rotate(dither, orientation) when orientation in [90, 180, 270] do
    Dither.rotate!(dither, orientation)
  end

  @doc false
  @impl true
  def terminate(_reason, state) do
    if state.driver_mod && state.driver_state do
      state.driver_mod.close(state.driver_state)
    end

    :ok
  end
end

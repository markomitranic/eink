defmodule EInk.Driver.UC8179 do
  @moduledoc """
  Driver for UC8179 e-ink displays.
  """
  use EInk.Driver

  alias EInk.Driver.SpiDriver
  alias EInk.Driver.UC8179.Settings
  alias Circuits.GPIO

  require Logger

  @impl EInk.Driver
  def new(opts \\ []) do
    spi_driver = SpiDriver.open(opts)

    {:ok, %{driver: spi_driver, boot_flag: false, current_lut: nil, current_mode: nil}}
  end

  @impl EInk.Driver
  def close(state) do
    SpiDriver.close(state.driver)
  end

  @impl EInk.Driver
  def reset(state) do
    if state.driver.debug, do: Logger.debug("UC8179 hardware reset")

    :ok = GPIO.write(state.driver.reset, 1)
    Process.sleep(10)
    :ok = GPIO.write(state.driver.reset, 0)
    Process.sleep(100)
    :ok = GPIO.write(state.driver.reset, 1)
    Process.sleep(100)

    :ok = SpiDriver.wait_for_busy(state.driver, polarity: :active_low)

    {:ok, %{state | boot_flag: false, current_lut: nil, current_mode: nil}}
  end

  @impl EInk.Driver
  def init(state, opts \\ []) do
    width = Keyword.fetch!(opts, :width)
    height = Keyword.fetch!(opts, :height)

    if state.driver.debug, do: Logger.debug("UC8179 init for #{width}x#{height}")

    state = apply_init(state, :full, {width, height})

    # Clear buffer 0x10
    SpiDriver.write(state.driver, 0x10, :binary.copy(<<0xFF>>, div(width * height, 8)))

    {:ok, state}
  end

  @impl EInk.Driver
  def draw(state, image, opts \\ []) do
    mode = Keyword.get(opts, :mode, :full)
    width = Keyword.fetch!(opts, :width)
    height = Keyword.fetch!(opts, :height)
    res = {width, height}

    if state.driver.debug, do: Logger.debug("UC8179 draw mode: #{mode}")

    # Pre-process data
    data =
      case image do
        %Dither{} = dither -> EInk.Utils.to_packed_binary(dither, mode)
        binary when is_binary(binary) -> binary
      end

    # Check for mode change
    state = if state.current_mode != mode, do: apply_init(state, mode, res), else: state

    if state.boot_flag do
      # Set VCOM and Data Interval for subsequent refreshes
      # We check the init sequence for a specific resolution to determine data interval
      # (This is a bit hacky, kept from original driver)
      init_commands = Settings.get_init(mode, res)

      data_interval =
        if init_commands |> List.keyfind(0x61, 0) == {0x61, <<0x03, 0x20, 0x01, 0xE0>>},
          do: <<0xA9, 0x07>>,
          else: <<0xD7, 0x07>>

      SpiDriver.write(state.driver, 0x50, data_interval)
    end

    case mode do
      :grayscale ->
        {buf10, buf13} = data
        SpiDriver.write(state.driver, 0x10, buf10)
        SpiDriver.write(state.driver, 0x13, buf13)

      _bw ->
        SpiDriver.write(state.driver, 0x13, data)
    end

    state = if state.current_lut != mode, do: load_lut(state, mode, res), else: state

    SpiDriver.write(state.driver, 0x17, <<0xA5>>)
    :ok = SpiDriver.wait_for_busy(state.driver, polarity: :active_low)

    # Update reference buffer for partial refreshes
    if mode != :grayscale do
      SpiDriver.write(state.driver, 0x10, data)
    end

    {:ok, %{state | boot_flag: true}}
  end

  defp apply_init(state, mode, resolution) do
    commands = Settings.get_init(mode, resolution)

    for {reg, data} <- commands do
      SpiDriver.write(state.driver, reg, data)
    end

    %{state | current_mode: mode, current_lut: nil}
  end

  defp load_lut(state, mode, resolution) do
    case Settings.get_lut(mode, resolution) do
      nil ->
        :ok

      commands ->
        for {reg, data} <- commands do
          SpiDriver.write(state.driver, reg, data)
        end
    end

    %{state | current_lut: mode}
  end

  @impl EInk.Driver
  def sleep(state) do
    if state.driver.debug, do: Logger.debug("UC8179 sleep")

    SpiDriver.write(state.driver, 0x07, <<0xA5>>)
    {:ok, state}
  end

  @impl EInk.Driver
  def wake(state) do
    if state.driver.debug, do: Logger.debug("UC8179 wake")

    {:ok, state} = reset(state)
    {:ok, state}
  end
end

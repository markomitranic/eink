defmodule EInk.Driver.UC8253C do
  @moduledoc """
  Driver for UC8253C e-ink display.
  """
  use EInk.Driver

  alias EInk.Driver.SpiDriver
  alias EInk.Driver.UC8253C.Settings
  alias Circuits.GPIO

  require Logger

  @impl EInk.Driver
  def new(opts \\ []) do
    spi_driver = SpiDriver.open(opts)

    {:ok,
     %{driver: spi_driver, boot_flag: false, lut_flag: 0, current_lut: nil, current_mode: nil}}
  end

  @impl EInk.Driver
  def close(state) do
    SpiDriver.close(state.driver)
  end

  @impl EInk.Driver
  def reset(state) do
    if state.driver.debug, do: Logger.debug("UC8253C hardware reset")

    :ok = GPIO.write(state.driver.reset, 1)
    Process.sleep(10)
    :ok = GPIO.write(state.driver.reset, 0)
    Process.sleep(100)
    :ok = GPIO.write(state.driver.reset, 1)
    Process.sleep(100)

    {:ok, %{state | boot_flag: false, lut_flag: 0, current_lut: nil, current_mode: nil}}
  end

  @impl EInk.Driver
  def init(state, opts \\ []) do
    width = Keyword.fetch!(opts, :width)
    height = Keyword.fetch!(opts, :height)

    if state.driver.debug, do: Logger.debug("UC8253C init")

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

    if state.driver.debug, do: Logger.debug("UC8253C draw mode: #{mode}")

    # Pre-process data
    data =
      case image do
        %Dither{} = dither -> EInk.Utils.to_packed_binary(dither, mode)
        binary when is_binary(binary) -> binary
      end

    # Check for mode change
    state = if state.current_mode != mode, do: apply_init(state, mode, res), else: state

    if state.boot_flag do
      SpiDriver.write(state.driver, 0x50, <<0xD7>>)
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

    # Update reference buffer for partial updates
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
    lut_data = Settings.get_lut(mode, resolution)

    if lut_data do
      lut_map = Map.new(lut_data)

      SpiDriver.write(state.driver, 0x20, lut_map[0x20])
      SpiDriver.write(state.driver, 0x21, lut_map[0x21])
      SpiDriver.write(state.driver, 0x24, lut_map[0x24])

      {reg22, reg23, new_lut_flag} =
        if state.lut_flag == 0 do
          {0x22, 0x23, 1}
        else
          {0x23, 0x22, 0}
        end

      SpiDriver.write(state.driver, reg22, lut_map[0x22])
      SpiDriver.write(state.driver, reg23, lut_map[0x23])

      %{state | lut_flag: new_lut_flag, current_lut: mode}
    else
      %{state | current_lut: mode}
    end
  end

  @impl EInk.Driver
  def sleep(state) do
    if state.driver.debug, do: Logger.debug("UC8253C sleep")

    SpiDriver.write(state.driver, 0x07, <<0xA5>>)
    {:ok, state}
  end

  @impl EInk.Driver
  def wake(state) do
    if state.driver.debug, do: Logger.debug("UC8253C wake")

    {:ok, state} = reset(state)
    {:ok, state}
  end
end

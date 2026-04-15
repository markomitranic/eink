defmodule EInk.Driver.UC8179 do
  @moduledoc """
  Unified driver for UC8179 e-ink displays.
  """
  use EInk.Driver

  alias EInk.Driver.SpiDriver
  alias Circuits.GPIO

  require Logger

  @configs %{
    {648, 480} => %{
      init: [
        {0x00, <<0x3F, 0x09>>},
        {0x01, <<0x03, 0x17, 0x3F, 0x3F, 0x03>>},
        {0x06, <<0x17, 0x17, 0x3D, 0x3C>>},
        {0x30, <<0x07>>},
        {0x61, <<0x02, 0x88, 0x01, 0xE0>>},
        {0x65, <<0x00, 0x10, 0x00, 0x00>>},
        {0x82, <<0x18>>},
        {0x50, <<0x29, 0x07>>},
        {0x52, <<0x02>>},
        {0x60, <<0x22>>},
        {0xE3, <<0x88>>}
      ],
      lut: %{
        full: %{
          0x20 => <<0x00, 0x1E, 0x1E, 0x1E, 0x01, 0x01>> <> :binary.copy(<<0x00>>, 36),
          0x21 => <<0x60, 0x1E, 0x1E, 0x1E, 0x01, 0x01>> <> :binary.copy(<<0x00>>, 36),
          0x22 => <<0x60, 0x1E, 0x1E, 0x1E, 0x01, 0x01>> <> :binary.copy(<<0x00>>, 36),
          0x23 => <<0x64, 0x1E, 0x1E, 0x1E, 0x01, 0x01>> <> :binary.copy(<<0x00>>, 36),
          0x24 => <<0x24, 0x1E, 0x1E, 0x1E, 0x01, 0x01>> <> :binary.copy(<<0x00>>, 36)
        },
        partial: %{
          0x20 => <<0x00, 0x14, 0x01, 0x00, 0x00, 0x01>> <> :binary.copy(<<0x00>>, 36),
          0x21 => <<0x00, 0x14, 0x01, 0x00, 0x00, 0x01>> <> :binary.copy(<<0x00>>, 36),
          0x22 => <<0x80, 0x14, 0x01, 0x00, 0x00, 0x01>> <> :binary.copy(<<0x00>>, 36),
          0x23 => <<0x40, 0x14, 0x01, 0x00, 0x00, 0x01>> <> :binary.copy(<<0x00>>, 36),
          0x24 => <<0x00, 0x14, 0x01, 0x00, 0x00, 0x01>> <> :binary.copy(<<0x00>>, 36)
        }
      }
    },
    {800, 480} => %{
      init: [
        {0x00, <<0x3F, 0x0D>>},
        {0x01, <<0x03, 0x17, 0x3F, 0x3F, 0x03>>},
        {0x06, <<0x17, 0x17, 0x3D, 0x3C>>},
        {0x30, <<0x09>>},
        {0x61, <<0x03, 0x20, 0x01, 0xE0>>},
        {0x65, <<0x00, 0x00, 0x00, 0x00>>},
        {0x82, <<0x00>>},
        {0x50, <<0x29, 0x07>>},
        {0x52, <<0x02>>},
        {0x60, <<0x22>>},
        {0xE3, <<0x88>>}
      ],
      lut: %{
        full: %{
          0x20 => <<0x00, 0x14, 0x14, 0x14, 0x00, 0x01>> <> :binary.copy(<<0x00>>, 42),
          0x21 => <<0x60, 0x14, 0x14, 0x14, 0x00, 0x01>> <> :binary.copy(<<0x00>>, 42),
          0x22 => <<0x20, 0x14, 0x14, 0x14, 0x00, 0x01>> <> :binary.copy(<<0x00>>, 42),
          0x23 => <<0x64, 0x14, 0x14, 0x14, 0x00, 0x01>> <> :binary.copy(<<0x00>>, 42),
          0x24 => <<0x24, 0x14, 0x14, 0x14, 0x00, 0x01>> <> :binary.copy(<<0x00>>, 42)
        },
        partial: %{
          0x20 => <<0x00, 0x14, 0x00, 0x00, 0x00, 0x01>> <> :binary.copy(<<0x00>>, 42),
          0x21 => <<0x00, 0x14, 0x00, 0x00, 0x00, 0x01>> <> :binary.copy(<<0x00>>, 42),
          0x22 => <<0x80, 0x14, 0x00, 0x00, 0x00, 0x01>> <> :binary.copy(<<0x00>>, 42),
          0x23 => <<0x40, 0x14, 0x00, 0x00, 0x00, 0x01>> <> :binary.copy(<<0x00>>, 42),
          0x24 => <<0x00, 0x14, 0x00, 0x00, 0x00, 0x01>> <> :binary.copy(<<0x00>>, 42)
        }
      }
    }
  }

  @impl EInk.Driver
  def new(opts \\ []) do
    spi_driver = SpiDriver.open(opts)

    {:ok, %{driver: spi_driver, boot_flag: false, current_lut: nil, config: nil}}
  end

  @impl EInk.Driver
  def close(state) do
    SpiDriver.close(state.driver)
  end

  @impl EInk.Driver
  def reset(state) do
    if state.driver.debug, do: Logger.debug("UC8179 unified hardware reset")

    :ok = GPIO.write(state.driver.reset, 1)
    Process.sleep(10)
    :ok = GPIO.write(state.driver.reset, 0)
    Process.sleep(100)
    :ok = GPIO.write(state.driver.reset, 1)
    Process.sleep(100)

    :ok = SpiDriver.wait_for_busy(state.driver, polarity: :active_low)

    {:ok, %{state | boot_flag: false, current_lut: nil}}
  end

  @impl EInk.Driver
  def init(state, opts \\ []) do
    width = Keyword.fetch!(opts, :width)
    height = Keyword.fetch!(opts, :height)

    config = Map.get(@configs, {width, height}) || raise "No UC8179 config for #{width}x#{height}"

    if state.driver.debug, do: Logger.debug("UC8179 init for #{width}x#{height}")

    for {reg, data} <- config.init do
      SpiDriver.write(state.driver, reg, data)
    end

    # Clear buffer 0x10
    SpiDriver.write(state.driver, 0x10, :binary.copy(<<0xFF>>, div(width * height, 8)))

    {:ok, %{state | config: config}}
  end

  @impl EInk.Driver
  def draw(state, image, opts \\ []) do
    if state.driver.debug, do: Logger.debug("UC8179 unified draw")

    width = Keyword.fetch!(opts, :width)
    height = Keyword.fetch!(opts, :height)
    gs2_size = div(width * height, 4)

    if state.boot_flag do
      # Set VCOM and Data Interval for subsequent refreshes
      data_interval =
        if state.config.init |> List.keyfind(0x61, 0) == {0x61, <<0x03, 0x20, 0x01, 0xE0>>},
          do: <<0xA9, 0x07>>,
          else: <<0xD7, 0x07>>

      SpiDriver.write(state.driver, 0x50, data_interval)
    end

    # Handle multi-buffer data for grayscale
    case byte_size(image) do
      size when size == gs2_size ->
        # This is a standardized 2-bit binary (4 pixels per byte)
        {buf10, buf13} = split_grayscale(image)
        SpiDriver.write(state.driver, 0x10, buf10)
        SpiDriver.write(state.driver, 0x13, buf13)

      _ ->
        # Standard 1-bit BW or already split binary
        SpiDriver.write(state.driver, 0x13, image)
    end

    refresh_type = Keyword.get(opts, :refresh_type, :full)

    if state.current_lut != refresh_type do
      load_lut(state, state.config.lut[refresh_type] || state.config.lut.full)
    end

    SpiDriver.write(state.driver, 0x17, <<0xA5>>)
    :ok = SpiDriver.wait_for_busy(state.driver, polarity: :active_low)

    # Update reference buffer for partial refreshes
    case byte_size(image) do
      size when size == gs2_size -> :ok
      _ -> SpiDriver.write(state.driver, 0x10, image)
    end

    {:ok, %{state | boot_flag: true, current_lut: refresh_type}}
  end

  defp split_grayscale(image) do
    # Each byte has 4 pixels, 2 bits each.
    # Output: two binaries, each 1 bit per pixel.
    # Mapping for 4-level grayscale:
    # 0 (Black): buf10=1, buf13=0
    # 1 (Dark Gray): buf10=1, buf13=1
    # 2 (Light Gray): buf10=0, buf13=1
    # 3 (White): buf10=0, buf13=0

    for <<p0::2, p1::2, p2::2, p3::2, p4::2, p5::2, p6::2, p7::2 <- image>>,
      reduce: {<<>>, <<>>} do
      {b10, b13} ->
        v10 = <<
          (if p0 < 2, do: 1, else: 0)::1,
          (if p1 < 2, do: 1, else: 0)::1,
          (if p2 < 2, do: 1, else: 0)::1,
          (if p3 < 2, do: 1, else: 0)::1,
          (if p4 < 2, do: 1, else: 0)::1,
          (if p5 < 2, do: 1, else: 0)::1,
          (if p6 < 2, do: 1, else: 0)::1,
          (if p7 < 2, do: 1, else: 0)::1
        >>

        v13 = <<
          (if p0 > 0 and p0 < 3, do: 1, else: 0)::1,
          (if p1 > 0 and p1 < 3, do: 1, else: 0)::1,
          (if p2 > 0 and p2 < 3, do: 1, else: 0)::1,
          (if p3 > 0 and p3 < 3, do: 1, else: 0)::1,
          (if p4 > 0 and p4 < 3, do: 1, else: 0)::1,
          (if p5 > 0 and p5 < 3, do: 1, else: 0)::1,
          (if p6 > 0 and p6 < 3, do: 1, else: 0)::1,
          (if p7 > 0 and p7 < 3, do: 1, else: 0)::1
        >>

        {b10 <> v10, b13 <> v13}
    end
  end

  @impl EInk.Driver
  def sleep(state) do
    if state.driver.debug, do: Logger.debug("UC8179 unified sleep")

    SpiDriver.write(state.driver, 0x07, <<0xA5>>)
    {:ok, state}
  end

  @impl EInk.Driver
  def wake(state) do
    if state.driver.debug, do: Logger.debug("UC8179 unified wake")

    {:ok, state} = reset(state)
    {:ok, state}
  end

  defp load_lut(state, lut) do
    for {reg, lut_data} <- lut do
      SpiDriver.write(state.driver, reg, lut_data)
    end
  end
end

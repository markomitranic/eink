defmodule EInk.MockDriver do
  use EInk.Driver

  @impl true
  def new(_opts), do: {:ok, %{test_pid: nil}}

  @impl true
  def close(_state), do: :ok

  @impl true
  def reset(state), do: {:ok, state}

  @impl true
  def init(state, opts) do
    {:ok, %{state | test_pid: opts[:test_pid]}}
  end

  @impl true
  def draw(state, data, opts) do
    if state.test_pid, do: send(state.test_pid, {:driver_draw, data, opts})
    {:ok, state}
  end

  @impl true
  def sleep(state), do: {:ok, state}

  @impl true
  def wake(state), do: {:ok, state}
end

defmodule EInkTest do
  use ExUnit.Case

  setup do
    Application.put_env(:eink, :driver, EInk.MockDriver)
    Application.put_env(:eink, :width, 400)
    Application.put_env(:eink, :height, 300)
    Application.put_env(:eink, :driver_config, [
      test_pid: self()
    ])

    on_exit(fn ->
      Application.delete_env(:eink, :driver)
      Application.delete_env(:eink, :width)
      Application.delete_env(:eink, :height)
      Application.delete_env(:eink, :driver_config)
    end)

    start_supervised!(EInk)
    :ok
  end

  test "capabilities returns configured dimensions" do
    caps = EInk.capabilities()
    assert caps.width == 400
    assert caps.height == 300
  end

  test "draw passes %Dither{} to driver for non-binary input" do
    # Create a 400x300 raw grayscale binary (8-bit)
    raw = :binary.copy(<<128>>, 400 * 300)
    dither = Dither.from_raw!(raw, 400, 300)
    EInk.draw(dither)
    assert_receive {:driver_draw, %Dither{}, opts}
    assert opts[:mode] == :full
  end

  test "draw passes binary directly to driver" do
    binary = <<0, 1, 2>>
    EInk.draw(binary)
    assert_receive {:driver_draw, ^binary, opts}
    assert opts[:mode] == :full
  end

  test "draw respects orientation for %Dither{} input" do
    Application.put_env(:eink, :orientation, 90)
    # Restart EInk to pick up new config
    stop_supervised(EInk)
    start_supervised!(EInk)

    raw = :binary.copy(<<128>>, 400 * 300)
    dither = Dither.from_raw!(raw, 400, 300)
    
    EInk.draw(dither)
    
    # If rotation happens, the driver should receive a Dither struct 
    # (or its processed result) that has been transformed.
    # In MockDriver, we receive the 'processed' variable.
    assert_receive {:driver_draw, %Dither{}, _opts}
    
    # Reset orientation for other tests
    Application.put_env(:eink, :orientation, 0)
    stop_supervised(EInk)
    start_supervised!(EInk)
  end

  test "draw ignores orientation for binary input" do
    Application.put_env(:eink, :orientation, 90)
    stop_supervised(EInk)
    start_supervised!(EInk)

    binary = <<0, 1, 2>>
    EInk.draw(binary)
    
    # Binary should go straight through untouched
    assert_receive {:driver_draw, ^binary, _}

    Application.put_env(:eink, :orientation, 0)
    stop_supervised(EInk)
    start_supervised!(EInk)
  end

  test "clear passes %Dither{} or binary to driver depending on mode" do
    EInk.clear(:white, mode: :grayscale)
    assert_receive {:driver_draw, %Dither{}, opts}
    assert opts[:mode] == :grayscale

    EInk.clear(:white, mode: :full)
    assert_receive {:driver_draw, binary, opts} when is_binary(binary)
    assert opts[:mode] == :full
  end

  test "draw respects per-call orientation override" do
    # Global orientation is 0 by default
    raw = :binary.copy(<<128>>, 400 * 300)
    dither = Dither.from_raw!(raw, 400, 300)
    
    # Pass override orientation
    EInk.draw(dither, orientation: 180)
    
    # Verify the call succeeded and driver received the data
    assert_receive {:driver_draw, %Dither{}, _opts}
  end

  test "start_link options override application environment" do
    # Default width/height in setup is 400x300
    # Stop the one started in setup so we can start a new one with the same name
    stop_supervised(EInk)
    
    override_opts = [
      driver: EInk.MockDriver,
      width: 800,
      height: 600,
      driver_config: [test_pid: self()]
    ]

    {:ok, _pid} = start_supervised({EInk, override_opts})
    
    caps = EInk.capabilities()
    assert caps.width == 800
    assert caps.height == 600
  end
end

defmodule EInk.UtilsTest do
  use ExUnit.Case
  alias EInk.Utils

  test "pack_bw packs pixels correctly" do
    pixels = <<255, 0, 255, 0, 255, 0, 255, 0>>
    assert Utils.pack_bw(pixels) == <<0xAA>>
  end

  test "pack_grayscale returns planar tuple" do
    # 8 pixels: White, Black, Light Gray, Dark Gray, White, Black, Light Gray, Dark Gray
    # Values: 255, 0, 170, 85, 255, 0, 170, 85
    pixels = <<255, 0, 170, 85, 255, 0, 170, 85>>
    {ch1, ch2} = Utils.pack_grayscale(pixels)
    
    # White (255): {0, 0}
    # Black (0): {1, 1}
    # Light Gray (170): {1, 0}
    # Dark Gray (85): {0, 1}
    
    # ch1: 0 1 1 0 0 1 1 0 = 0x66
    # ch2: 0 1 0 1 0 1 0 1 = 0x55
    
    assert ch1 == <<0x66>>
    assert ch2 == <<0x55>>
  end
end

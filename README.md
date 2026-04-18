# EInk

## Motivation

E-Ink displays offer a unique set of challenges and opportunities for embedded
systems. Their high contrast, low power consumption, and paper-like readability
make them ideal for dashboards, labels, and slow-refresh interfaces. However,
interacting with these displays often involves low-level SPI communication,
complex look-up tables (LUTs), and specific pixel-packing requirements. This
library aims to provide a high-level, idiomatic Elixir interface that abstracts
away these hardware details, allowing developers to focus on building beautiful,
efficient interfaces.

## Usage

To get started, configure the library in your application environment. You will
need to specify your display dimensions and the driver module matching your
hardware.

```elixir
config :eink,
  driver: EInk.Driver.UC8276,
  width: 800,
  height: 480,
  orientation: 0,
  dither: true,
  driver_config: [
    spi_device: "spidev0.0",
    reset_pin: 17,
    busy_pin: 18,
    dc_pin: 27
  ]
```

After adding configuration, add `EInk` to your application's supervision tree:

```elixir
def start(_type, _args) do
  children = [
    # Other children here
    EInk
  ]

  opts = [strategy: :one_for_one, name: MyApp.Supervisor]
  Supervisor.start_link(children, opts)
end
```

### Common Functions

The primary way to update the display is through the draw function. It accepts
file paths, raw binaries, or `%Dither{}` structs.

Update the screen with an image file:

```elixir
EInk.draw({:file, "path/to/image.png"})
```

Clear the screen to white:

```elixir
EInk.clear(:white)
```

You can override global configuration options on a per-call basis. For example,
to rotate a specific image or disable dithering:

```elixir
Dither.load!("path/to/file.jpg")
|> EInk.draw(orientation: 90, dither: false)
```

### Managing Display Power

E-Ink displays can be put into deep sleep to save power between updates.

```elixir
EInk.sleep()
EInk.wake()
```

## Virtual Driver

For development and testing without physical hardware, the library includes a
virtual driver. This driver renders the display output to a JPEG stream that can
be viewed in a web browser.

Enable the virtual driver in your configuration:

```elixir
config :eink,
  driver: EInk.Driver.Virtual,
  width: 800,
  height: 480
```

You can then serve the live display stream using the provided Plug. In a Phoenix
router, you can mount it like this:

```elixir
scope "/" do
  get "/eink/stream", EInk.Plug.VirtualStream, []
end
```

The stream is a standard MJPEG multipart response and can be embedded in any
webpage using a simple `img` tag, like the following:

```html
<img src="/eink/stream" width="800" height="480" />
```

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `eink` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:eink, "~> 0.1.0"}
  ]
end
```

Documentation can be found at <https://hexdocs.pm/eink>.

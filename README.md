# EInk

Draw images to e-ink displays with Elixir.

## Motivation

This package was developed to provide a unified API for drawing images to EInk
displays. Originally created for the
[Goatmire 2025 name badge](https://github.com/protolux-electronics/name_badge),
development is now primarily in support of the project that grew out of that -
the [Nerves Starter Kit](https://github.com/protolux-electronics/nsk). However,
I'm happy to add support for any alternative displays, not just the ones used in
these projects. Feel free to open an issue or get in contact for more
information.

## Configuration and Startup

EInk can be configured either through your application's `config/config.exs` or
by passing options directly when starting the process.

### Application Configuration

To use the global application configuration, add the following to your
`config.exs`:

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

Then add `EInk` to your application's supervision tree:

```elixir
def start(_type, _args) do
  children = [
    EInk
  ]

  opts = [strategy: :one_for_one, name: MyApp.Supervisor]
  Supervisor.start_link(children, opts)
end
```

### Manual Startup

If you want to start the driver manually with specific settings, you can pass
the configuration directly to `start_link/1`. Options passed here will override
any global application environment settings.

```elixir
EInk.start_link(
  driver: EInk.Driver.Virtual,
  width: 800,
  height: 480
)
```

You can also use this approach in a supervision tree by passing the options to
the child spec:

```elixir
children = [
  {EInk, [width: 400, height: 300]}
]
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

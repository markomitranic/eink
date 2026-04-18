if Code.ensure_loaded?(Plug) do
  defmodule EInk.Plug.VirtualStream do
    @moduledoc """
    A Plug that streams MJPEG data from the virtual e-ink driver.
    """
    import Plug.Conn

    alias EInk.Driver.Virtual.Server

    @boundary "eink_frame"

    def init(opts) do
      registry = Keyword.get(opts, :registry_name, EInk.Driver.Virtual.Registry)
      server = Keyword.get(opts, :server_name, EInk.Driver.Virtual.Server)
      [registry_name: registry, server_name: server]
    end

    def call(conn, opts) do
      registry_name = opts[:registry_name]
      server_name = opts[:server_name]

      conn =
        conn
        |> put_resp_header("Content-Type", "multipart/x-mixed-replace; boundary=#{@boundary}")
        |> send_chunked(200)

      # Register for frame updates
      Registry.register(registry_name, "frames", [])

      # Send the latest frame immediately
      if latest = Server.get_latest_frame(server_name) do
        send_frame(conn, latest)
      end

      # Enter streaming loop
      stream_loop(conn)
    end

    defp stream_loop(conn) do
      receive do
        {:frame, jpeg} ->
          case send_frame(conn, jpeg) do
            {:ok, conn} ->
              stream_loop(conn)

            {:error, :closed} ->
              conn
          end
      end
    end

    defp send_frame(conn, jpeg) do
      chunk_data = [
        "--#{@boundary}\r\n",
        "Content-Type: image/jpeg\r\n",
        "Content-Length: #{byte_size(jpeg)}\r\n",
        "\r\n",
        jpeg,
        "\r\n"
      ]

      chunk(conn, chunk_data)
    end
  end
end

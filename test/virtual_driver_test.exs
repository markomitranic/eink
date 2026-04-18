defmodule EInk.Driver.VirtualTest do
  use ExUnit.Case

  alias EInk.Driver.Virtual

  setup do
    # Generate unique names for this test
    id = System.unique_integer([:positive])
    supervisor_name = Module.concat([Virtual, Supervisor, "Test#{id}"])
    registry_name = Module.concat([Virtual, Registry, "Test#{id}"])
    server_name = Module.concat([Virtual, Server, "Test#{id}"])

    opts = [
      supervisor_name: supervisor_name,
      registry_name: registry_name,
      server_name: server_name
    ]

    {:ok, state} = Virtual.new(opts)
    
    on_exit(fn ->
      Virtual.close(state)
    end)

    {:ok, %{driver_state: state, opts: opts}}
  end

  test "new/1 starts the supervision tree", %{opts: opts} do
    assert Process.whereis(opts[:supervisor_name])
    assert Process.whereis(opts[:registry_name])
    assert Process.whereis(opts[:server_name])
  end

  test "Server stores latest frame", %{opts: opts} do
    server = opts[:server_name]
    jpeg = <<0xFF, 0xD8, 0xFF, 0xEE>>
    Virtual.Server.broadcast(server, jpeg)
    
    # Wait for cast to be processed
    Process.sleep(50)
    
    assert Virtual.Server.get_latest_frame(server) == jpeg
  end

  test "Server dispatches to subscribers", %{opts: opts} do
    registry = opts[:registry_name]
    server = opts[:server_name]
    Registry.register(registry, "frames", [])
    
    jpeg = <<0x01, 0x02, 0x03>>
    Virtual.Server.broadcast(server, jpeg)
    
    assert_receive {:frame, ^jpeg}
  end
end

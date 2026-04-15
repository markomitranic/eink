defprotocol EInk.Drawable do
  @moduledoc """
  Protocol for types that can be drawn to an E-Ink display.
  """

  @doc """
  Converts the data into a standardized packed binary matching the display's palette.
  """
  def to_binary(data, display_state, opts \\ [])
end

defimpl EInk.Drawable, for: BitString do
  def to_binary(data, _state, _opts), do: data
end

defimpl EInk.Drawable, for: Dither do
  def to_binary(dither, state, opts) do
    dither
    |> maybe_resize(state.width, state.height)
    |> maybe_dither(state.palette, opts)
    |> Dither.to_raw!()
    |> EInk.Packer.pack(state.palette)
  end

  defp maybe_resize(%Dither{size: {w, h}} = dither, w, h), do: dither
  defp maybe_resize(dither, w, h), do: Dither.resize!(dither, w, h)

  defp maybe_dither(dither, palette, opts) do
    if Keyword.get(opts, :dither, true) do
      bit_depth =
        case palette do
          :bw -> 1
          :grayscale2 -> 2
          _ -> 1
        end

      dither_opts = [bit_depth: bit_depth]
      dither_opts = if alg = opts[:algorithm], do: [{:algorithm, alg} | dither_opts], else: dither_opts

      Dither.dither!(dither, dither_opts)
    else
      Dither.grayscale!(dither)
    end
  end
end

defimpl EInk.Drawable, for: Tuple do
  def to_binary({:file, path}, state, opts) do
    path
    |> Dither.load!()
    |> EInk.Drawable.to_binary(state, opts)
  end

  def to_binary(other, _state, _opts) do
    raise "Unsupported tuple format for EInk.Drawable: #{inspect(other)}"
  end
end

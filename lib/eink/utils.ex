defmodule EInk.Utils do
  @moduledoc """
  Utilities for converting and packing pixel data for EInk displays.
  """

  @doc """
  Dithers and packs a %Dither{} struct into a binary based on the mode.
  - `:full` / `:fast`: Returns a 1-bit packed binary.
  - `:grayscale`: Returns a tuple of two 1-bit planar binaries {ch1, ch2}.
  Can skip dithering if `dither: false` is passed in `opts`.
  """
  def to_packed_binary(%Dither{} = dither, mode, opts \\ []) do
    dither_enabled? = Keyword.get(opts, :dither, true)

    case mode do
      m when m in [:full, :fast] ->
        dither = if dither_enabled?, do: Dither.dither!(dither, bit_depth: 1), else: dither

        dither
        |> Dither.to_raw!()
        |> pack_bw()

      :grayscale ->
        dither = if dither_enabled?, do: Dither.dither!(dither, bit_depth: 3), else: dither

        dither
        |> Dither.to_raw!()
        |> pack_grayscale()
    end
  end

  @doc """
  Packs 8-bit grayscale pixels into a 1-bit binary.
  Assumes pixels >= 128 are white (1), < 128 are black (0).
  """
  def pack_bw(pixels) when is_binary(pixels) do
    for <<pixel::8 <- pixels>>, into: <<>> do
      bit = if pixel >= 128, do: 1, else: 0
      <<bit::1>>
    end
  end

  @doc """
  Packs 8-bit grayscale pixels into two 1-bit planar binaries.
  Maps 4 levels (derived from dithered [0, 85, 170, 255]) to planar bits.

  Mapping (Standard 2-bit chunky -> Planar):
  - White (3): ch1=1, ch2=1
  - Light Gray (2): ch1=0, ch2=1
  - Dark Gray (1): ch1=1, ch2=0
  - Black (0): ch1=0, ch2=0

  Note: This maps chunky LSB to ch1 and MSB to ch2.
  """
  def pack_grayscale(pixels) when is_binary(pixels) do
    # Process in 8-pixel chunks for efficiency
    split_planar(pixels, <<>>, <<>>)
  end

  defp split_planar(<<>>, acc1, acc2), do: {acc1, acc2}

  defp split_planar(<<p1, p2, p3, p4, p5, p6, p7, p8, rest::binary>>, acc1, acc2) do
    {v1_1, v1_2} = pixel_to_planar(p1)
    {v2_1, v2_2} = pixel_to_planar(p2)
    {v3_1, v3_2} = pixel_to_planar(p3)
    {v4_1, v4_2} = pixel_to_planar(p4)
    {v5_1, v5_2} = pixel_to_planar(p5)
    {v6_1, v6_2} = pixel_to_planar(p6)
    {v7_1, v7_2} = pixel_to_planar(p7)
    {v8_1, v8_2} = pixel_to_planar(p8)

    ch1 = <<v1_1::1, v2_1::1, v3_1::1, v4_1::1, v5_1::1, v6_1::1, v7_1::1, v8_1::1>>
    ch2 = <<v1_2::1, v2_2::1, v3_2::1, v4_2::1, v5_2::1, v6_2::1, v7_2::1, v8_2::1>>

    split_planar(rest, <<acc1::binary, ch1::binary>>, <<acc2::binary, ch2::binary>>)
  end

  # Threshold-based mapping from 8-bit grayscale to 2-bit planar
  defp pixel_to_planar(p) do
    cond do
      # White
      p >= 213 -> {0, 0}
      # Light Gray
      p >= 128 -> {1, 0}
      # Dark Gray
      p >= 42 -> {0, 1}
      # Black
      true -> {1, 1}
    end
  end
end

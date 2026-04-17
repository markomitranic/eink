defmodule EInk.Packer do
  @moduledoc """
  Efficiently packs pixel data into various bit-depths.
  """

  @doc """
  Packs pixels into a binary based on the palette.
  Assumes pixels is a binary of 8-bit grayscale values (0-255).
  """
  def pack(pixels, :bw) when is_binary(pixels) do
    # Optimized 1-bit packing from 8-bit grayscale pixels.
    # Extracts the most significant bit (>= 128 is white, < 128 is black).
    for <<bit::1, _rest::7 <- pixels>>, into: <<>> do
      <<bit::1>>
    end
  end

  def pack(pixels, :grayscale2) when is_binary(pixels) do
    # Optimized 2-bit packing from 8-bit grayscale pixels.
    # Maps levels based on thresholds to handle dithered values [0, 85, 170, 255]
    # and general grayscale input correctly.
    # 3 (11): White, 2 (10): Light Gray, 1 (01): Dark Gray, 0 (00): Black
    for <<pixel::8 <- pixels>>, into: <<>> do
      val =
        cond do
          pixel >= 213 -> 3
          pixel >= 128 -> 2
          pixel >= 42 -> 1
          true -> 0
        end

      <<val::2>>
    end
  end

  def pack(_pixels, palette) do
    raise "Unsupported palette for packing: #{inspect(palette)}"
  end
end

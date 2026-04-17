defmodule EInk.Driver.Settings do
  @moduledoc """
  Behaviour for defining chip-specific initialization and LUT sequences.
  Allows multiple panels to share the same chip driver via pattern matching.
  """

  @callback get_init(mode :: atom(), resolution :: {integer(), integer()}) :: [{integer(), binary()}]
  @callback get_lut(mode :: atom(), resolution :: {integer(), integer()}) :: [{integer(), binary()}] | nil
end

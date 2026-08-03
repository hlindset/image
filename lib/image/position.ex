defmodule Image.Position do
  @moduledoc """
  Resolves a placement specification into a pixel offset.

  Placing one rectangle inside another using the offset, the edge of the container
  it is measured from, and the edge of the placed rectangle it is measured to.
  The last two are collapsed: a tag names one side, and relates that side of the
  placed rectangle to the same side of the container. `{:right, 0}` is flush right,
  and `{:right, 10}` leaves 10 pixels between the container's right edge and the
  rectangle's right edge.

  ## Specifications

  * A non-negative integer is an offset from the left or top edge. There is no
    bare negative form, so a tagged offset with a negative value will have to be
    used instead.

  * `:left`/`:right`/`:top`/`:bottom` place the rectangle flush against
    that edge. `:center` centers it horizontally and `:middle` vertically.

  * `{tag, offset}` applies `offset` inward from the named edge. The offset is
    signed: a negative value places the rectangle beyond the edge, which is
    legal wherever the calling operation permits partial overlap.

  ## Bounds

  Resolution is pure: it converts a specification into a position and does not
  decide whether that position is legal. Different operations have different
  positioning rules. E.g. `Image.crop/5` requires the region to be completely
  inside the source, while `Image.embed/4` requires only a single pixel of
  overlap. Each operation's validator applies its own rules to the resolved
  value.

  """

  @x_tags [:left, :center, :right]
  @y_tags [:top, :middle, :bottom]

  @near_tags [:left, :top]
  @far_tags [:right, :bottom]
  @center_tags [:center, :middle]

  @typedoc "Horizontal placement tags."
  @type x_symbol :: :left | :center | :right

  @typedoc "Vertical placement tags."
  @type y_symbol :: :top | :middle | :bottom

  @typedoc "A horizontal placement specification."
  @type x_spec :: non_neg_integer() | x_symbol() | {x_symbol(), integer()}

  @typedoc "A vertical placement specification."
  @type y_spec :: non_neg_integer() | y_symbol() | {y_symbol(), integer()}

  @typedoc "The axis a specification applies to."
  @type axis :: :x | :y

  @doc """
  Resolves a placement specification into an offset.

  ### Arguments

  * `axis` is `:x` or `:y` and selects the accepted tags.

  * `spec` is an `t:x_spec/0` or `t:y_spec/0`.

  * `placed` is the extent of the rectangle being positioned, along `axis`.

  * `container` is the extent it is being positioned within, along `axis`.

  ### Returns

  * `{:ok, offset}`, the left or top coordinate, possibly negative or beyond
    `container`, or

  * `{:error, %Image.Error{}}` if the specification is not valid for `axis`.

  ### Examples

      iex> Image.Position.resolve(:x, :right, 200, 300)
      {:ok, 100}

      iex> Image.Position.resolve(:x, {:right, 10}, 200, 300)
      {:ok, 90}

      iex> Image.Position.resolve(:y, {:bottom, -10}, 200, 300)
      {:ok, 110}

      iex> Image.Position.resolve(:x, :center, 200, 300)
      {:ok, 50}

      iex> {:error, error} = Image.Position.resolve(:y, :left, 200, 300)
      iex> {error.reason, error.value}
      {:invalid_option, {:y, :left}}

  """
  @spec resolve(axis(), x_spec() | y_spec(), non_neg_integer(), non_neg_integer()) ::
          {:ok, integer()} | {:error, Image.Error.t()}

  def resolve(axis, spec, placed, container)
      when axis in [:x, :y] and is_integer(placed) and is_integer(container) do
    do_resolve(axis, spec, placed, container)
  end

  defp do_resolve(_axis, offset, _placed, _container) when is_integer(offset) and offset >= 0 do
    {:ok, offset}
  end

  defp do_resolve(:x, tag, placed, container) when tag in @x_tags do
    do_resolve(:x, {tag, 0}, placed, container)
  end

  defp do_resolve(:y, tag, placed, container) when tag in @y_tags do
    do_resolve(:y, {tag, 0}, placed, container)
  end

  defp do_resolve(:x, {tag, offset}, placed, container)
       when tag in @x_tags and is_integer(offset) do
    {:ok, from_edge(tag, offset, placed, container)}
  end

  defp do_resolve(:y, {tag, offset}, placed, container)
       when tag in @y_tags and is_integer(offset) do
    {:ok, from_edge(tag, offset, placed, container)}
  end

  defp do_resolve(axis, spec, _placed, _container) do
    {:error, invalid(axis, spec)}
  end

  defp from_edge(tag, offset, _placed, _container) when tag in @near_tags do
    offset
  end

  defp from_edge(tag, offset, placed, container) when tag in @far_tags do
    container - placed - offset
  end

  defp from_edge(tag, offset, placed, container) when tag in @center_tags do
    round((container - placed) / 2) + offset
  end

  defp invalid(axis, spec) do
    %Image.Error{
      reason: :invalid_option,
      value: {axis, spec},
      message:
        "Invalid #{axis} position: #{inspect(spec)}. Valid values are an integer, " <>
          "#{Enum.map_join(tags(axis), ", ", &inspect/1)}, or a {tag, offset} tuple"
    }
  end

  defp tags(:x), do: @x_tags
  defp tags(:y), do: @y_tags
end

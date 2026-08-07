defmodule Image.Options.New do
  @moduledoc """
  Options for new images.

  """
  alias Image.{Pixel, BandFormat, Interpretation}

  @type t :: [
          {:bands, pos_integer()}
          | {:format, Image.BandFormat.t()}
          | {:interpretation, Image.Interpretation.t()}
          | {:color, Image.Pixel.t()}
          | {:x_res, number()}
          | {:y_res, number()}
          | {:x_offset, number()}
          | {:y_offset, number()}
        ]

  # :format and :bands are deliberately absent. Both are derived from
  # :interpretation when the caller does not set them, and the derivation
  # cannot tell a default apart from an explicit value.
  def default_options do
    [
      interpretation: :srgb,
      color: 0,
      x_res: 0,
      y_res: 0,
      x_offset: 0,
      y_offset: 0
    ]
  end

  @doc """
  Validate the options for `Image.new/2`.

  """
  def validate_options(options) do
    options = Keyword.merge(default_options(), options)

    options =
      case Enum.reduce_while(options, options, &validate_option(&1, &2)) do
        {:error, value} ->
          {:error, value}

        options ->
          {:ok, options}
      end

    with {:ok, options} <- options,
         options = Map.new(options),
         {:ok, shape} <- interpretation_shape(options.interpretation),
         {:ok, options} <- set_bands(options, shape),
         {:ok, options} <- validate_color_bands(options) do
      set_format(options, shape)
    end
  end

  # The natural band count and band format of an interpretation, owned by
  # Image.Pixel because it is the same table that drives color conversion.
  # An interpretation with no entry there has no shape to build an image
  # from, whether because it is not a color space at all (:matrix,
  # :histogram, :fourier) or because it is one Image.Pixel cannot resolve
  # colors for (:cmc, :labq). Image.Pixel's message says which, so it is
  # carried through rather than restated here.
  defp interpretation_shape(vips_interpretation) do
    interpretation = Interpretation.decode_interpretation(vips_interpretation)

    case Pixel.shape(interpretation) do
      {:ok, shape} ->
        {:ok, shape}

      {:error, reason} ->
        {:error,
         %Image.Error{
           reason: :invalid_option,
           value: interpretation,
           message:
             "Invalid option or option value: interpretation: " <>
               "#{inspect(interpretation)}. #{reason}"
         }}
    end
  end

  defp validate_option({:format, format}, options) when is_tuple(format) do
    case BandFormat.image_format_from_nx(format) do
      {:ok, format} ->
        {:cont, Keyword.put(options, :format, format)}

      {:error, reason} ->
        {:halt, {:error, reason}}
    end
  end

  defp validate_option({:format, format}, options) when is_atom(format) do
    case BandFormat.nx_format(format) do
      {:ok, _nx_type} ->
        {:cont, options}

      {:error, reason} ->
        {:halt, {:error, reason}}
    end
  end

  defp validate_option({:interpretation, interpretation}, options) do
    case Interpretation.validate_interpretation(interpretation) do
      {:ok, interpretation} ->
        {:cont, Keyword.put(options, :interpretation, interpretation)}

      {:error, reason} ->
        {:halt, {:error, reason}}
    end
  end

  @numeric_options [:x_res, :y_res, :x_offset, :y_offset, :bands]
  defp validate_option({option, value}, options)
       when option in @numeric_options and is_number(value) and value >= 0 do
    {:cont, options}
  end

  defp validate_option({:color, color}, options) when is_integer(color) do
    {:cont, Keyword.put(options, :color, color)}
  end

  # A pre-encoded numeric list (any length 1..5) is passed through
  # untouched. This is the path used internally by callers that
  # already produced a pixel for a particular interpretation
  # (Image.if_then_else, Image.replace_color, k-means, etc).
  defp validate_option({:color, color}, options)
       when is_list(color) and color != [] and length(color) <= 5 do
    if Enum.all?(color, &is_number/1) do
      {:cont, Keyword.put(options, :color, color)}
    else
      case Pixel.to_srgb(color) do
        {:ok, pixel} -> {:cont, Keyword.put(options, :color, pixel)}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end
  end

  # Validated but deliberately not converted. Resolving to sRGB here would
  # discard the target interpretation, which is the whole point: Image.new/3
  # resolves the color against the image it is about to build, so a named
  # color lands in :cmyk or :lab rather than as sRGB values wearing that tag.
  defp validate_option({:color, color}, options) do
    case Pixel.to_srgb(color) do
      {:ok, _srgb} ->
        {:cont, Keyword.put(options, :color, color)}

      {:error, reason} ->
        {:halt, {:error, reason}}
    end
  end

  defp validate_option({option, value}, _options) do
    {:halt, {:error, invalid_option(option, value)}}
  end

  # An explicit :bands wins. A list color sizes the image by its own length,
  # which is how a caller asks for an alpha band. Everything else takes the
  # interpretation's natural band count, so :cmyk gets 4 and :bw gets 1
  # rather than the 3 that a default color used to imply.
  defp set_bands(%{bands: _bands} = options, _shape), do: {:ok, options}

  defp set_bands(%{color: color} = options, _shape) when is_list(color) do
    {:ok, Map.put(options, :bands, length(color))}
  end

  defp set_bands(options, {bands, _format}) do
    {:ok, Map.put(options, :bands, bands + alpha_bands(options.color))}
  end

  # A color that carries its own alpha (`:transparent`, `"#ff000080"`, a
  # Color struct with an alpha component) asks for an alpha band, whatever
  # the interpretation's own band count is.
  defp alpha_bands(color) when is_number(color), do: 0

  defp alpha_bands(color) do
    case Pixel.to_srgb(color) do
      {:ok, srgb} when length(srgb) == 4 -> 1
      _other -> 0
    end
  end

  # An explicit :format wins. Otherwise the interpretation decides, so a
  # color destined for :lab or :rgb16 is not silently clipped into {:u, 8}.
  # Pixel.shape/1 speaks the Nx form that Image.band_format/1 returns, and
  # validate_option/2 has already put explicit formats into the vips form.
  defp set_format(%{format: _format} = options, _shape), do: {:ok, options}

  defp set_format(options, {_bands, format}) do
    case BandFormat.image_format_from_nx(format) do
      {:ok, vips_format} -> {:ok, Map.put(options, :format, vips_format)}
      {:error, reason} -> {:error, reason}
    end
  end

  # A list color sizes the image by its own length, so it can only disagree
  # with :bands when the caller set both. libvips would otherwise silently
  # widen the canvas to the vector's length, ignoring :bands, or raise from
  # inside Image.Math.add/2. A single value is the uniform-across-all-bands
  # form and always fits.
  #
  # The interpretation's own band count is deliberately not enforced here.
  # An sRGB tag covers 1 to 5 band images in practice, and Image.Complex
  # builds 2-band images this way for real/imaginary pairs.
  defp validate_color_bands(%{color: color, bands: bands} = options)
       when is_list(color) do
    if length(color) in [1, bands] do
      {:ok, options}
    else
      {:error, color_bands_error(color, bands)}
    end
  end

  defp validate_color_bands(options), do: {:ok, options}

  defp color_bands_error(color, bands) do
    %Image.Error{
      reason: :invalid_option,
      value: color,
      message:
        "Invalid option or option value: color: #{inspect(color)} has #{length(color)} " <>
          "values but :bands is #{bands}. Expected #{bands} values, or 1 to apply the " <>
          "same value to every band."
    }
  end

  @doc false
  def invalid_option(option) do
    message = "Invalid option or option value: #{inspect(option)}"
    %Image.Error{reason: :invalid_option, value: option, message: message}
  end

  @doc false
  def invalid_option(option, value) do
    message = "Invalid option or option value: #{option}: #{inspect(value)}"
    %Image.Error{reason: :invalid_option, value: value, message: message}
  end
end

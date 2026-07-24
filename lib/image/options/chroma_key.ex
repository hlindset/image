defmodule Image.Options.ChromaKey do
  @moduledoc """
  Options and option validation for `Image.chroma_key/2`.

  """
  alias Image.Pixel

  @typedoc """
  Options applicable to Image.chroma_key/2

  """
  @type chroma_key_options ::
          [
            {:color, Pixel.t() | :auto}
            | {:threshold, non_neg_integer()}
            | {:greater_than, Pixel.t()}
            | {:less_than, Pixel.t()}
            | {:sigma, float()}
            | {:min_amplitude, float()}
          ]
          | map()

  @doc """
  Validate the options for `Image.chroma_key/2`.

  """
  def validate_options(image, options) when is_list(options) do
    options = Keyword.merge(default_options(), options)

    case Enum.reduce_while(options, options, &validate_option(&1, image, &2)) do
      {:error, value} ->
        {:error, value}

      options ->
        select_strategy(Map.new(options))
    end
  end

  # `Image.chroma_key/2` and `Image.chroma_mask/2` both document a map as
  # an acceptable option form, so it is validated the same way a keyword
  # list is rather than being returned untouched.
  def validate_options(image, %{} = options) do
    validate_options(image, Map.to_list(options))
  end

  defp validate_option({:color, :auto}, _image, options) do
    {:cont, options}
  end

  defp validate_option({key, color} = option, image, options)
       when key in [:greater_than, :less_than, :color] do
    case Pixel.to_pixel(image, color) do
      {:ok, pixel} -> {:cont, Keyword.put(options, key, pixel)}
      _other -> {:halt, {:error, invalid_option(option)}}
    end
  end

  defp validate_option({:threshold, threshold}, _image, options)
       when is_integer(threshold) and threshold >= 0 do
    {:cont, options}
  end

  defp validate_option({:sigma, sigma}, _image, options) when is_number(sigma) and sigma > 0 do
    {:cont, options}
  end

  defp validate_option({:min_amplitude, min_amplitude}, _image, options)
       when is_float(min_amplitude) do
    {:cont, Keyword.put(options, :min_amplitude, min_amplitude)}
  end

  defp validate_option(option, _image, _options) do
    {:halt, {:error, invalid_option(option)}}
  end

  defp invalid_option(option) do
    %Image.Error{
      reason: :invalid_option,
      value: option,
      message: "Invalid option or option value: #{inspect(option)}"
    }
  end

  defp select_strategy(%{greater_than: _, less_than: _} = options) do
    options =
      options
      |> Map.delete(:color)
      |> Map.delete(:threshold)

    {:ok, options}
  end

  defp select_strategy(%{color: _, threshold: _} = options) do
    options =
      options
      |> Map.delete(:greater_than)
      |> Map.delete(:less_than)

    {:ok, options}
  end

  # Unreachable while the defaults inject both :color and :threshold, so
  # the clause above always matches. Kept as a guard against a change to
  # `default_options/0`, and returning the same struct the other error
  # paths in this module return rather than a bare string.
  defp select_strategy(options) do
    {:error,
     %Image.Error{
       reason: :invalid_option,
       value: options,
       message:
         "Invalid options #{inspect(options)}. Options need to have either :greater_than " <>
           "and :less_than or :color and :threshold."
     }}
  end

  defp default_options do
    [
      color: :auto,
      threshold: 20
    ]
  end
end

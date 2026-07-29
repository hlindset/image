defmodule Image.Options.ChromaKey do
  @moduledoc """
  Options and option validation for `Image.chroma_key/2`.

  """
  alias Image.Pixel

  # The two masking strategies are mutually exclusive. Which one applies is
  # decided from the keys the caller supplied, not from the merged options,
  # since the defaults always materialise the threshold keys.
  @threshold_keys [:color, :threshold]
  @range_keys [:greater_than, :less_than]
  @strategy_keys @threshold_keys ++ @range_keys

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

  @doc """
  Validate the options for `Image.chroma_key/2`.

  """
  def validate_options(image, options) when is_list(options) do
    # A nil strategy option means "unset". It falls back to the default and does
    # not count as explicitly supplied, so it does not conflict with the other
    # strategy. Options with no default, like `:sigma`, keep rejecting nil.
    options = Enum.reject(options, &match?({key, nil} when key in @strategy_keys, &1))
    user_supplied_keys = Keyword.keys(options)
    options = Keyword.merge(default_options(), options)

    case Enum.reduce_while(options, options, &validate_option(&1, image, &2)) do
      {:error, value} ->
        {:error, value}

      options ->
        options
        |> Map.new()
        |> select_strategy(user_supplied_keys)
    end
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

  # Resolves which masking strategy the caller asked for and records it under
  # `:strategy` so the mask calculation dispatches on an explicit discriminator
  # rather than on which keys happen to be present.
  defp select_strategy(options, user_supplied_keys) do
    threshold = Enum.filter(@threshold_keys, &(&1 in user_supplied_keys))
    range = Enum.filter(@range_keys, &(&1 in user_supplied_keys))

    case {threshold, range} do
      {[_ | _], [_ | _]} ->
        {:error, conflicting_strategies_error(threshold, range)}

      {_, [single]} ->
        {:error, incomplete_range_error(single)}

      {[], @range_keys} ->
        options =
          options
          |> Map.drop(@threshold_keys)
          |> Map.put(:strategy, :range)

        {:ok, options}

      {_, []} ->
        {:ok, Map.put(options, :strategy, :threshold)}
    end
  end

  defp conflicting_strategies_error(threshold, range) do
    %Image.Error{
      reason: :invalid_option,
      value: threshold ++ range,
      message:
        "The threshold strategy options #{inspect(threshold)} cannot be combined with " <>
          "the color range options #{inspect(range)}. The two masking strategies are " <>
          "mutually exclusive, pass the options for one or the other."
    }
  end

  defp incomplete_range_error(key) do
    %Image.Error{
      reason: :invalid_option,
      value: [key],
      message:
        "The color range strategy requires both :greater_than and :less_than. " <>
          "Only #{inspect(key)} was supplied."
    }
  end

  defp default_options do
    [color: :auto, threshold: 20]
  end
end

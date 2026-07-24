defmodule Image.DominantColorTest do
  use ExUnit.Case, async: true

  describe "dominant_color/2 with the histogram method" do
    test "reports black for an opaque black image with an alpha band" do
      # Regression: the black-bin correction subtracted the transparent-pixel
      # count with min/2 instead of max/2, so a genuinely black RGBA image
      # could never report black as its dominant color.
      image = Image.new!(10, 10, color: [0, 0, 0, 255])

      assert {:ok, [r, g, b]} = Image.dominant_color(image)
      assert r < 16 and g < 16 and b < 16
    end

    test "matches the non-alpha result for the same black image" do
      with_alpha = Image.new!(10, 10, color: [0, 0, 0, 255])
      without_alpha = Image.new!(10, 10, color: [0, 0, 0])

      assert Image.dominant_color(with_alpha) == Image.dominant_color(without_alpha)
    end

    test "excludes fully transparent pixels from the dominant color" do
      transparent = Image.new!(20, 20, color: [0, 0, 0, 0])
      red = Image.new!(10, 10, color: [255, 0, 0, 255])
      {:ok, composed} = Image.compose(transparent, red, x: 0, y: 0)

      assert {:ok, [r, g, b]} = Image.dominant_color(composed)
      assert r > 200 and g < 16 and b < 16
    end
  end

  describe "parse_gif_global_color_table/1" do
    # gct_flag set, size code 1, so the header declares 4 entries of 3 bytes each
    @header <<"GIF89a", 4::16-little, 4::16-little, 0x81, 0, 0>>

    test "returns the palette when the table is complete" do
      buffer = @header <> :binary.copy(<<1, 2, 3>>, 4)

      assert {:ok, [{1, 2, 3}, {1, 2, 3}, {1, 2, 3}, {1, 2, 3}]} =
               Image.parse_gif_global_color_table(buffer)
    end

    test "returns an error when the table is truncated" do
      buffer = @header <> <<1, 2, 3>>

      assert {:error, %Image.Error{} = error} = Image.parse_gif_global_color_table(buffer)
      assert error.message =~ "ends before its Global Color Table is complete"
    end

    test "returns an error when no Global Color Table is present" do
      buffer = <<"GIF89a", 4::16-little, 4::16-little, 0x01, 0, 0>>

      assert {:error, %Image.Error{} = error} = Image.parse_gif_global_color_table(buffer)
      assert error.message =~ "does not contain a Global Color Table"
    end

    test "returns an error for a buffer that is not a GIF" do
      assert {:error, %Image.Error{} = error} = Image.parse_gif_global_color_table(<<"NOTAGIF">>)
      assert error.message =~ "Could not parse GIF buffer"
    end
  end
end

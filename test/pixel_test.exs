defmodule Image.PixelTest do
  use ExUnit.Case, async: true

  doctest Image.Pixel

  alias Image.Pixel

  describe "to_pixel/3 against an sRGB image" do
    setup do
      {:ok, image} = Image.new(2, 2, color: :black)
      {:ok, image: image}
    end

    test "atom name", %{image: image} do
      assert {:ok, [255, 0, 0]} = Pixel.to_pixel(image, :red)
    end

    test "string name", %{image: image} do
      assert {:ok, [255, 0, 0]} = Pixel.to_pixel(image, "red")
    end

    test "hex string", %{image: image} do
      assert {:ok, [255, 0, 0]} = Pixel.to_pixel(image, "#ff0000")
    end

    test "short hex", %{image: image} do
      assert {:ok, [255, 0, 0]} = Pixel.to_pixel(image, "#f00")
    end

    test "integer list", %{image: image} do
      assert {:ok, [10, 20, 30]} = Pixel.to_pixel(image, [10, 20, 30])
    end

    test "float list", %{image: image} do
      assert {:ok, [255, 0, 0]} = Pixel.to_pixel(image, [1.0, 0.0, 0.0])
    end

    test "Color.SRGB struct", %{image: image} do
      assert {:ok, [255, 0, 0]} =
               Pixel.to_pixel(image, %Color.SRGB{r: 1.0, g: 0.0, b: 0.0})
    end

    test "color from another space is converted to sRGB", %{image: image} do
      lab_red = %Color.Lab{l: 53.24, a: 80.09, b: 67.20}
      assert {:ok, [r, g, b]} = Pixel.to_pixel(image, lab_red)
      assert_in_delta r, 255, 1
      assert_in_delta g, 0, 1
      assert_in_delta b, 0, 1
    end

    test "hex with alpha is dropped on a 3-band image", %{image: image} do
      assert {:ok, [255, 0, 0]} = Pixel.to_pixel(image, "#ff000080")
    end

    test "transparency aliases collapse to black", %{image: image} do
      assert {:ok, [0, 0, 0]} = Pixel.to_pixel(image, :transparent)
      assert {:ok, [0, 0, 0]} = Pixel.to_pixel(image, :none)
      assert {:ok, [0, 0, 0]} = Pixel.to_pixel(image, :opaque)
    end
  end

  describe "to_pixel/3 against an sRGB image with alpha" do
    setup do
      {:ok, image} = Image.new(2, 2, color: [0, 0, 0, 255])
      {:ok, image: image}
    end

    test "named color gets full opacity", %{image: image} do
      assert {:ok, [255, 0, 0, 255]} = Pixel.to_pixel(image, :red)
    end

    test "explicit :alpha option overrides", %{image: image} do
      assert {:ok, [255, 0, 0, 128]} = Pixel.to_pixel(image, :red, alpha: 0.5)
      assert {:ok, [255, 0, 0, 0]} = Pixel.to_pixel(image, :red, alpha: :transparent)
      assert {:ok, [255, 0, 0, 255]} = Pixel.to_pixel(image, :red, alpha: :opaque)
      assert {:ok, [255, 0, 0, 100]} = Pixel.to_pixel(image, :red, alpha: 100)
    end

    test "hex with alpha is preserved", %{image: image} do
      assert {:ok, [255, 0, 0, 128]} = Pixel.to_pixel(image, "#ff000080")
    end

    test "transparent / none yield zero alpha", %{image: image} do
      assert {:ok, [0, 0, 0, 0]} = Pixel.to_pixel(image, :transparent)
      assert {:ok, [0, 0, 0, 0]} = Pixel.to_pixel(image, :none)
    end

    test "opaque yields full alpha", %{image: image} do
      assert {:ok, [0, 0, 0, 255]} = Pixel.to_pixel(image, :opaque)
    end

    test "a list one band short gains the missing alpha", %{image: image} do
      assert {:ok, [255, 0, 0, 255]} = Pixel.to_pixel(image, [255, 0, 0])
    end
  end

  describe "to_pixel/3 fits a list color to the image band count" do
    test "a list one band over a non-alpha image loses the extra value" do
      {:ok, image} = Image.new(2, 2, color: [0, 0, 0])

      assert {:ok, [255, 0, 0]} = Pixel.to_pixel(image, [255, 0, 0, 255])
    end
  end

  describe "to_pixel/3 against a Lab image" do
    setup do
      {:ok, image} = Image.new(2, 2, color: :black)
      {:ok, image} = Image.to_colorspace(image, :lab)
      {:ok, image: image}
    end

    test "named red is converted to Lab red, not [255, 0, 0]", %{image: image} do
      assert {:ok, [l, a, b]} = Pixel.to_pixel(image, :red)
      assert_in_delta l, 53.24, 0.1
      assert_in_delta a, 80.09, 0.1
      assert_in_delta b, 67.20, 0.1
    end

    test "Color.Lab struct passes through", %{image: image} do
      lab_blue = %Color.Lab{l: 32.30, a: 79.20, b: -107.86}
      assert {:ok, [l, a, b]} = Pixel.to_pixel(image, lab_blue)
      assert_in_delta l, 32.30, 0.001
      assert_in_delta a, 79.20, 0.001
      assert_in_delta b, -107.86, 0.001
    end

    test "white is L≈100, a≈0, b≈0", %{image: image} do
      assert {:ok, [l, a, b]} = Pixel.to_pixel(image, :white)
      assert_in_delta l, 100.0, 0.5
      assert_in_delta a, 0.0, 0.5
      assert_in_delta b, 0.0, 0.5
    end
  end

  describe "to_pixel/3 alpha scale matches the interpretation's max alpha" do
    defp with_alpha(colorspace) do
      {:ok, srgba} = Image.new(2, 2, color: [10, 20, 30, 255])
      {:ok, image} = Image.to_colorspace(srgba, colorspace)
      image
    end

    test "opaque alpha resolves to 255 for every 0..255-scale interpretation" do
      for colorspace <- [:srgb, :cmyk, :hsv, :bw, :lab, :lch, :labs] do
        image = with_alpha(colorspace)
        {:ok, pixel} = Pixel.to_pixel(image, :red, alpha: :opaque)
        assert List.last(pixel) == 255, "#{colorspace} opaque alpha was #{List.last(pixel)}"
      end
    end

    test "scRGB opaque alpha stays 1.0" do
      image = with_alpha(:scrgb)
      assert {:ok, [_r, _g, _b, alpha]} = Pixel.to_pixel(image, :red, alpha: :opaque)
      assert alpha == 1.0
    end

    test "a plain color (no explicit :alpha) also synthesizes opaque 255 on Lab" do
      image = with_alpha(:lab)
      assert {:ok, [_l, _a, _b, 255]} = Pixel.to_pixel(image, :red)
    end

    test "alpha 0.5 resolves to 128 on Lab" do
      image = with_alpha(:lab)
      assert {:ok, [_l, _a, _b, alpha]} = Pixel.to_pixel(image, :red, alpha: 0.5)
      assert alpha == 128
    end
  end

  describe "to_pixel/3 against a CMYK image" do
    setup do
      {:ok, image} = Image.new(2, 2, color: :black)
      {:ok, image} = Image.to_colorspace(image, :cmyk)
      {:ok, image: image}
    end

    test "named red is converted to CMYK with 4 channels", %{image: image} do
      assert {:ok, [c, m, y, k]} = Pixel.to_pixel(image, :red)
      # Red in CMYK is roughly (0, 255, 255, 0)
      assert c == 0
      assert m == 255
      assert y == 255
      assert k == 0
    end

    test "white is (0, 0, 0, 0)", %{image: image} do
      assert {:ok, [0, 0, 0, 0]} = Pixel.to_pixel(image, :white)
    end
  end

  describe "to_pixel/3 against a B/W image" do
    setup do
      {:ok, image} = Image.new(2, 2, color: 0, bands: 1)
      {:ok, image: image}
    end

    test "named red collapses to a single luma channel", %{image: image} do
      assert {:ok, [gray]} = Pixel.to_pixel(image, :red)
      # Red has a Lab L* around 53, so the gray should be near 53/100 * 255 ≈ 135
      assert_in_delta gray, 135, 5
    end

    test "white is 255, black is 0", %{image: image} do
      assert {:ok, [white]} = Pixel.to_pixel(image, :white)
      assert white == 255
      assert {:ok, [0]} = Pixel.to_pixel(image, :black)
    end
  end

  describe "strip_alpha/2" do
    test "drops the last band of a full pixel on an alpha image" do
      {:ok, image} = Image.new(2, 2, color: [0, 0, 0, 255])

      assert [255, 0, 0] == Pixel.strip_alpha([255, 0, 0, 128], image)
    end

    test "returns the pixel unchanged on an image without alpha" do
      {:ok, image} = Image.new(2, 2, color: [0, 0, 0])

      assert [255, 0, 0] == Pixel.strip_alpha([255, 0, 0], image)
    end

    test "returns a pixel shorter than the image's bands unchanged" do
      {:ok, image} = Image.new(2, 2, color: [0, 0, 0, 255])

      assert [255, 0, 0] == Pixel.strip_alpha([255, 0, 0], image)
    end
  end

  describe "transparency/1" do
    test "atoms" do
      assert {:ok, 0} = Pixel.transparency(:none)
      assert {:ok, 0} = Pixel.transparency(:transparent)
      assert {:ok, 255} = Pixel.transparency(:opaque)
    end

    test "integers" do
      assert {:ok, 0} = Pixel.transparency(0)
      assert {:ok, 128} = Pixel.transparency(128)
      assert {:ok, 255} = Pixel.transparency(255)
    end

    test "floats" do
      assert {:ok, 0} = Pixel.transparency(0.0)
      assert {:ok, 128} = Pixel.transparency(0.5)
      assert {:ok, 255} = Pixel.transparency(1.0)
    end

    test "out of range" do
      assert {:error, %Image.Error{reason: :invalid_transparency, value: -1}} =
               Pixel.transparency(-1)

      assert {:error, %Image.Error{reason: :invalid_transparency}} = Pixel.transparency(256)
      assert {:error, %Image.Error{reason: :invalid_transparency}} = Pixel.transparency(2.0)
      assert {:error, %Image.Error{reason: :invalid_transparency}} = Pixel.transparency(:blue)
    end
  end

  describe "error contract" do
    setup do
      {:ok, image} = Image.new(2, 2, color: :black)
      {:ok, image: image}
    end

    test "an unknown color name", %{image: image} do
      assert {:error, %Image.Error{} = error} = Pixel.to_pixel(image, "no-such-color")
      assert error.reason == :invalid_color
      assert error.value == "no-such-color"
      assert error.message =~ "no-such-color"
    end

    test "a list that is neither pre-encoded nor a valid color", %{image: image} do
      assert {:error, %Image.Error{reason: :invalid_color, value: [1.0, 0, 0]}} =
               Pixel.to_pixel(image, [1.0, 0, 0])
    end

    test "an unsupported interpretation", %{image: image} do
      {:ok, yxy} = Vix.Vips.Operation.copy(image, interpretation: :VIPS_INTERPRETATION_YXY)

      assert {:error, %Image.Error{} = error} = Pixel.to_pixel(yxy, :red)
      assert error.reason == :unsupported_interpretation
      assert error.value == :yxy
      assert error.message =~ ":yxy interpretation"
    end

    test "an invalid :alpha option" do
      {:ok, image} = Image.new(2, 2, color: [0, 0, 0, 255])

      assert {:error, %Image.Error{reason: :invalid_transparency, value: :bogus}} =
               Pixel.to_pixel(image, :red, alpha: :bogus)
    end

    test "an unknown color name on a mutable image", %{image: image} do
      {:ok, _image} =
        Image.mutate(image, fn mutable ->
          send(self(), {:pixel, Pixel.to_pixel(mutable, "no-such-color")})
          :ok
        end)

      assert_received {:pixel, {:error, %Image.Error{reason: :invalid_color}}}
    end

    test "to_srgb/1" do
      assert {:error, %Image.Error{} = error} = Pixel.to_srgb("no-such-color")
      assert error.reason == :invalid_color
      assert error.value == "no-such-color"
      assert error.message =~ "no-such-color"
    end

    test "the bang variants raise with the error's message", %{image: image} do
      assert_raise Image.Error, ~r/no-such-color/, fn ->
        Pixel.to_pixel!(image, "no-such-color")
      end

      assert_raise Image.Error, ~r/no-such-color/, fn ->
        Pixel.to_srgb!("no-such-color")
      end
    end
  end
end

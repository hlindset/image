defmodule Image.PixelColorspaceFidelityTest do
  use ExUnit.Case, async: true

  alias Image.Pixel
  alias Vix.Vips.Image, as: Vimage
  alias Vix.Vips.Operation

  # Colors spanning primaries, secondaries, neutrals and desaturated
  # midtones. Primaries alone hide transfer-function errors, because a
  # gamma curve is the identity at 0.0 and 1.0.
  @colors [:dark_slate_blue, :orange, :teal, :crimson, :olive_drab, :white, :black, :gray]

  # Resolve a color for `interpretation`, write those values into an image
  # tagged that way, and let libvips read it back as sRGB. The arbiter is
  # what the pixel means once it is in an image, which is the only thing
  # downstream cares about. Comparing two in-repo conversions to each other
  # says nothing about which is right.
  defp round_trip_error(color, interpretation) do
    source = Image.new!(1, 1, color: color)
    {:ok, target} = Image.to_colorspace(source, interpretation)
    {:ok, vips_interpretation} = Vimage.header_value(target, "interpretation")

    pixel = Pixel.to_pixel!(target, color)

    restored =
      Operation.black!(1, 1, bands: length(pixel))
      |> Image.Math.add!(pixel)
      |> Operation.cast!(Vimage.format(target))
      |> Operation.copy!(interpretation: vips_interpretation)
      |> Image.to_colorspace!(:srgb)

    Operation.avg!(Operation.de00!(source, restored))
  end

  describe "Image.Pixel.to_pixel/3 colorspace fidelity" do
    # Exactly zero rather than a tolerance: Color and libvips share the
    # primaries, the D65 white point and the sRGB transfer function
    # (Lindbloom.srgb_inverse_compand/1 against the v2Y tables built in
    # libvips' LabQ2sRGB.c), so these are the same equations on both
    # sides rather than two implementations agreeing closely.
    for interpretation <- [:srgb, :rgb16, :scrgb, :lab, :labs, :lch, :xyz, :yxy] do
      test "a color resolved for #{interpretation} round trips through libvips unchanged" do
        for color <- @colors do
          assert round_trip_error(color, unquote(interpretation)) == 0.0
        end
      end
    end

    # HSV cannot reach zero. libvips stores it as three uchar bands, so hue
    # gets 256 steps over 360 degrees and the container itself costs up to
    # about 1.1 dE00 on these colors, whichever route produces the values.
    # The bound only has to separate that quantization from a mapping
    # error, which is what this file exists to catch: pointing a row at the
    # wrong Color module costs tens of dE00, not fractions.
    test "hsv stays within its quantization cost" do
      for color <- @colors do
        assert round_trip_error(color, :hsv) < 2.0
      end
    end
  end

  describe "Image.Pixel.shape/1" do
    test "returns the band count and format libvips gives that interpretation" do
      for interpretation <- [:srgb, :rgb16, :scrgb, :lab, :labs, :lch, :xyz, :yxy, :cmyk, :hsv] do
        {:ok, image} = Image.to_colorspace(Image.new!(1, 1, color: :white), interpretation)

        assert Pixel.shape(interpretation) ==
                 {:ok, {Image.bands(image), Image.band_format(image)}}
      end
    end

    test "reports interpretations that carry no color meaning" do
      assert {:error, message} = Pixel.shape(:matrix)
      assert message =~ ":matrix interpretation"
    end
  end

  describe "Image.Pixel.to_pixel/3 uniform grey" do
    test "a one-element list resolves like the equivalent scalar" do
      for interpretation <- [:srgb, :cmyk, :rgb16, :lab] do
        {:ok, image} = Image.to_colorspace(Image.new!(1, 1, color: :white), interpretation)

        assert Pixel.to_pixel(image, [128]) == Pixel.to_pixel(image, 128)
      end
    end
  end
end

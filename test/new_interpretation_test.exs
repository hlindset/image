defmodule Image.NewInterpretationTest do
  use ExUnit.Case, async: true

  describe "Image.new/3 sizes an image from its :interpretation" do
    test "band count comes from the interpretation, not from the default color" do
      for {interpretation, bands} <- [srgb: 3, cmyk: 4, bw: 1, grey16: 1, lab: 3] do
        image = Image.new!(2, 2, interpretation: interpretation)

        assert Image.bands(image) == bands
        assert Image.colorspace(image) == interpretation
      end
    end

    test "band format comes from the interpretation" do
      for {interpretation, format} <- [
            srgb: {:u, 8},
            rgb16: {:u, 16},
            grey16: {:u, 16},
            lab: {:f, 32},
            labs: {:s, 16},
            scrgb: {:f, 32}
          ] do
        assert Image.band_format(Image.new!(2, 2, interpretation: interpretation)) == format
      end
    end

    test "an explicit :bands or :format wins over the interpretation" do
      image = Image.new!(2, 2, interpretation: :cmyk, bands: 2, format: {:u, 16})

      assert Image.bands(image) == 2
      assert Image.band_format(image) == {:u, 16}
    end

    test "a color carrying alpha adds a band" do
      assert Image.bands(Image.new!(2, 2, color: :transparent)) == 4
      assert Image.bands(Image.new!(2, 2, color: "#ff000080")) == 4
      assert Image.bands(Image.new!(2, 2, color: :red)) == 3
    end

    test "an interpretation with no color meaning is rejected" do
      for interpretation <- [:matrix, :histogram, :fourier] do
        assert {:error, %Image.Error{reason: :invalid_option}} =
                 Image.new(2, 2, interpretation: interpretation)
      end
    end
  end

  describe "Image.new/3 resolves :color into the interpretation" do
    # Within f32 precision rather than exactly: the float interpretations
    # store {:f, 32} while to_pixel/3 returns double-precision floats, so the
    # image itself is the lossy step, not the color resolution.
    test "a named color means the same thing as drawing it on such an image" do
      for interpretation <- [:cmyk, :lab, :rgb16, :bw, :scrgb] do
        created = Image.new!(2, 2, color: :red, interpretation: interpretation)
        target = Image.to_colorspace!(Image.new!(2, 2, color: :white), interpretation)

        drawn = Image.Pixel.to_pixel!(target, :red)
        assert length(Image.get_pixel!(created, 0, 0)) == length(drawn)

        for {got, want} <- Enum.zip(Image.get_pixel!(created, 0, 0), drawn) do
          assert_in_delta got, want, 0.0001
        end
      end
    end

    test "a numeric list is used as given, in the interpretation's own format" do
      image = Image.new!(2, 2, color: [1000, 30_000, 45_678], interpretation: :rgb16)

      assert Image.get_pixel!(image, 0, 0) == [1000, 30_000, 45_678]
      assert Image.band_format(image) == {:u, 16}
    end

    test "a single number applies to every band" do
      assert Image.get_pixel!(Image.new!(2, 2, color: 0, bands: 4), 0, 0) == [0, 0, 0, 0]
      assert Image.get_pixel!(Image.new!(2, 2, color: 128), 0, 0) == [128, 128, 128]
    end
  end

  describe "Image.new/3 :color and :bands agreement" do
    test "a one-value list applies to every band" do
      assert Image.get_pixel!(Image.new!(2, 2, color: [128], bands: 3), 0, 0) == [128, 128, 128]
    end

    # libvips' linear widens the canvas to the vector's length, so these used
    # to either ignore :bands or raise out of a non-bang function.
    test "a list that disagrees with :bands is an error rather than a raise" do
      for {color, bands} <- [{[1, 2, 3], 4}, {[1, 2, 3, 4], 3}, {[10, 20], 4}] do
        assert {:error, %Image.Error{reason: :invalid_option}} =
                 Image.new(2, 2, color: color, bands: bands)
      end
    end

    test "a named color fills an explicit band count" do
      assert Image.get_pixel!(Image.new!(2, 2, color: :red, bands: 4), 0, 0) == [255, 0, 0, 255]
    end
  end
end

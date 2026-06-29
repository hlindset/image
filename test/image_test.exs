defmodule Image.Test do
  use ExUnit.Case, async: false
  import Image.TestSupport
  alias Vix.Vips.Operation
  alias Vix.Vips.Image, as: Vimage

  doctest Image
  doctest Image.BandFormat
  doctest Image.Blurhash
  doctest Image.Math
  doctest Image.Social
  doctest Image.YUV

  setup do
    Temp.track!()
    dir = Temp.mkdir!()
    {:ok, %{dir: dir}}
  end

  test "Minimise metadata", %{dir: dir} do
    image = image_path("Kip_small.jpg")
    {:ok, input_info} = File.stat(image)
    {:ok, kip} = Vimage.new_from_file(image)

    {:ok, minimised} = Image.minimize_metadata(kip)

    out_path = Temp.path!(suffix: ".jpg", basedir: dir)
    validate_path = validate_path("Kip_small_with_simple_exif.jpg")

    assert :ok = Vimage.write_to_file(minimised, out_path)

    {:ok, output_info} = File.stat(validate_path)

    assert_images_equal(out_path, validate_path("Kip_small_with_simple_exif.jpg"))
    assert input_info.size > output_info.size * 2
  end

  test "Remove metadata", %{dir: _dir} do
    image = image_path("Kip_small.jpg")
    {:ok, kip} = Vimage.new_from_file(image)

    for {atom_key, raw_header_key} <- [
          {:exif, "exif-data"},
          {:xmp, "xmp-data"},
          {:iptc, "iptc-data"}
        ] do
      {:ok, header_fields} = Vix.Vips.Image.header_field_names(kip)
      assert Enum.member?(header_fields, raw_header_key)
      {:ok, kip} = Image.remove_metadata(kip, [atom_key])
      {:ok, header_fields} = Vix.Vips.Image.header_field_names(kip)
      refute Enum.member?(header_fields, raw_header_key)
    end
  end

  test "Circular Image", %{dir: dir} do
    image = image_path("Kip_small.jpg")
    {:ok, kip} = Vimage.new_from_file(image)
    {:ok, circle} = Image.circle(kip)

    out_path = Temp.path!(suffix: ".png", basedir: dir)
    assert :ok = Vimage.write_to_file(circle, out_path)

    assert_images_equal(out_path, validate_path("Kip_small_circle_mask.png"))
  end

  test "Rounded Image", %{dir: dir} do
    image = image_path("Kip_small.jpg")
    {:ok, kip} = Vimage.new_from_file(image)
    {:ok, rounded} = Image.rounded(kip)

    out_path = Temp.path!(suffix: ".png", basedir: dir)
    assert :ok = Vimage.write_to_file(rounded, out_path)

    assert_images_equal(out_path, validate_path("Kip_small_rounded_mask.png"))
  end

  test "Squircled Image", %{dir: dir} do
    image = image_path("Kip_small.jpg")
    {:ok, kip} = Vimage.new_from_file(image)
    {:ok, squircled} = Image.squircle(kip)

    out_path = Temp.path!(suffix: ".png", basedir: dir)
    assert :ok = Vimage.write_to_file(squircled, out_path)

    assert_images_equal(out_path, validate_path("Kip_small_squircle_mask.png"))
  end

  test "Rounded Image with alpha", %{dir: dir} do
    image = image_path("Kip_small.jpg")
    validate_path = validate_path("Kip_small_alpha_rounded_mask.png")

    {:ok, kip} = Vimage.new_from_file(image)
    {:ok, kip} = Image.add_alpha(kip, 255)
    {:ok, rounded} = Image.rounded(kip)

    out_path = Temp.path!(suffix: ".png", basedir: dir)
    assert :ok = Vimage.write_to_file(rounded, out_path)

    # {:ok, _} = Image.write(rounded, validate_path)

    assert_images_equal(out_path, validate_path)
  end

  test "Squircled Image with alpha", %{dir: dir} do
    image = image_path("Kip_small.jpg")
    validate_path = validate_path("Kip_small_alpha_squircle_mask.png")

    {:ok, kip} = Vimage.new_from_file(image)
    {:ok, kip} = Image.add_alpha(kip, 255)
    {:ok, squircled} = Image.squircle(kip)

    out_path = Temp.path!(suffix: ".png", basedir: dir)
    assert :ok = Vimage.write_to_file(squircled, out_path)

    # {:ok, _} = Image.write(squircled, validate_path)

    assert_images_equal(out_path, validate_path)
  end

  test "Image composition", %{dir: dir} do
    image = image_path("lamborghini-forsennato-concept.jpg")

    {:ok, lambo} = Vimage.new_from_file(image)
    {:ok, grad} = Image.linear_gradient(lambo)

    {:ok, composite} = Operation.composite2(lambo, grad, :VIPS_BLEND_MODE_OVER)

    out_path = Temp.path!(suffix: ".png", basedir: dir)
    assert :ok = Vimage.write_to_file(composite, out_path)

    assert_images_equal(out_path, validate_path("composite_with_gradient.png"))
  end

  @tag :circular_gradient
  test "Circular Image Gradient 1", %{dir: dir} do
    use Image.Math
    validate_path = validate_path("radial_gradient_1.png")

    start = [100, 50, 0]
    finish = [50, 0, 50]
    size = 512

    {:ok, x} = Operation.xyz(size, size)
    {:ok, x} = subtract(x, [Image.width(x) / 2, Image.height(x) / 2])

    {:ok, x0} = Operation.extract_band(x, 0)
    {:ok, x1} = Operation.extract_band(x, 1)

    d =
      pow!(x0, 2)
      |> add!(pow!(x1, 2))
      |> pow!(0.5)
      |> divide!(2 ** 0.5 * size / 2)

    out =
      d
      |> multiply!(finish)
      |> add!(multiply!(d, -1) |> add!(1) |> multiply!(start))

    {:ok, out} = Operation.copy(out, interpretation: :VIPS_INTERPRETATION_sRGB)

    out_path = Temp.path!(suffix: ".png", basedir: dir)
    assert :ok = Vimage.write_to_file(out, out_path)

    # Image.preview out
    # Image.preview Image.open!(validate_path)

    # Image.write!(out, validate_path)
    assert_images_equal(out_path, validate_path, 2.0)
  end

  test "Circular Image Gradient 2", %{dir: dir} do
    use Image.Math

    start = [255, 0, 0]
    finish = [0, 0, 255]

    {:ok, x} = Operation.xyz(100, 200)
    {:ok, x} = subtract(x, [Image.width(x) / 2, Image.height(x) / 2])

    {:ok, x0} = Operation.extract_band(x, 0)
    {:ok, x1} = Operation.extract_band(x, 1)

    d =
      x0
      |> pow!(2)
      |> add!(pow!(x1, 2))
      |> pow!(0.5)

    d =
      d
      |> multiply!(10)
      |> cos!()
      |> divide!(2)
      |> add!(0.5)

    out =
      d
      |> multiply!(finish)
      |> add!(multiply!(d, -1) |> add!(1) |> multiply!(start))

    {:ok, out} = Operation.copy(out, interpretation: :VIPS_INTERPRETATION_sRGB)

    out_path = Temp.path!(suffix: ".png", basedir: dir)
    assert :ok = Vimage.write_to_file(out, out_path)

    assert_images_equal(out_path, validate_path("radial_gradient_2.png"))
  end

  # This test validates the expected operation of infix operators
  # working on Image data. This behaviour is driven by `use Image.Math`.

  test "Math operators to create a white circle", %{dir: dir} do
    use Image.Math

    {:ok, im} = Operation.xyz(200, 200)

    # move the origin to the centre
    im = im - [Image.width(im) / 2, Image.height(im) / 2]

    # a one-band image where pixels are distance from the centre
    im = (im[0] ** 2 + im[1] ** 2) ** 0.5

    # relational operations make uchar images with 0 for false, 255 for true
    im = im < Image.width(im) / 3

    out_path = Temp.path!(suffix: ".png", basedir: dir)
    assert :ok = Vimage.write_to_file(im, out_path)

    assert_images_equal(out_path, validate_path("image_circle_white.png"))
  end

  test "Rotating an image 90 degrees", %{dir: dir} do
    image = image_path("Kip_small.jpg")
    {:ok, kip} = Vimage.new_from_file(image)
    {:ok, rotated} = Image.rotate(kip, 90.0)

    out_path = Temp.path!(suffix: ".jpg", basedir: dir)
    assert :ok = Vimage.write_to_file(rotated, out_path)

    assert_images_equal(out_path, validate_path("Kip_small_rotate90.jpg"))
  end

  test "Rotating an image -90 degrees", %{dir: dir} do
    image = image_path("Kip_small.jpg")
    {:ok, kip} = Vimage.new_from_file(image)
    {:ok, rotated} = Image.rotate(kip, -90.0)

    out_path = Temp.path!(suffix: ".jpg", basedir: dir)
    assert :ok = Vimage.write_to_file(rotated, out_path)

    assert_images_equal(out_path, validate_path("Kip_small_rotate-90.jpg"))
  end

  test "Rotating an image 45 degrees", %{dir: dir} do
    image = image_path("Kip_small.jpg")
    {:ok, kip} = Vimage.new_from_file(image)
    {:ok, rotated} = Image.rotate(kip, 45)

    out_path = Temp.path!(suffix: ".jpg", basedir: dir)
    assert :ok = Vimage.write_to_file(rotated, out_path)

    assert_images_equal(out_path, validate_path("Kip_small_rotate45.jpg"))
  end

  test "Rotating an image 45 degrees with white background", %{dir: dir} do
    image = image_path("Kip_small.jpg")
    {:ok, kip} = Vimage.new_from_file(image)
    {:ok, rotated} = Image.rotate(kip, 45, background: [255, 255, 255])

    out_path = Temp.path!(suffix: ".jpg", basedir: dir)
    assert :ok = Vimage.write_to_file(rotated, out_path)

    assert_images_equal(out_path, validate_path("Kip_small_rotate45_white.jpg"))
  end

  test "Rotating an image 45 degrees with displacement", %{dir: dir} do
    image = image_path("Kip_small.jpg")
    {:ok, kip} = Vimage.new_from_file(image)
    {:ok, rotated} = Image.rotate(kip, 45, odx: 10, ody: 10, background: [255, 255, 255])

    out_path = Temp.path!(suffix: ".jpg", basedir: dir)
    assert :ok = Vimage.write_to_file(rotated, out_path)

    assert_images_equal(out_path, validate_path("Kip_small_rotate45_displaced.jpg"))
  end

  test "Convert to polar coordinates", %{dir: dir} do
    image = image_path("San-Francisco-2018-04-2549.jpg")
    {:ok, image} = Vimage.new_from_file(image)
    {:ok, polar} = Image.to_polar_coordinates(image)

    out_path = Temp.path!(suffix: ".jpg", basedir: dir)
    assert :ok = Vimage.write_to_file(polar, out_path)

    assert_images_equal(out_path, validate_path("polar.jpg"))
  end

  test "Convert to rectangular coordinates", %{dir: dir} do
    image = validate_path("polar.jpg")
    {:ok, image} = Vimage.new_from_file(image)
    {:ok, rectangular} = Image.to_rectangular_coordinates(image)

    out_path = Temp.path!(suffix: ".jpg", basedir: dir)
    assert :ok = Vimage.write_to_file(rectangular, out_path)

    assert_images_equal(out_path, validate_path("rectangular.jpg"))
  end

  test "Ripple Effect", %{dir: dir} do
    image = image_path("San-Francisco-2018-04-2549.jpg")
    {:ok, image} = Vimage.new_from_file(image)
    {:ok, ripple} = Image.ripple(image)

    out_path = Temp.path!(suffix: ".jpg", basedir: dir)
    assert :ok = Vimage.write_to_file(ripple, out_path)

    assert_images_equal(out_path, validate_path("ripple.jpg"))
  end

  test "Autorotate an image", %{dir: dir} do
    image = image_path("Kip_small_rotated.jpg")
    {:ok, image} = Vimage.new_from_file(image)
    {:ok, {autorotated, flags}} = Image.autorotate(image)

    out_path = Temp.path!(suffix: ".jpg", basedir: dir)
    assert :ok = Vimage.write_to_file(autorotated, out_path)

    assert {:ok, 180} = Map.fetch(flags, :angle)
    assert_images_equal(out_path, validate_path("autorotated.jpg"))
  end

  test "Image.new/3" do
    # 100x100 pixel image of dark blue slate color
    assert {:ok, _image} = Image.new(100, 100, color: :dark_slate_blue)

    # 100x100 pixel green image, fully transparent
    assert {:ok, _image} = Image.new(100, 100, color: [0, 255, 0, 1], bands: 4)
  end

  test "Image.open/2 for different file formats" do
    jpeg_binary = File.read!(image_path("Kip_small.jpg"))
    assert {:ok, _i} = Image.open(jpeg_binary)

    png_binary = File.read!(image_path("Kip_small.png"))
    assert {:ok, _i} = Image.open(png_binary)

    webp_binary = File.read!(image_path("example.webp"))
    assert {:ok, _i} = Image.open(webp_binary)
  end

  test "Splitting an image into its bands" do
    image = Image.open!(image_path("/2x2-maze.png"))
    assert [_, _, _, _] = Image.split_bands(image)
  end

  test "Split alpha band" do
    image = Image.open!(image_path("2x2-maze.png"))
    {bands, alpha} = Image.split_alpha(image)
    assert Image.bands(bands) == 3
    assert Image.bands(alpha) == 1
  end

  test "Image/new 3 default bands" do
    assert Image.bands(Image.new!(20, 20, color: [0, 0, 0, 0])) == 4
    assert Image.bands(Image.new!(20, 20, color: [0, 0, 0])) == 3
  end

  test "Image color replacement" do
    validate_path = validate_path("green.tiff")

    {:ok, red} = Image.new(20, 20, color: :red)
    {:ok, replaced} = Image.replace_color(red, color: :red, replace_with: :green)

    assert_images_equal(replaced, validate_path)
  end

  test "Joining bands results in the same image" do
    image = Image.open!("./test/support/images/Singapore-2016-09-5887.jpg")
    bands = Image.split_bands(image)
    joined = Image.join_bands!(bands)
    assert {:ok, +0.0, _} = Image.compare(image, joined)
  end

  test "Opening an HEIC binary" do
    heic = File.read!("./test/support/images/sample1.heic")
    assert {:ok, _image} = Image.open(heic)
  end

  # The HEIC/AVIF compression tests below probe libvips at compile
  # time. Encoders that the bundled libheif was not built with are
  # skipped automatically; this keeps the suite green on systems
  # where libheif lacks one of HEVC, AV1, JPEG, or AVC.

  describe "Saving an HEIC/AVIF file with different compression methods" do
    setup do
      {:ok, image: Image.open!("./test/support/images/Singapore-2016-09-5887.jpg")}
    end

    @av1_supported Image.TestSupport.heif_compression_supported?(:av1)
    @hevc_supported Image.TestSupport.heif_compression_supported?(:hevc)
    @jpeg_supported Image.TestSupport.heif_compression_supported?(:jpeg)
    @avc_supported Image.TestSupport.heif_compression_supported?(:avc)

    if @av1_supported do
      test ".heic with av1", %{image: image} do
        assert {:ok, _} = Image.write(image, "/tmp/s1.heic", compression: :av1)
      end

      test ".heif with av1", %{image: image} do
        assert {:ok, _} = Image.write(image, "/tmp/s1.heif", compression: :av1)
      end

      test ".avif with av1", %{image: image} do
        assert {:ok, _} = Image.write(image, "/tmp/s1.avif", compression: :av1)
      end
    end

    if @hevc_supported do
      test ".heic with hevc", %{image: image} do
        assert {:ok, _} = Image.write(image, "/tmp/s1.heic", compression: :hevc)
      end

      test ".heif with hevc", %{image: image} do
        assert {:ok, _} = Image.write(image, "/tmp/s1.heif", compression: :hevc)
      end
    end

    if @jpeg_supported do
      test ".avif with jpeg", %{image: image} do
        assert {:ok, _} = Image.write(image, "/tmp/s1.avif", compression: :jpeg)
      end
    end

    if @avc_supported do
      test ".avif with avc", %{image: image} do
        assert {:ok, _} = Image.write(image, "/tmp/s1.avif", compression: :avc)
      end
    end
  end

  describe "Saving a JXL file" do
    @jxl_supported Image.TestSupport.jxl_supported?()

    # A small source image keeps these tests fast. JXL at high effort
    # (e.g. minimize_file_size) on a multi-megapixel image can exceed
    # ExUnit's default per-test timeout under concurrent suite load.
    setup do
      {:ok, image: Image.open!(image_path("Kip_small.jpg"))}
    end

    if @jxl_supported do
      test "writes a bare .jxl to a file path and reads it back", %{image: image, dir: dir} do
        path = Temp.path!(suffix: ".jxl", basedir: dir)
        assert {:ok, _} = Image.write(image, path)

        assert {:ok, reloaded} = Image.open(path)
        assert Image.width(reloaded) == Image.width(image)
        assert Image.height(reloaded) == Image.height(image)
      end

      test "writes a .jxl to :memory", %{image: image} do
        assert {:ok, binary} = Image.write(image, :memory, suffix: ".jxl")
        assert is_binary(binary)
        assert {:ok, _} = Image.from_binary(binary)
      end

      test "writes a .jxl with :quality (higher quality = larger file)", %{image: image, dir: dir} do
        low = Temp.path!(suffix: ".jxl", basedir: dir)
        high = Temp.path!(suffix: ".jxl", basedir: dir)
        assert {:ok, _} = Image.write(image, low, quality: 10)
        assert {:ok, _} = Image.write(image, high, quality: 90)

        # proves :quality actually reaches the encoder, not just that it validates
        assert File.stat!(high).size > File.stat!(low).size
        assert {:ok, _} = Image.open(high)
      end

      test "writes a .jxl with :effort (reaches the encoder)", %{image: image, dir: dir} do
        path = Temp.path!(suffix: ".jxl", basedir: dir)
        assert {:ok, _} = Image.write(image, path, effort: 3)
        assert {:ok, _} = Image.open(path)
      end

      test "lossy: false produces lossless JXL (larger, pixel-identical to source)",
           %{image: image, dir: dir} do
        lossy_path = Temp.path!(suffix: ".jxl", basedir: dir)
        lossless_path = Temp.path!(suffix: ".jxl", basedir: dir)

        assert {:ok, _} = Image.write(image, lossy_path, lossy: true)
        assert {:ok, _} = Image.write(image, lossless_path, lossy: false)

        assert File.stat!(lossless_path).size > File.stat!(lossy_path).size

        # lossless must reproduce the source pixels exactly (tight threshold
        # distinguishes true lossless from merely high-quality lossy)
        {:ok, reloaded} = Image.open(lossless_path)
        assert_images_equal(reloaded, image, 0.01)
      end

      test "writes a .jxl with minimize_file_size: true", %{image: image, dir: dir} do
        path = Temp.path!(suffix: ".jxl", basedir: dir)
        assert {:ok, _} = Image.write(image, path, minimize_file_size: true)
        assert {:ok, _} = Image.open(path)
      end

      test "writes a .jxl with minimize_file_size: false", %{image: image, dir: dir} do
        path = Temp.path!(suffix: ".jxl", basedir: dir)
        assert {:ok, _} = Image.write(image, path, minimize_file_size: false)
        assert {:ok, _} = Image.open(path)
      end

      test "writes a .jxl with :distance (int + float; smaller distance = larger file)",
           %{image: image, dir: dir} do
        near_lossless = Temp.path!(suffix: ".jxl", basedir: dir)
        lossy = Temp.path!(suffix: ".jxl", basedir: dir)
        int_path = Temp.path!(suffix: ".jxl", basedir: dir)

        assert {:ok, _} = Image.write(image, near_lossless, distance: 0.5)
        assert {:ok, _} = Image.write(image, lossy, distance: 10.0)
        assert {:ok, _} = Image.write(image, int_path, distance: 3)

        # :distance is inverse quality — proves the value reaches the encoder
        assert File.stat!(near_lossless).size > File.stat!(lossy).size
      end

      test "writes a .jxl with :tier (higher tier = larger file) and :bitdepth",
           %{image: image, dir: dir} do
        t0 = Temp.path!(suffix: ".jxl", basedir: dir)
        t4 = Temp.path!(suffix: ".jxl", basedir: dir)
        assert {:ok, _} = Image.write(image, t0, tier: 0)
        assert {:ok, _} = Image.write(image, t4, tier: 4)

        # tier trades decode speed for size — tier 4 is larger than tier 0.
        # Proves the value reaches the encoder, not just that it validates.
        assert File.stat!(t4).size > File.stat!(t0).size

        bd = Temp.path!(suffix: ".jxl", basedir: dir)
        assert {:ok, _} = Image.write(image, bd, bitdepth: 8)
        assert {:ok, _} = Image.open(bd)
      end

      test "strip_metadata: true removes EXIF/XMP from a JXL written to :memory",
           %{image: image} do
        exif_count = fn binary ->
          {:ok, i} = Image.from_binary(binary)
          {:ok, names} = Vimage.header_field_names(i)
          Enum.count(names, &(&1 =~ ~r/exif|xmp/i))
        end

        {:ok, kept} = Image.write(image, :memory, suffix: ".jxl", strip_metadata: false)
        {:ok, stripped} = Image.write(image, :memory, suffix: ".jxl", strip_metadata: true)

        assert exif_count.(kept) > 0
        assert exif_count.(stripped) == 0
      end

      test "rejects out-of-range JXL options", %{image: image, dir: dir} do
        path = Temp.path!(suffix: ".jxl", basedir: dir)
        assert {:error, _} = Image.write(image, path, distance: -1)
        assert {:error, _} = Image.write(image, path, distance: 99)
        assert {:error, _} = Image.write(image, path, tier: 9)
        assert {:error, _} = Image.write(image, path, bitdepth: 0)
        assert {:error, _} = Image.write(image, path, effort: 11)
      end

      test "rejects :distance on a non-JXL format", %{image: image, dir: dir} do
        path = Temp.path!(suffix: ".png", basedir: dir)
        assert {:error, _} = Image.write(image, path, distance: 1.0)
      end

      test "writes a .jxl via the jxl: option block", %{image: image, dir: dir} do
        path = Temp.path!(suffix: ".jxl", basedir: dir)
        assert {:ok, _} = Image.write(image, path, jxl: [distance: 1.0])
      end

      test "write!/3 returns the image and raises on a bad option", %{image: image, dir: dir} do
        path = Temp.path!(suffix: ".jxl", basedir: dir)
        assert %Vimage{} = Image.write!(image, path, distance: 1.0)
        assert_raise Image.Error, fn -> Image.write!(image, path, distance: 99) end
      end

      test "rejects :quality and :distance together", %{image: image, dir: dir} do
        path = Temp.path!(suffix: ".jxl", basedir: dir)
        assert {:error, _} = Image.write(image, path, quality: 80, distance: 1.0)
      end

      test "rejects :quality and :distance across the jxl: block", %{image: image, dir: dir} do
        path = Temp.path!(suffix: ".jxl", basedir: dir)
        assert {:error, _} = Image.write(image, path, quality: 80, jxl: [distance: 1.0])
      end

      test "writes a .jxl to a File.Stream and reads it back", %{image: image, dir: dir} do
        path = Temp.path!(suffix: ".jxl", basedir: dir)
        assert {:ok, _} = Image.write(image, File.stream!(path), suffix: ".jxl")

        assert {:ok, reloaded} = Image.open(path)
        assert Image.width(reloaded) == Image.width(image)
      end

      test "writes an uppercase .JXL suffix to a File.Stream (buffered path)",
           %{image: image, dir: dir} do
        # The stream seam matches the suffix case-insensitively; a regression
        # in that downcasing would route .JXL to the non-seekable path and fail.
        path = Temp.path!(suffix: ".JXL", basedir: dir)
        assert {:ok, _} = Image.write(image, File.stream!(path), suffix: ".JXL")
        assert {:ok, _} = Image.open(path)
      end

      test "stream!/2 produces valid JXL bytes", %{image: image} do
        binary =
          image
          |> Image.stream!(suffix: ".jxl")
          |> Enum.into([])
          |> IO.iodata_to_binary()

        assert byte_size(binary) > 0
        assert {:ok, _} = Image.from_binary(binary)
      end

      test "stream!/2 with :buffer_size emits multiple valid JXL chunks", %{image: image} do
        # JXL's buffered single binary must still re-chunk through buffer!/2
        # (the S3 multi-part path).
        chunks = image |> Image.stream!(suffix: ".jxl", buffer_size: 4096) |> Enum.to_list()

        assert length(chunks) > 1
        assert {:ok, _} = Image.from_binary(IO.iodata_to_binary(chunks))
      end
    end
  end
end

defmodule Image.ChromaKey.Test do
  use ExUnit.Case, async: true
  import Image.TestSupport
  alias Vix.Vips.Image, as: Vimage

  setup do
    Temp.track!()
    dir = Temp.mkdir!()
    {:ok, %{dir: dir}}
  end

  test "Chroma Key an image", %{dir: dir} do
    image = image_path("chroma_key/greenscreen.jpg")
    validate_path = validate_path("chroma_key/person.jpg")

    {:ok, image} = Vimage.new_from_file(image)
    {:ok, meme} = Image.chroma_key(image)

    out_path = Temp.path!(suffix: ".jpg", basedir: dir)
    assert :ok = Vimage.write_to_file(meme, out_path)

    # Image.write!(meme, validate_path)
    assert_images_equal out_path, validate_path
  end

  describe "map options" do
    setup do
      {:ok, %{image: Image.new!(20, 20, color: [0, 255, 0])}}
    end

    test "an unrecognised map returns an error rather than raising", %{image: image} do
      assert {:error, %Image.Error{}} = Image.chroma_key(image, %{not_an_option: true})
      assert {:error, %Image.Error{}} = Image.chroma_mask(image, %{not_an_option: true})
    end

    test "a complete color/threshold map is accepted", %{image: image} do
      assert {:ok, %Vimage{}} = Image.chroma_key(image, %{color: [0, 255, 0], threshold: 20})
      assert {:ok, %Vimage{}} = Image.chroma_mask(image, %{color: [0, 255, 0], threshold: 20})
    end

    test "a complete greater_than/less_than map is accepted", %{image: image} do
      options = %{greater_than: [0, 200, 0], less_than: [100, 255, 100]}

      assert {:ok, %Vimage{}} = Image.chroma_key(image, options)
      assert {:ok, %Vimage{}} = Image.chroma_mask(image, options)
    end

    # Omitting :color also exercises the :auto default and so the
    # chroma_color/1 path.
    test "a partial map is completed from the defaults", %{image: image} do
      assert {:ok, %Vimage{}} = Image.chroma_key(image, %{threshold: 20})
    end

    test "a map and the equivalent keyword list produce the same mask", %{image: image} do
      {:ok, from_map} = Image.chroma_mask(image, %{color: [0, 255, 0], threshold: 20})
      {:ok, from_list} = Image.chroma_mask(image, color: [0, 255, 0], threshold: 20)

      assert Vimage.write_to_binary(from_map) == Vimage.write_to_binary(from_list)
    end
  end
end

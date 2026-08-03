defmodule Image.Position.Test do
  use ExUnit.Case, async: true
  doctest Image.Position

  alias Image.Position

  # A 200px rectangle placed within a 300px container throughout, so the flush
  # right position is 100 and the centered position is 50.
  @placed 200
  @container 300

  defp x(spec), do: Position.resolve(:x, spec, @placed, @container)
  defp y(spec), do: Position.resolve(:y, spec, @placed, @container)

  describe "symbolic placement" do
    test "places flush against the named edge" do
      assert x(:left) == {:ok, 0}
      assert x(:right) == {:ok, 100}
      assert y(:top) == {:ok, 0}
      assert y(:bottom) == {:ok, 100}
    end

    test "centers on both axes" do
      assert x(:center) == {:ok, 50}
      assert y(:middle) == {:ok, 50}
    end

    test "rejects a tag belonging to the other axis" do
      assert {:error, %Image.Error{reason: :invalid_option, value: {:y, :left}}} = y(:left)
      assert {:error, %Image.Error{reason: :invalid_option, value: {:x, :top}}} = x(:top)
    end
  end

  describe "tagged offsets" do
    test "measure inward from the named edge" do
      assert x({:left, 10}) == {:ok, 10}
      assert x({:right, 10}) == {:ok, 90}
      assert y({:bottom, 10}) == {:ok, 90}
    end

    test "a zero offset is the flush position" do
      assert x({:right, 0}) == x(:right)
      assert y({:bottom, 0}) == y(:bottom)
      assert x({:left, 0}) == x(:left)
    end

    test "a negative offset places the rectangle beyond the edge" do
      assert x({:right, -10}) == {:ok, 110}
      assert x({:left, -10}) == {:ok, -10}
    end

    test "offsets a centered rectangle" do
      assert x({:center, 10}) == {:ok, 60}
      assert y({:middle, -10}) == {:ok, 40}
    end

    test "rejects a non-integer offset" do
      assert {:error, %Image.Error{reason: :invalid_option}} = x({:right, :nope})
    end
  end

  describe "bare integers" do
    test "a non-negative integer is an offset from the near edge" do
      assert x(40) == {:ok, 40}
      assert y(40) == {:ok, 40}
    end

    test "a negative integer is not a specification" do
      assert {:error, %Image.Error{reason: :invalid_option, value: {:x, -1}}} = x(-1)
    end
  end

  test "resolves against extents where the container is smaller than the placed rectangle" do
    # A centered crop: the rectangle overhangs equally on both sides.
    assert Position.resolve(:x, :center, 120, 100) == {:ok, -10}
    assert Position.resolve(:x, :right, 120, 100) == {:ok, -20}
  end

  test "rejects a specification it cannot interpret" do
    assert {:error, %Image.Error{reason: :invalid_option, value: {:x, nil}}} = x(nil)
    assert {:error, %Image.Error{reason: :invalid_option}} = x("left")
    assert {:error, %Image.Error{reason: :invalid_option}} = x({:left, 1, 2})
  end
end

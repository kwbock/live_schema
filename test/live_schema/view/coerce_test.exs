defmodule LiveSchema.View.CoerceTest do
  use ExUnit.Case, async: true

  alias LiveSchema.View.Coerce

  describe "coerce/2 with :integer" do
    test "converts string to integer" do
      assert Coerce.coerce("42", :integer) == 42
      assert Coerce.coerce("-10", :integer) == -10
      assert Coerce.coerce("0", :integer) == 0
    end

    test "passes through integer values" do
      assert Coerce.coerce(42, :integer) == 42
      assert Coerce.coerce(-10, :integer) == -10
    end

    test "raises on invalid string" do
      assert_raise ArgumentError, fn ->
        Coerce.coerce("not_a_number", :integer)
      end
    end
  end

  describe "coerce/2 with :float" do
    test "converts string to float" do
      assert Coerce.coerce("3.14", :float) == 3.14
      assert Coerce.coerce("-2.5", :float) == -2.5
    end

    test "passes through float values" do
      assert Coerce.coerce(3.14, :float) == 3.14
    end

    test "converts integer to float" do
      assert Coerce.coerce(42, :float) == 42.0
    end

    test "raises on invalid string" do
      assert_raise ArgumentError, fn ->
        Coerce.coerce("not_a_float", :float)
      end
    end
  end

  describe "coerce/2 with :boolean" do
    test "converts string true/false" do
      assert Coerce.coerce("true", :boolean) == true
      assert Coerce.coerce("false", :boolean) == false
    end

    test "passes through boolean values" do
      assert Coerce.coerce(true, :boolean) == true
      assert Coerce.coerce(false, :boolean) == false
    end
  end

  describe "coerce/2 with :atom" do
    test "converts string to existing atom" do
      # These atoms exist in the test runtime
      assert Coerce.coerce("ok", :atom) == :ok
      assert Coerce.coerce("error", :atom) == :error
    end

    test "passes through atom values" do
      assert Coerce.coerce(:ok, :atom) == :ok
    end

    test "raises on non-existing atom" do
      assert_raise ArgumentError, fn ->
        Coerce.coerce("definitely_not_an_existing_atom_xyz123", :atom)
      end
    end
  end

  describe "coerce/2 with :string" do
    test "converts values to string" do
      assert Coerce.coerce(123, :string) == "123"
      assert Coerce.coerce(:hello, :string) == "hello"
      assert Coerce.coerce("already_string", :string) == "already_string"
    end
  end

  describe "coerce/2 with nil" do
    test "passes through any value unchanged" do
      assert Coerce.coerce("hello", nil) == "hello"
      assert Coerce.coerce(123, nil) == 123
      assert Coerce.coerce(:atom, nil) == :atom
      assert Coerce.coerce([1, 2, 3], nil) == [1, 2, 3]
    end
  end
end

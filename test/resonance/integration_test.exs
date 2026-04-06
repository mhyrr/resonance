defmodule Resonance.IntegrationTest do
  use ExUnit.Case, async: false

  alias Resonance.Renderable

  setup do
    original_provider = Application.get_env(:resonance, :provider)
    original_api_key = Application.get_env(:resonance, :api_key)
    original_model = Application.get_env(:resonance, :model)

    Application.put_env(:resonance, :provider, Resonance.Test.MockProvider)
    Application.put_env(:resonance, :api_key, "test")
    Application.put_env(:resonance, :model, "test-model")

    on_exit(fn ->
      if original_provider,
        do: Application.put_env(:resonance, :provider, original_provider),
        else: Application.delete_env(:resonance, :provider)

      if original_api_key,
        do: Application.put_env(:resonance, :api_key, original_api_key),
        else: Application.delete_env(:resonance, :api_key)

      if original_model,
        do: Application.put_env(:resonance, :model, original_model),
        else: Application.delete_env(:resonance, :model)
    end)

    :ok
  end

  describe "generate/2 end-to-end" do
    test "returns renderables from mock provider and resolver" do
      assert {:ok, renderables} =
               Resonance.generate("test prompt", %{resolver: Resonance.Test.MockResolver})

      assert is_list(renderables)
      assert length(renderables) >= 1

      renderable = hd(renderables)
      assert %Renderable{} = renderable
      assert renderable.status == :ready
      assert renderable.type == "rank_entities"
      assert renderable.props != nil
      assert renderable.props != %{}
    end

    test "renderable props contain resolved data" do
      {:ok, [renderable]} =
        Resonance.generate("test prompt", %{resolver: Resonance.Test.MockResolver})

      assert renderable.props.title == "Test Ranking"
      assert is_list(renderable.props.data)
      assert length(renderable.props.data) == 3
    end
  end

  describe "generate_stream/3" do
    test "streams component_ready and done messages to caller" do
      assert :ok =
               Resonance.generate_stream(
                 "test prompt",
                 %{resolver: Resonance.Test.MockResolver},
                 self()
               )

      assert_receive {:resonance, {:component_ready, %Renderable{} = renderable}}, 1000
      assert renderable.status == :ready
      assert renderable.type == "rank_entities"
      assert renderable.props != nil
      assert renderable.props != %{}

      assert_receive {:resonance, :done}, 1000
    end

    test "streamed renderable contains resolved data" do
      :ok =
        Resonance.generate_stream(
          "test prompt",
          %{resolver: Resonance.Test.MockResolver},
          self()
        )

      assert_receive {:resonance, {:component_ready, renderable}}, 1000
      assert renderable.props.title == "Test Ranking"
      assert is_list(renderable.props.data)
      assert length(renderable.props.data) == 3

      assert_receive {:resonance, :done}, 1000
    end
  end
end

defmodule MetadataTest do
  use ExUnit.Case, async: true
  import Mock

  test "get_brokers returns brokers for topic" do
    response = TestHelper.generate_metadata_response(1,
      [%{node_id: 0, host: "localhost", port: 9092},
       %{node_id: 1, host: "foo",       port: 9092}],
      [%{error_code: 0, name: "test", partitions:
          [%{error_code: 0, id: 0, leader: 0, replicas: [0,1], isrs: [0,1]},
           %{error_code: 0, id: 1, leader: 0, replicas: [0,1], isrs: [0,1]}]},
       %{error_code: 0, name: "fnord", partitions:
          [%{error_code: 0, id: 0, leader: 1, replicas: [0,1], isrs: [0,1]},
           %{error_code: 0, id: 1, leader: 1, replicas: [0,1], isrs: [0,1]}]}])

    with_mock Kafka.Connection, [send: fn(_, _) -> response end] do
      metadata = Kafka.Metadata.new(%{correlation_id: 1}, "foo")
      brokers_for_topic = Kafka.Metadata.get_brokers(metadata, "foo", ["fnord"])
      assert brokers_for_topic == %{%{host: "foo", port: 9092, socket: nil} => %{"fnord" => [0, 1]}}
    end
  end

  test "get metadata for single node and topic" do
    response = TestHelper.generate_metadata_response(1,
      [%{node_id: 0, host: "localhost", port: 9092}],
      [%{error_code: 0, name: "test", partitions:
          [%{error_code: 0, id: 0, leader: 0, replicas: [0], isrs: [0]}]}])

    with_mock Kafka.Connection, [send: fn(_, _) -> response end] do
      %{brokers: broker_map, topics: topic_map, timestamp: _} =
        Kafka.Metadata.get(%{correlation_id: 1}, "foo")
      assert broker_map == %{0 => %{host: "localhost", port: 9092, socket: nil}}
      assert topic_map  == %{"test" =>
        [error_code: 0, partitions: %{0 => %{error_code: 0, isrs: [0], leader: 0, replicas: [0]}}]}
    end
  end

  test "get metadata for multiple nodes and topics" do
    response = TestHelper.generate_metadata_response(1,
      [%{node_id: 0, host: "localhost", port: 9092},
       %{node_id: 1, host: "foo",       port: 9092}],
      [%{error_code: 0, name: "test", partitions:
          [%{error_code: 0, id: 0, leader: 0, replicas: [0,1], isrs: [0,1]},
           %{error_code: 0, id: 1, leader: 0, replicas: [0,1], isrs: [0,1]}]},
       %{error_code: 0, name: "fnord", partitions:
          [%{error_code: 0, id: 0, leader: 1, replicas: [0,1], isrs: [0,1]},
           %{error_code: 0, id: 1, leader: 1, replicas: [0,1], isrs: [0,1]}]}])

    with_mock Kafka.Connection, [send: fn(_, _) -> response end] do
      %{brokers: broker_map, topics: topic_map, timestamp: _} =
        Kafka.Metadata.get(%{correlation_id: 1}, "foo")
      assert broker_map == %{0 =>
        %{host: "localhost", port: 9092, socket: nil}, 1 => %{host: "foo", port: 9092, socket: nil}}
      assert topic_map  == %{"fnord" => [error_code: 0,
          partitions: %{0 => %{error_code: 0, isrs: [0, 1], leader: 1, replicas: [0, 1]},
            1 => %{error_code: 0, isrs: [0, 1], leader: 1, replicas: [0, 1]}}],
        "test" => [error_code: 0,
          partitions: %{0 => %{error_code: 0, isrs: [0, 1], leader: 0, replicas: [0, 1]},
            1 => %{error_code: 0, isrs: [0, 1], leader: 0, replicas: [0, 1]}}]}
    end
  end

  test "calling get again in < 5 minutes returns the same metadata" do
    response = TestHelper.generate_metadata_response(1,
      [%{node_id: 0, host: "localhost", port: 9092}],
      [%{error_code: 0, name: "test", partitions:
          [%{error_code: 0, id: 0, leader: 0, replicas: [0], isrs: [0]}]}])

    with_mock Kafka.Connection, [send: fn(_, _) -> response end] do
      metadata = Kafka.Metadata.get(%{correlation_id: 1}, "foo")
      :timer.sleep(1000)
      assert metadata == Kafka.Metadata.update(metadata, "foo")
    end
  end

  test "calling get again in > 5 minutes returns new metadata" do
    response = TestHelper.generate_metadata_response(1,
      [%{node_id: 0, host: "localhost", port: 9092}],
      [%{error_code: 0, name: "test", partitions:
          [%{error_code: 0, id: 0, leader: 0, replicas: [0], isrs: [0]}]}])

    with_mock Kafka.Connection, [send: fn(_, _) -> response end] do
      metadata = Kafka.Metadata.get(%{correlation_id: 1}, "foo")
      {mega, secs, _} = :os.timestamp
      ts = mega * 1000000 + secs + 6 * 60
      with_mock Kafka.Helper, [get_timestamp: fn -> ts end] do
        assert metadata != Kafka.Metadata.update(metadata, "foo")
      end
    end
  end
end
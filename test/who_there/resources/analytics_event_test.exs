defmodule WhoThere.Resources.AnalyticsEventTest do
  use ExUnit.Case, async: true

  alias WhoThere.Resources.AnalyticsEvent

  setup do
    tenant_id = Ash.UUID.generate()
    session_id = Ash.UUID.generate()
    {:ok, tenant_id: tenant_id, session_id: session_id}
  end

  describe "creation" do
    test "creates event with valid attributes", %{tenant_id: tenant_id, session_id: session_id} do
      attrs = %{
        tenant_id: tenant_id,
        event_type: :page_view,
        path: "/home",
        session_id: session_id,
        user_agent: "Mozilla/5.0 (compatible; test)",
        ip_address: "192.168.1.1"
      }

      assert {:ok, event} = AnalyticsEvent.create(attrs, tenant: tenant_id)
      assert event.tenant_id == tenant_id
      assert event.event_type == :page_view
      assert event.path == "/home"
      assert event.session_id == session_id
      assert %DateTime{} = event.timestamp
    end

    test "auto-sets timestamp if not provided", %{tenant_id: tenant_id} do
      attrs = %{
        tenant_id: tenant_id,
        event_type: :page_view,
        path: "/test"
      }

      assert {:ok, event} = AnalyticsEvent.create(attrs, tenant: tenant_id)
      assert %DateTime{} = event.timestamp
      # Timestamp should be recent (within last 5 seconds)
      assert DateTime.diff(DateTime.utc_now(), event.timestamp) < 5
    end

    test "detects bot traffic automatically", %{tenant_id: tenant_id} do
      attrs = %{
        tenant_id: tenant_id,
        event_type: :page_view,
        path: "/test",
        user_agent: "Googlebot/2.1"
      }

      assert {:ok, event} = AnalyticsEvent.create(attrs, tenant: tenant_id)
      assert event.event_type == :bot_traffic
      assert event.bot_name != nil
    end

    test "validates required fields", %{tenant_id: tenant_id} do
      # Missing event_type
      attrs = %{tenant_id: tenant_id, path: "/test"}
      assert {:error, %Ash.Error.Invalid{}} = AnalyticsEvent.create(attrs, tenant: tenant_id)

      # Missing path
      attrs = %{tenant_id: tenant_id, event_type: :page_view}
      assert {:error, %Ash.Error.Invalid{}} = AnalyticsEvent.create(attrs, tenant: tenant_id)

      # Missing tenant_id
      attrs = %{event_type: :page_view, path: "/test"}
      assert {:error, %Ash.Error.Invalid{}} = AnalyticsEvent.create(attrs)
    end

    test "validates event_type is valid", %{tenant_id: tenant_id} do
      attrs = %{
        tenant_id: tenant_id,
        event_type: :invalid_type,
        path: "/test"
      }

      assert {:error, %Ash.Error.Invalid{}} = AnalyticsEvent.create(attrs, tenant: tenant_id)
    end

    test "validates path format", %{tenant_id: tenant_id} do
      # Path must start with /
      attrs = %{
        tenant_id: tenant_id,
        event_type: :page_view,
        path: "invalid-path"
      }

      assert {:error, %Ash.Error.Invalid{}} = AnalyticsEvent.create(attrs, tenant: tenant_id)

      # Valid path
      attrs = %{
        tenant_id: tenant_id,
        event_type: :page_view,
        path: "/valid-path"
      }

      assert {:ok, _event} = AnalyticsEvent.create(attrs, tenant: tenant_id)
    end

    test "validates status code range", %{tenant_id: tenant_id} do
      # Invalid status code
      attrs = %{
        tenant_id: tenant_id,
        event_type: :api_call,
        path: "/api/test",
        status_code: 999
      }

      assert {:error, %Ash.Error.Invalid{}} = AnalyticsEvent.create(attrs, tenant: tenant_id)

      # Valid status code
      attrs = %{
        tenant_id: tenant_id,
        event_type: :api_call,
        path: "/api/test",
        status_code: 200
      }

      assert {:ok, _event} = AnalyticsEvent.create(attrs, tenant: tenant_id)
    end

    test "validates country code format", %{tenant_id: tenant_id} do
      # Invalid country code length
      attrs = %{
        tenant_id: tenant_id,
        event_type: :page_view,
        path: "/test",
        country_code: "USA"
      }

      assert {:error, %Ash.Error.Invalid{}} = AnalyticsEvent.create(attrs, tenant: tenant_id)

      # Valid country code
      attrs = %{
        tenant_id: tenant_id,
        event_type: :page_view,
        path: "/test",
        country_code: "US"
      }

      assert {:ok, _event} = AnalyticsEvent.create(attrs, tenant: tenant_id)
    end

    test "validates bot events have bot_name", %{tenant_id: tenant_id} do
      attrs = %{
        tenant_id: tenant_id,
        event_type: :bot_traffic,
        path: "/test"
        # missing bot_name
      }

      assert {:error, %Ash.Error.Invalid{}} = AnalyticsEvent.create(attrs, tenant: tenant_id)

      # Valid bot event
      attrs = %{
        tenant_id: tenant_id,
        event_type: :bot_traffic,
        path: "/test",
        bot_name: "Googlebot"
      }

      assert {:ok, _event} = AnalyticsEvent.create(attrs, tenant: tenant_id)
    end

    test "prevents future timestamps", %{tenant_id: tenant_id} do
      future_time = DateTime.utc_now() |> DateTime.add(3600, :second)

      attrs = %{
        tenant_id: tenant_id,
        event_type: :page_view,
        path: "/test",
        timestamp: future_time
      }

      assert {:error, %Ash.Error.Invalid{}} = AnalyticsEvent.create(attrs, tenant: tenant_id)
    end
  end

  describe "reading" do
    test "reads events by date range", %{tenant_id: tenant_id} do
      now = DateTime.utc_now()
      yesterday = DateTime.add(now, -86400, :second)
      tomorrow = DateTime.add(now, 86400, :second)

      # Create event within range
      attrs = %{
        tenant_id: tenant_id,
        event_type: :page_view,
        path: "/test",
        timestamp: now
      }

      assert {:ok, event} = AnalyticsEvent.create(attrs, tenant: tenant_id)

      # Query by date range
      assert {:ok, events} = AnalyticsEvent.by_date_range(yesterday, tomorrow, tenant: tenant_id)
      assert Enum.any?(events, &(&1.id == event.id))
    end

    test "reads events by event type", %{tenant_id: tenant_id} do
      # Create page view event
      attrs = %{
        tenant_id: tenant_id,
        event_type: :page_view,
        path: "/test1"
      }

      assert {:ok, page_event} = AnalyticsEvent.create(attrs, tenant: tenant_id)

      # Create API call event
      attrs = %{
        tenant_id: tenant_id,
        event_type: :api_call,
        path: "/api/test"
      }

      assert {:ok, _api_event} = AnalyticsEvent.create(attrs, tenant: tenant_id)

      # Query by event type
      assert {:ok, events} = AnalyticsEvent.by_event_type(:page_view, tenant: tenant_id)
      assert Enum.any?(events, &(&1.id == page_event.id))
      assert Enum.all?(events, &(&1.event_type == :page_view))
    end

    test "reads events by session", %{tenant_id: tenant_id, session_id: session_id} do
      # Create event with session
      attrs = %{
        tenant_id: tenant_id,
        event_type: :page_view,
        path: "/test",
        session_id: session_id
      }

      assert {:ok, event} = AnalyticsEvent.create(attrs, tenant: tenant_id)

      # Query by session
      assert {:ok, events} = AnalyticsEvent.by_session(session_id, tenant: tenant_id)
      assert Enum.any?(events, &(&1.id == event.id))
      assert Enum.all?(events, &(&1.session_id == session_id))
    end

    test "tenant isolation works correctly", %{session_id: session_id} do
      tenant1 = Ash.UUID.generate()
      tenant2 = Ash.UUID.generate()

      # Create event for tenant1
      attrs1 = %{
        tenant_id: tenant1,
        event_type: :page_view,
        path: "/test1"
      }

      assert {:ok, event1} = AnalyticsEvent.create(attrs1, tenant: tenant1)

      # Create event for tenant2
      attrs2 = %{
        tenant_id: tenant2,
        event_type: :page_view,
        path: "/test2"
      }

      assert {:ok, _event2} = AnalyticsEvent.create(attrs2, tenant: tenant2)

      # Tenant1 should only see their events
      assert {:ok, events} = AnalyticsEvent.read(tenant: tenant1)
      assert Enum.any?(events, &(&1.id == event1.id))
      assert Enum.all?(events, &(&1.tenant_id == tenant1))
    end
  end

  describe "calculations" do
    test "is_bot_traffic calculation works", %{tenant_id: tenant_id} do
      # Create bot event
      bot_attrs = %{
        tenant_id: tenant_id,
        event_type: :bot_traffic,
        path: "/test",
        bot_name: "Googlebot"
      }

      assert {:ok, bot_event} = AnalyticsEvent.create(bot_attrs, tenant: tenant_id)

      # Create human event
      human_attrs = %{
        tenant_id: tenant_id,
        event_type: :page_view,
        path: "/test"
      }

      assert {:ok, human_event} = AnalyticsEvent.create(human_attrs, tenant: tenant_id)

      # Load calculation
      assert {:ok, events} =
               AnalyticsEvent
               |> Ash.Query.load(:is_bot_traffic)
               |> AnalyticsEvent.read(tenant: tenant_id)

      bot_result = Enum.find(events, &(&1.id == bot_event.id))
      human_result = Enum.find(events, &(&1.id == human_event.id))

      assert bot_result.is_bot_traffic == true
      assert human_result.is_bot_traffic == false
    end

    test "geographic_label calculation works", %{tenant_id: tenant_id} do
      # Event with city and country
      attrs = %{
        tenant_id: tenant_id,
        event_type: :page_view,
        path: "/test",
        city: "New York",
        country_code: "US"
      }

      assert {:ok, event} = AnalyticsEvent.create(attrs, tenant: tenant_id)

      # Load calculation
      assert {:ok, [event_with_calc]} =
               AnalyticsEvent
               |> Ash.Query.load(:geographic_label)
               |> Ash.Query.filter(id == event.id)
               |> AnalyticsEvent.read(tenant: tenant_id)

      assert event_with_calc.geographic_label == "New York, US"
    end
  end
end

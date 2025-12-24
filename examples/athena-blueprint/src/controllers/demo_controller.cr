require "athena"
require "datastar"
require "datastar/adapters/athena"
require "datastar/adapters/blueprint"
require "../components/*"

# Demo controller showcasing Datastar SSE streaming with Blueprint components.
class DemoController < ATH::Controller
  include Datastar::Athena::LiveController
  @@counter_active = Atomic(Bool).new(false)

  # Renders the main demo page.
  @[ARTA::Get("/")]
  def index : ATH::Response
    datastar_render(IndexPage.new)
  end

  # SSE endpoint that streams a counter incrementing every second.
  @[ARTA::Get("/counter/start")]
  def start_counter(request : ATH::Request) : ATH::StreamedResponse
    pp request
    datastar_stream(request) do |sse|
      if @@counter_active.get && !sse.closed?
        sse.patch_elements(StatusMessage.new("Counter is already running!"))
      else
        @@counter_active.set(true)
        sse.patch_elements(StatusMessage.new("Counter started!"))

        count = 0
        while @@counter_active.get && !sse.closed?
          sse.patch_elements(Counter.new(count))
          sleep 1.second
          count += 1
        end
      end
    end
  end

  # SSE endpoint that stops the counter (demonstrates one-off events).
  @[ARTA::Get("/counter/stop")]
  def stop_counter(request : ATH::Request) : ATH::StreamedResponse
    datastar_stream(request) do |sse|
      @@counter_active.set(false)
      sse.patch_elements(StatusMessage.new("Counter stopped by user"))
    end
  end

  # SSE endpoint that streams the current server time.
  @[ARTA::Get("/clock")]
  def clock(request : ATH::Request) : ATH::StreamedResponse
    datastar_stream(request) do |sse|
      loop do
        break if sse.closed?
        sse.patch_elements(Clock.new(Time.local))
        sleep 1.second
      end
    end
  end

  # SSE endpoint that returns a personalized greeting.
  # Reads the name from signals sent by the browser.
  @[ARTA::Get("/greet")]
  def greet(request : ATH::Request) : ATH::StreamedResponse
    datastar_stream(request) do |sse|
      signals = sse.signals
      name = signals["name"]?.try(&.as_s?) || "Anonymous"
      name = "Anonymous" if name.blank?

      sse.patch_elements(Greeting.new(name))
    end
  end
end

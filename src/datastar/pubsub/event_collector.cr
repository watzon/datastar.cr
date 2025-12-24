require "json"
require "../consts"
require "../renderable"
require "../server_sent_event"

module Datastar::PubSub
  # Collects SSE events without writing to IO.
  #
  # Used by broadcast blocks to capture events that will
  # be serialized and sent to all subscribed connections.
  class EventCollector
    @events : Array(ServerSentEvent)

    def initialize
      @events = [] of ServerSentEvent
    end

    # Patches elements into the DOM.
    def patch_elements(
      fragment : String | Renderable,
      *,
      selector : String = WHOLE_DOCUMENT_SELECTOR,
      mode : FragmentMergeMode = DEFAULT_FRAGMENT_MERGE_MODE,
      use_view_transition : Bool = DEFAULT_USE_VIEW_TRANSITION
    ) : Nil
      patch_elements([fragment], selector: selector, mode: mode, use_view_transition: use_view_transition)
    end

    # Patches multiple elements into the DOM.
    def patch_elements(
      fragments : Array(String | Renderable),
      *,
      selector : String = WHOLE_DOCUMENT_SELECTOR,
      mode : FragmentMergeMode = DEFAULT_FRAGMENT_MERGE_MODE,
      use_view_transition : Bool = DEFAULT_USE_VIEW_TRANSITION
    ) : Nil
      data_lines = [] of String

      unless selector.empty?
        data_lines << "selector #{selector}"
      end

      if mode != DEFAULT_FRAGMENT_MERGE_MODE
        data_lines << "mode #{mode.to_s.downcase}"
      end

      if use_view_transition
        data_lines << "useViewTransition true"
      end

      fragments.each do |fragment|
        html = fragment.is_a?(Renderable) ? fragment.to_datastar_html : fragment
        html.each_line do |line|
          data_lines << "elements #{line}"
        end
      end

      @events << ServerSentEvent.new(
        event_type: EventType::PatchElements,
        data_lines: data_lines
      )
    end

    # Removes elements from the DOM.
    def remove_elements(
      selector : String,
      *,
      use_view_transition : Bool = DEFAULT_USE_VIEW_TRANSITION
    ) : Nil
      data_lines = ["selector #{selector}", "mode remove"]

      if use_view_transition
        data_lines.insert(1, "useViewTransition true")
      end

      @events << ServerSentEvent.new(
        event_type: EventType::PatchElements,
        data_lines: data_lines
      )
    end

    # Patches signals (reactive state) in the browser.
    def patch_signals(**signals) : Nil
      patch_signals(signals, only_if_missing: DEFAULT_SIGNALS_ONLY_IF_MISSING)
    end

    # :ditto:
    def patch_signals(
      signals : Hash | NamedTuple,
      *,
      only_if_missing : Bool = DEFAULT_SIGNALS_ONLY_IF_MISSING
    ) : Nil
      data_lines = [] of String

      if only_if_missing
        data_lines << "onlyIfMissing true"
      end

      data_lines << "signals #{signals.to_json}"

      @events << ServerSentEvent.new(
        event_type: EventType::PatchSignals,
        data_lines: data_lines
      )
    end

    # Executes JavaScript in the browser.
    def execute_script(
      script : String,
      *,
      auto_remove : Bool = DEFAULT_AUTOREMOVE_SCRIPT,
      attributes : Hash(String, String) = {} of String => String
    ) : Nil
      data_lines = [] of String

      if auto_remove
        data_lines << "autoRemove true"
      end

      attributes.each do |key, value|
        data_lines << "attributes #{key} #{value}"
      end

      data_lines << "script #{script}"

      @events << ServerSentEvent.new(
        event_type: EventType::ExecuteScript,
        data_lines: data_lines
      )
    end

    # Serializes all collected events to a payload string.
    def to_payload : String
      @events.map(&.to_s).join
    end
  end
end

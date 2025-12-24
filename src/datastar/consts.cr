module Datastar
  # Datastar protocol version this SDK targets
  DATASTAR_VERSION = "1.0.0-RC.7"

  # Default SSE retry duration in milliseconds
  DEFAULT_SSE_RETRY_DURATION = 1000

  # Default settings
  DEFAULT_FRAGMENT_MERGE_MODE     = FragmentMergeMode::Outer
  DEFAULT_SIGNALS_ONLY_IF_MISSING = false
  DEFAULT_AUTOREMOVE_SCRIPT       = true
  DEFAULT_USE_VIEW_TRANSITION     = false

  # Selector for targeting the whole document
  WHOLE_DOCUMENT_SELECTOR = ""

  # SSE Event types
  module EventType
    PatchElements = "datastar-patch-elements"
    PatchSignals  = "datastar-patch-signals"
    ExecuteScript = "datastar-execute-script"
  end

  # Fragment merge modes for patch_elements
  enum FragmentMergeMode
    Outer
    Inner
    Replace
    Prepend
    Append
    Before
    After
    Remove
  end

  # Request header that indicates a Datastar request
  DATASTAR_REQUEST_HEADER = "Datastar-Request"

  # Query parameter name for signals (used in GET requests)
  DATASTAR_QUERY_PARAM = "datastar"
end

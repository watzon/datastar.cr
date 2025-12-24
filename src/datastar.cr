require "./datastar/version"
require "./datastar/consts"
require "./datastar/configuration"
require "./datastar/renderable"
require "./datastar/server_sent_event"
require "./datastar/request_detection"
require "./datastar/event_stream"
require "./datastar/signals"
require "./datastar/server_sent_event_generator"

module Datastar
  include RequestDetection
end

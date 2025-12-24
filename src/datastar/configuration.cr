module Datastar
  class Configuration
    property heartbeat : Time::Span | Bool = 3.seconds
    property on_error : Proc(Exception, Nil)? = nil
  end

  class_getter config : Configuration = Configuration.new

  def self.configure(& : Configuration ->) : Nil
    yield @@config
  end
end

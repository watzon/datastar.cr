require "./layout"

# The main demo page that extends MainLayout.
class IndexPage < MainLayout
  def page_title : String
    "Datastar + Athena + Blueprint Demo"
  end

  private def blueprint
    h1 { "Datastar + Athena + Blueprint Demo" }

    # Counter Demo
    div class: "card", "data-signals": "{count: 0}" do
      h2 { "Counter Demo" }
      p { "Click the buttons to start/stop a live counter stream." }

      div id: "counter", class: "counter" do
        plain "0"
      end
      div id: "status", class: "status" do
        plain "Ready to start..."
      end

      br
      button "data-on:click": "@get('/counter/start')" do
        plain "Start Counter"
      end
      button "data-on:click": "@get('/counter/stop')", class: "btn-danger" do
        plain "Stop"
      end
    end

    # Clock Demo
    div class: "card" do
      h2 { "Live Clock" }
      p { "Stream the current server time." }

      div id: "clock", class: "time" do
        plain "--:--:--"
      end

      br
      button "data-on:click": "@get('/clock')" do
        plain "Start Clock"
      end
    end

    # Greeting Demo
    div class: "card", "data-signals": "{name: ''}" do
      h2 { "Greeting Demo" }
      p { "Enter your name and get a personalized greeting from the server." }

      input type: "text", "data-bind": "name", placeholder: "Enter your name"
      button "data-on:click": "@get('/greet')" do
        plain "Greet Me!"
      end

      div id: "greeting"
    end
  end
end

require "blueprint/html"

# Base layout class using Blueprint's around_render pattern.
# Pages should inherit from this class and define their own blueprint method.
class MainLayout
  include Blueprint::HTML

  def page_title : String
    "Datastar Demo"
  end

  private def around_render(&)
    doctype
    html lang: "en" do
      head do
        meta charset: "utf-8"
        meta name: "viewport", content: "width=device-width, initial-scale=1"
        title { page_title }

        # Include Datastar from CDN
        script type: "module", src: "https://cdn.jsdelivr.net/gh/starfederation/datastar@1.0.0-RC.7/bundles/datastar.js"

        # Minimal inline styles
        style do
          raw safe(
            <<-CSS
              * { box-sizing: border-box; }
              body {
                font-family: system-ui, -apple-system, sans-serif;
                max-width: 800px;
                margin: 0 auto;
                padding: 2rem;
                background: #f5f5f5;
              }
              .card {
                background: white;
                border-radius: 8px;
                padding: 1.5rem;
                box-shadow: 0 2px 4px rgba(0,0,0,0.1);
                margin-bottom: 1rem;
              }
              .card h2 { margin-top: 0; color: #333; }
              button {
                background: #4a90d9;
                color: white;
                border: none;
                padding: 0.5rem 1rem;
                border-radius: 4px;
                cursor: pointer;
                font-size: 1rem;
                margin-right: 0.5rem;
              }
              button:hover { background: #357abd; }
              button:disabled { background: #ccc; cursor: not-allowed; }
              .counter { font-size: 3rem; font-weight: bold; color: #4a90d9; }
              .status { color: #666; font-size: 0.9rem; margin-top: 1rem; }
              .time { font-size: 1.2rem; color: #333; }
              .btn-danger { background: #d9534f; }
              .btn-danger:hover { background: #c9302c; }
              input {
                padding: 0.5rem;
                font-size: 1rem;
                border: 1px solid #ccc;
                border-radius: 4px;
                margin-right: 0.5rem;
              }
            CSS
          )
        end
      end

      body do
        yield
      end
    end
  end
end

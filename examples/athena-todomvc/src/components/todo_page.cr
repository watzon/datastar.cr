require "blueprint"
require "datastar/adapters/blueprint"

# Renders the full TodoMVC page following the standard TodoMVC HTML structure
class TodoPage
  include Blueprint::HTML

  def blueprint
    doctype
    html lang: "en" do
      head do
        meta charset: "utf-8"
        meta name: "viewport", content: "width=device-width, initial-scale=1"
        title { "Datastar + Athena - TodoMVC" }

        # Standard TodoMVC CSS
        link rel: "stylesheet", href: "https://cdn.jsdelivr.net/npm/todomvc-app-css@2.4.3/index.css"

        # Datastar from CDN
        script type: "module", src: "https://cdn.jsdelivr.net/gh/starfederation/datastar@1.0.0-RC.7/bundles/datastar.js"
      end

      body do
        section class: "todoapp", id: "todomvc", "data-init": "@get('/updates')" do
          header class: "header" do
            h1 { "todos" }
            input id: "toggle-all",
              class: "toggle-all",
              type: "checkbox",
              "data-on:click": "@post('/todos/toggle-all')"
            label for: "toggle-all" do
              "Mark all as complete"
            end
            input class: "new-todo",
              placeholder: "What needs to be done?",
              autofocus: true,
              "data-signals:input": "",
              "data-bind:input": "",
              "data-on:keydown": "evt.key === 'Enter' && $input.trim() && @patch('/todos') && ($input = '')"
          end

          # Main section with todo list - will be populated via SSE
          section class: "main" do
            ul id: "todo-list", class: "todo-list" do
            end
          end

          # Footer - will be populated via SSE
          footer id: "todo-footer", class: "footer" do
          end
        end

        footer class: "info" do
          p { "Double-click to edit a todo" }
          p do
            plain "Built with "
            a href: "https://data-star.dev" do
              "Datastar"
            end
            plain " + "
            a href: "https://athenaframework.org" do
              "Athena"
            end
          end
          p do
            plain "Part of "
            a href: "http://todomvc.com" do
              "TodoMVC"
            end
          end
        end
      end
    end
  end
end

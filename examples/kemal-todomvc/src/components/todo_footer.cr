require "blueprint"
require "datastar/adapters/blueprint"

# Renders the footer following standard TodoMVC HTML structure
class TodoFooter
  include Blueprint::HTML

  def initialize(@pending_count : Int32, @has_completed : Bool, @mode : FilterMode)
  end

  def blueprint
    footer id: "todo-footer", class: "footer" do
      span class: "todo-count" do
        strong { @pending_count.to_s }
        plain " item#{@pending_count == 1 ? "" : "s"} left"
      end

      ul class: "filters" do
        li do
          a href: "#/",
            class: (@mode == FilterMode::All ? "selected" : ""),
            "data-on:click__prevent": "@put('/mode/0')" do
            "All"
          end
        end
        li do
          a href: "#/active",
            class: (@mode == FilterMode::Pending ? "selected" : ""),
            "data-on:click__prevent": "@put('/mode/1')" do
            "Active"
          end
        end
        li do
          a href: "#/completed",
            class: (@mode == FilterMode::Completed ? "selected" : ""),
            "data-on:click__prevent": "@put('/mode/2')" do
            "Completed"
          end
        end
      end

      if @has_completed
        button class: "clear-completed",
          "data-on:click": "@delete('/todos/completed')" do
          "Clear completed"
        end
      end
    end
  end
end

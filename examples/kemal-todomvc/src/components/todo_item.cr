require "blueprint"
require "datastar/adapters/blueprint"

# Renders a single todo item following standard TodoMVC HTML structure
class TodoItem
  include Blueprint::HTML

  def initialize(@todo : Todo, @editing : Bool = false)
  end

  def blueprint
    li id: "todo-#{@todo.id}", class: li_class do
      div class: "view" do
        if @todo.completed
          input class: "toggle",
            type: "checkbox",
            checked: true,
            "data-on:click": "@post('/todos/#{@todo.id}/toggle')"
        else
          input class: "toggle",
            type: "checkbox",
            "data-on:click": "@post('/todos/#{@todo.id}/toggle')"
        end

        label "data-on:dblclick": "@get('/todos/#{@todo.id}/edit')" do
          @todo.text
        end

        button class: "destroy",
          "data-on:click": "@delete('/todos/#{@todo.id}')"
      end

      if @editing
        input class: "edit",
          value: @todo.text,
          autofocus: true,
          "data-signals:editText": @todo.text,
          "data-bind:editText": "",
          "data-on:keydown": "evt.key === 'Enter' && @patch('/todos/#{@todo.id}') || evt.key === 'Escape' && @get('/todos/#{@todo.id}/cancel')",
          "data-on:blur": "@patch('/todos/#{@todo.id}')"
      end
    end
  end

  private def li_class : String
    classes = [] of String
    classes << "completed" if @todo.completed
    classes << "editing" if @editing
    classes.join(" ")
  end
end

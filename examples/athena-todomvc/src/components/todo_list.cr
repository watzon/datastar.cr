require "blueprint"
require "datastar/adapters/blueprint"
require "./todo_item"

# Renders the todo list container with all filtered todos
class TodoList
  include Blueprint::HTML

  def initialize(@todos : Array(Todo))
  end

  def blueprint
    ul id: "todo-list", class: "todo-list" do
      @todos.each do |todo|
        render TodoItem.new(todo)
      end
    end
  end
end

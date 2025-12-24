require "kemal"
require "datastar/adapters/kemal"

require "./store"
require "./components/todo_page"
require "./components/todo_list"
require "./components/todo_item"
require "./components/todo_footer"

# Global store (resets on server restart)
STORE = TodoStore.new

# Serve the main HTML page
get "/" do |env|
  env.datastar_render(TodoPage.new)
end

# SSE endpoint - streams initial state and updates
get "/updates" do |env|
  env.datastar_stream do |sse|
    # Send the current todo list
    sse.patch_elements(TodoList.new(STORE.filtered_todos))

    # Send the footer
    sse.patch_elements(TodoFooter.new(
      STORE.pending_count,
      STORE.has_completed?,
      STORE.mode
    ))
  end
end

# Add a new todo
patch "/todos" do |env|
  env.datastar_stream do |sse|
    # Get the input signal from the request
    signals = sse.signals
    input = signals["input"]?.try(&.as_s?) || ""

    unless input.empty?
      STORE.add(input)

      # Update the UI
      sse.patch_elements(TodoList.new(STORE.filtered_todos))
      sse.patch_elements(TodoFooter.new(
        STORE.pending_count,
        STORE.has_completed?,
        STORE.mode
      ))
    end
  end
end

# Toggle a specific todo
post "/todos/:id/toggle" do |env|
  id = env.params.url["id"]

  env.datastar_stream do |sse|
    STORE.toggle(id)

    # Update the UI
    sse.patch_elements(TodoList.new(STORE.filtered_todos))
    sse.patch_elements(TodoFooter.new(
      STORE.pending_count,
      STORE.has_completed?,
      STORE.mode
    ))
  end
end

# Toggle all todos
post "/todos/toggle-all" do |env|
  env.datastar_stream do |sse|
    STORE.toggle_all

    # Update the UI
    sse.patch_elements(TodoList.new(STORE.filtered_todos))
    sse.patch_elements(TodoFooter.new(
      STORE.pending_count,
      STORE.has_completed?,
      STORE.mode
    ))
  end
end

# Delete a specific todo
delete "/todos/:id" do |env|
  id = env.params.url["id"]

  env.datastar_stream do |sse|
    STORE.remove(id)

    # Update the UI
    sse.patch_elements(TodoList.new(STORE.filtered_todos))
    sse.patch_elements(TodoFooter.new(
      STORE.pending_count,
      STORE.has_completed?,
      STORE.mode
    ))
  end
end

# Delete all completed todos
delete "/todos/completed" do |env|
  env.datastar_stream do |sse|
    STORE.remove_completed

    # Update the UI
    sse.patch_elements(TodoList.new(STORE.filtered_todos))
    sse.patch_elements(TodoFooter.new(
      STORE.pending_count,
      STORE.has_completed?,
      STORE.mode
    ))
  end
end

# Enter edit mode for a todo
get "/todos/:id/edit" do |env|
  id = env.params.url["id"]

  env.datastar_stream do |sse|
    if todo = STORE.todos.find { |t| t.id == id }
      sse.patch_elements(TodoItem.new(todo, editing: true))
    end
  end
end

# Cancel editing a todo
get "/todos/:id/cancel" do |env|
  id = env.params.url["id"]

  env.datastar_stream do |sse|
    if todo = STORE.todos.find { |t| t.id == id }
      sse.patch_elements(TodoItem.new(todo, editing: false))
    end
  end
end

# Update a todo's text
patch "/todos/:id" do |env|
  id = env.params.url["id"]

  env.datastar_stream do |sse|
    signals = sse.signals
    # Signal name is dynamic: edit{uuid without hyphens}
    signal_name = "edit#{id.gsub("-", "")}"
    new_text = signals[signal_name]?.try(&.as_s?) || ""

    if todo = STORE.todos.find { |t| t.id == id }
      unless new_text.empty?
        todo.text = new_text
      end
      sse.patch_elements(TodoItem.new(todo, editing: false))
      sse.patch_elements(TodoFooter.new(
        STORE.pending_count,
        STORE.has_completed?,
        STORE.mode
      ))
    end
  end
end

# Change filter mode
put "/mode/:mode" do |env|
  mode = env.params.url["mode"].to_i

  env.datastar_stream do |sse|
    STORE.set_mode(mode)

    # Update the UI
    sse.patch_elements(TodoList.new(STORE.filtered_todos))
    sse.patch_elements(TodoFooter.new(
      STORE.pending_count,
      STORE.has_completed?,
      STORE.mode
    ))
  end
end

# Reset to default todos
put "/reset" do |env|
  env.datastar_stream do |sse|
    STORE.reset_to_defaults

    # Update the UI
    sse.patch_elements(TodoList.new(STORE.filtered_todos))
    sse.patch_elements(TodoFooter.new(
      STORE.pending_count,
      STORE.has_completed?,
      STORE.mode
    ))
  end
end

Kemal.run

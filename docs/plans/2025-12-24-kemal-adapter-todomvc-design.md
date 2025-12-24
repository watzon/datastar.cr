# Kemal Adapter + TodoMVC Example Design

**Date:** 2025-12-24
**Status:** Approved

## Overview

Add a Kemal framework adapter for datastar.cr and implement the canonical TodoMVC example application without persistence.

## 1. Kemal Adapter Structure

Location: `src/datastar/adapters/kemal.cr`

```crystal
module Datastar::Kemal
  module Helpers
    # Start an SSE stream for real-time updates
    def datastar_stream(&block : ServerSentEventGenerator ->)
      response.content_type = "text/event-stream"
      response.headers["Cache-Control"] = "no-cache"
      response.headers["Connection"] = "keep-alive"

      sse = ServerSentEventGenerator.new(request, response)
      sse.start_streaming
      yield sse
      sse.finish
    end

    # Render HTML for Datastar (non-streaming)
    def datastar_render(renderable : Renderable) : String
      renderable.to_datastar_html
    end

    # Check if request is from Datastar client
    def datastar_request? : Bool
      Datastar.datastar_request?(request)
    end
  end
end

class HTTP::Server::Context
  include Datastar::Kemal::Helpers
end
```

## 2. TodoMVC Data Model

Location: `examples/kemal-todomvc/src/store.cr`

```crystal
enum FilterMode
  All       = 0
  Pending   = 1
  Completed = 2
end

struct Todo
  property id : String
  property text : String
  property completed : Bool

  def initialize(@text, @completed = false)
    @id = UUID.random.to_s
  end
end

class TodoStore
  property todos : Array(Todo)
  property mode : FilterMode

  def initialize
    @todos = [] of Todo
    @mode = FilterMode::All
    @mutex = Mutex.new
    reset_to_defaults
  end

  def add(text : String) : Todo
  def toggle(id : String) : Todo?
  def toggle_all : Nil
  def remove(id : String) : Nil
  def remove_completed : Nil
  def reset_to_defaults : Nil
  def set_mode(mode : FilterMode) : Nil

  def filtered_todos : Array(Todo)
  def pending_count : Int32
  def completed_count : Int32
  def all_completed? : Bool
end
```

## 3. Routes

Location: `examples/kemal-todomvc/src/app.cr`

| Method | Path | Purpose |
|--------|------|---------|
| `GET` | `/` | Serve main HTML page |
| `GET` | `/updates` | SSE stream - initial render |
| `PATCH` | `/todos` | Add new todo |
| `POST` | `/todos/:id/toggle` | Toggle single todo |
| `POST` | `/todos/toggle-all` | Toggle all todos |
| `DELETE` | `/todos/:id` | Delete single todo |
| `DELETE` | `/todos/completed` | Delete completed |
| `PUT` | `/mode/:mode` | Change filter mode |
| `PUT` | `/reset` | Reset to defaults |

## 4. Blueprint Components

Location: `examples/kemal-todomvc/src/components/`

### TodoPage
Full HTML page with Datastar setup:
- Includes Datastar CDN script
- Main section with `data-init="@get('/updates')"`
- Input with `data-signals-input` and `data-bind-input`
- Containers for todo list and footer

### TodoItem
Individual todo `<li>` element:
- Checkbox with `data-on-click="@post('/todos/:id/toggle')"`
- Text with conditional strikethrough
- Delete button with `data-on-click="@delete('/todos/:id')"`

### TodoList
Wrapper `<ul id="todo-list">` containing TodoItems

### TodoFooter
Footer with:
- Pending count display
- Filter buttons (All/Pending/Completed)
- Delete completed button

## 5. File Structure

```
src/datastar/adapters/kemal.cr

examples/kemal-todomvc/
├── shard.yml
├── src/
│   ├── app.cr
│   ├── store.cr
│   └── components/
│       ├── todo_page.cr
│       ├── todo_item.cr
│       ├── todo_list.cr
│       └── todo_footer.cr
```

## 6. Dependencies

```yaml
# examples/kemal-todomvc/shard.yml
dependencies:
  kemal:
    github: kemalcr/kemal
  datastar:
    path: ../..
  blueprint:
    github: gunbolt/blueprint
```

## 7. Key Interactions

1. **Page Load:** `data-init` triggers `GET /updates` → SSE patches todo list + footer
2. **Add Todo:** Enter key → `PATCH /todos` with `input` signal → SSE patches list + footer
3. **Toggle Todo:** Click checkbox → `POST /todos/:id/toggle` → SSE patches item + footer
4. **Delete Todo:** Click X → `DELETE /todos/:id` → SSE removes item + patches footer
5. **Filter:** Click filter button → `PUT /mode/:mode` → SSE patches entire list
6. **Toggle All:** Click toggle-all → `POST /todos/toggle-all` → SSE patches all items + footer

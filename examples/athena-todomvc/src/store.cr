require "uuid"

enum FilterMode
  All       = 0
  Pending   = 1
  Completed = 2
end

class Todo
  property id : String
  property text : String
  property completed : Bool

  def initialize(@text : String, @completed : Bool = false)
    @id = UUID.random.to_s
  end

  def toggle : Nil
    @completed = !@completed
  end
end

class TodoStore
  property todos : Array(Todo)
  property mode : FilterMode

  @mutex : Mutex

  def initialize
    @todos = [] of Todo
    @mode = FilterMode::All
    @mutex = Mutex.new
    reset_to_defaults
  end

  # Add a new todo
  def add(text : String) : Todo
    @mutex.synchronize do
      todo = Todo.new(text)
      @todos << todo
      todo
    end
  end

  # Toggle a specific todo's completion status
  def toggle(id : String) : Todo?
    @mutex.synchronize do
      if todo = @todos.find { |t| t.id == id }
        todo.toggle
        todo
      end
    end
  end

  # Toggle all todos
  def toggle_all : Nil
    @mutex.synchronize do
      # If all are completed, mark all incomplete. Otherwise, mark all complete.
      all_completed = @todos.all?(&.completed)
      @todos.each { |t| t.completed = !all_completed }
    end
  end

  # Remove a specific todo
  def remove(id : String) : Nil
    @mutex.synchronize do
      @todos.reject! { |t| t.id == id }
    end
  end

  # Remove all completed todos
  def remove_completed : Nil
    @mutex.synchronize do
      @todos.reject!(&.completed)
    end
  end

  # Reset to default todos
  def reset_to_defaults : Nil
    @mutex.synchronize do
      @todos.clear
      @todos << Todo.new("Learn any backend language", true)
      @todos << Todo.new("Learn Datastar")
      @todos << Todo.new("???")
      @todos << Todo.new("Profit")
    end
  end

  # Set the filter mode
  def set_mode(mode : FilterMode) : Nil
    @mutex.synchronize do
      @mode = mode
    end
  end

  # Set mode from integer
  def set_mode(mode : Int32) : Nil
    set_mode(FilterMode.from_value(mode))
  end

  # Get todos filtered by current mode
  def filtered_todos : Array(Todo)
    @mutex.synchronize do
      case @mode
      when FilterMode::Pending
        @todos.reject(&.completed)
      when FilterMode::Completed
        @todos.select(&.completed)
      else
        @todos.dup
      end
    end
  end

  # Count of pending (incomplete) todos
  def pending_count : Int32
    @mutex.synchronize do
      @todos.count { |t| !t.completed }
    end
  end

  # Count of completed todos
  def completed_count : Int32
    @mutex.synchronize do
      @todos.count(&.completed)
    end
  end

  # Check if all todos are completed
  def all_completed? : Bool
    @mutex.synchronize do
      @todos.all?(&.completed)
    end
  end

  # Check if there are any completed todos
  def has_completed? : Bool
    @mutex.synchronize do
      @todos.any?(&.completed)
    end
  end
end

DECLARE PROC printf NO CHECK;

CREATE PROC create_tasks_table ()
BEGIN
  CREATE TABLE tasks(
    id INTEGER PRIMARY KEY, -- AUTOINCREMENT doesn't work as expected
    title TEXT NOT NULL,
    description TEXT,
    is_done BOOL NOT NULL DEFAULT 0,
    created_at TEXT DEFAULT ''
  );
END;

CREATE PROC add_task (id INTEGER NOT NULL, title TEXT NOT NULL, description TEXT)
BEGIN
  INSERT INTO tasks using
    id as id,
    title as title,
    description as description,
    date('now') as created_at
  ;
END;

CREATE PROC get_all_tasks ()
BEGIN
  SELECT * FROM tasks ORDER BY created_at DESC;
END;

CREATE PROC update_task (
  id_ INTEGER NOT NULL,
  title_ TEXT,
  description_ TEXT,
  is_done_ BOOL
)
BEGIN
  UPDATE tasks
  SET
    title = COALESCE(title_, title),
    description = COALESCE(description_, description),
    is_done = COALESCE(is_done_, is_done)
  WHERE id = id_;
END;

CREATE PROC delete_task (id_ INTEGER NOT NULL)
BEGIN
  DELETE FROM tasks WHERE id = id_;
END;

CREATE PROC print_tasks()
BEGIN
  DECLARE C CURSOR FOR CALL get_all_tasks();
  LOOP FETCH C
  BEGIN
    CALL printf(
      "ID: %d Completed: %d Created At: %s \tTitle: %s\tDescription: %s\n",
      C.id, C.is_done, C.created_at, C.title, C.description
    );
  END;

  CALL printf("\n\n");
END;

CREATE PROC entrypoint()
BEGIN
  CALL create_tasks_table();

  CALL add_task(1, 'Buy groceries', 'Milk, Eggs, Bread');
  CALL add_task(2, 'Call John', 'Discuss the project details');

  CALL printf("Initial Tasks:\n");
  CALL print_tasks();

  CALL printf("Updating Task 1.\n");
  CALL update_task(1, NULL, NULL, 1);

  CALL printf("Tasks After Update:\n");
  CALL print_tasks();

  CALL printf("Updating Task 2\n");
  CALL update_task(2, "Call John Doe", NULL, 0);

  CALL printf("Tasks After Update:\n");
  CALL print_tasks();

  CALL printf("Deleting Task 2.\n");
  CALL delete_task(2);

  CALL printf("Tasks After Deletion:\n");
  CALL print_tasks();
END;

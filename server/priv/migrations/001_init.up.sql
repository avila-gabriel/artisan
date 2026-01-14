CREATE TABLE sales_intake (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT NOT NULL,
  supplier TEXT NOT NULL,
  created_at REAL NOT NULL
);

CREATE TABLE sales_intake_product (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  sales_intake_id INTEGER NOT NULL,
  nome TEXT NOT NULL,
  ambiente TEXT NOT NULL,
  quantidade INTEGER NOT NULL,
  FOREIGN KEY (sales_intake_id)
    REFERENCES sales_intake(id)
    ON DELETE CASCADE
);


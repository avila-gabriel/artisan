CREATE TABLE sales_intakes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT NOT NULL,
  supplier TEXT NOT NULL,
  created_at REAL NOT NULL
);

CREATE TABLE sales_intake_products (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  sales_intake_id INTEGER NOT NULL,
  nome TEXT NOT NULL,
  ambiente TEXT NOT NULL,
  quantidade INTEGER NOT NULL,
  FOREIGN KEY (sales_intake_id)
    REFERENCES sales_intakes(id)
    ON DELETE CASCADE
);


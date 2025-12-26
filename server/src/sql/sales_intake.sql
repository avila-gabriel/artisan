-- name: CreateSalesIntake :one
INSERT INTO sales_intakes (
  username,
  supplier,
  created_at
) VALUES (
  ?, ?, ?
)
RETURNING id;

-- name: AddSalesIntakeProduct :exec
INSERT INTO sales_intake_products (
  sales_intake_id,
  nome,
  ambiente,
  quantidade
) VALUES (
  ?, ?, ?, ?
);


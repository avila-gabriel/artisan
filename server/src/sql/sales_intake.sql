-- name: CreateSalesIntake :one
INSERT INTO sales_intake (
  username,
  supplier,
  created_at
) VALUES (
  ?, ?, ?
)
RETURNING id;

-- name: AddSalesIntakeProduct :exec
INSERT INTO sales_intake_product (
  sales_intake_id,
  nome,
  ambiente,
  quantidade
) VALUES (
  ?, ?, ?, ?
);


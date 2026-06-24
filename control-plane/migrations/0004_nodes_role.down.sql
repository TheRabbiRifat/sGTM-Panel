-- Reverse 0004_nodes_role: restore is_edge BOOLEAN, drop role column.
DROP INDEX IF EXISTS idx_nodes_role;

ALTER TABLE nodes
  ADD COLUMN is_edge BOOLEAN NOT NULL DEFAULT TRUE;

ALTER TABLE nodes DROP COLUMN role;

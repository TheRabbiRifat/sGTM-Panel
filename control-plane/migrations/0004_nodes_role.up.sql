-- ───────────────────────────────────────────────
-- Nodes: rename is_edge (BOOLEAN) → role (TEXT)
-- Every node is a "master" node; no slave/non-edge role exists.
-- ───────────────────────────────────────────────
ALTER TABLE nodes
  ADD COLUMN role TEXT NOT NULL DEFAULT 'master'
    CHECK (role IN ('master'));

-- Backfill: previous is_edge=FALSE rows would have been non-edge; under the
-- new model every node is master, so we collapse them all to 'master'.
UPDATE nodes SET role = 'master' WHERE role IS NULL;

-- Drop the now-redundant boolean column.
ALTER TABLE nodes DROP COLUMN is_edge;

-- Helpful index for the common "list master nodes" lookup.
CREATE INDEX idx_nodes_role ON nodes(role);

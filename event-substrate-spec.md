# Threehorse: Event Substrate Specification

## Context

This spec describes an event-sourced data substrate for business process applications, developed as a practical implementation of the Formfold theory (see `formfold-theory.md` for the full theoretical framework). The first test case is the Northwind database — a sample business application with orders, customers, products, employees, shipping, and purchasing.

## Core Principle

There are no tables for business entities. No orders table, no customers table, no products table. There is one table: **events**. Every business entity is a **nexus** — a creation event that other events accrete around. The current state of any entity is computed by reading all events that reference its nexus, never stored as mutable state.

## The Events Table

```sql
CREATE TABLE events (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nexus       UUID REFERENCES events(id),  -- the creation event this accretes around
    flow        TEXT NOT NULL,                -- e.g. 'order', 'shipping', 'customer', 'payment', 'lineitem'
    field       TEXT NOT NULL,                -- e.g. 'created', 'shipperid', 'quantity', 'cancelled'
    value       JSONB,                        -- the fact: number, string, boolean, null, or compound
    at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    by          UUID,                         -- who created this event (itself a nexus reference)
    origin      TEXT                          -- system/node origin for distributed contexts
);

CREATE INDEX idx_events_nexus ON events(nexus, flow, at);
CREATE INDEX idx_events_flow ON events(flow, field);
CREATE INDEX idx_events_at ON events(at);
CREATE INDEX idx_events_value ON events USING GIN (value);
```

## How Entities Work

### Creating an entity (a nexus)

An order, customer, product, employee — any business entity — is created by inserting an event with `nexus: NULL` and `field: 'created'`. This event's `id` becomes the nexus UUID that all subsequent events reference.

```sql
-- Create an order
INSERT INTO events (id, nexus, flow, field, value) VALUES
    ('a1b2...', NULL, 'order', 'created', 'true');
```

The `id` of this event (`a1b2...`) is now the structural identity of this order. It is not a human-readable order number — that comes later as just another event.

### Accreting facts around a nexus

Every piece of information about the entity is a separate event pointing back to the nexus:

```sql
-- These all reference nexus 'a1b2...' (the order creation event)
INSERT INTO events (nexus, flow, field, value) VALUES
    ('a1b2...', 'order',    'ordernumber',   '1001'),
    ('a1b2...', 'customer', 'customerid',    '"x7y8..."'),   -- UUID of customer nexus
    ('a1b2...', 'employee', 'employeeid',    '"m3n4..."'),   -- UUID of employee nexus
    ('a1b2...', 'employee', 'notes',         '"Rush order, handle with care"'),
    ('a1b2...', 'shipping', 'shipperid',     '"p5q6..."'),   -- UUID of shipper nexus
    ('a1b2...', 'shipping', 'shippingfee',   '25.00'),
    ('a1b2...', 'payment',  'paymentmethod', '"Check"'),
    ('a1b2...', 'payment',  'taxrate',       '0.08');
```

### Updating a field

There is no UPDATE. A changed field is a new event with a later timestamp:

```sql
-- Shipper changed from p5q6... to r7s8...
INSERT INTO events (nexus, flow, field, value) VALUES
    ('a1b2...', 'shipping', 'shipperid', '"r7s8..."');
```

The old event stays. The current value is always the latest event for that nexus+flow+field combination.

### Computing current state

The current state of any nexus is derived, never stored:

```sql
SELECT DISTINCT ON (flow, field)
    flow, field, value, at, by
FROM events
WHERE nexus = 'a1b2...'
ORDER BY flow, field, at DESC;
```

### Sub-nexuses (e.g. line items)

A line item is its own creation event, linked to the order nexus:

```sql
-- Create a line item (its own nexus, linked to the order)
INSERT INTO events (id, nexus, flow, field, value) VALUES
    ('j1k2...', 'a1b2...', 'lineitem', 'created', 'true');

-- Facts accreting around the line item nexus
INSERT INTO events (nexus, flow, field, value) VALUES
    ('j1k2...', 'lineitem', 'productid', '"w3x4..."'),   -- UUID of product nexus
    ('j1k2...', 'lineitem', 'quantity',  '5'),
    ('j1k2...', 'lineitem', 'unitprice', '18.50'),
    ('j1k2...', 'lineitem', 'status',    '"allocated"');
```

The line item nexus `j1k2...` points to order nexus `a1b2...`. The hierarchy is events pointing to events.

### Resolution events (workflow transitions)

Status changes, approvals, cancellations — these are just events. They are structurally identical to a field update, but they represent bifurcation points in the trajectory:

```sql
INSERT INTO events (nexus, flow, field, value) VALUES
    ('a1b2...', 'order', 'invoiced',  'true'),    -- at time T1
    ('a1b2...', 'order', 'shipped',   'true'),    -- at time T2
    ('a1b2...', 'order', 'paid',      'true'),    -- at time T3
    ('a1b2...', 'order', 'closed',    'true');     -- at time T4

-- Or, alternatively:
    ('a1b2...', 'order', 'cancelled', 'true');     -- different trajectory
```

### Cross-nexus references

When a value is itself a nexus UUID, that's a link in the topology. The customer assigned to an order is a UUID pointing to the customer's creation event. The product on a line item is a UUID pointing to the product's creation event. FKs are nexus-to-nexus references.

This means a customer, a product, an employee — all are created the same way:

```sql
-- Create a customer
INSERT INTO events (id, nexus, flow, field, value) VALUES
    ('x7y8...', NULL, 'customer', 'created', 'true');

INSERT INTO events (nexus, flow, field, value) VALUES
    ('x7y8...', 'customer', 'companyname', '"Acme Corp"'),
    ('x7y8...', 'customer', 'phone',       '"555-1234"'),
    ('x7y8...', 'customer', 'city',        '"Portland"');
```

The schema does not know the difference between a customer and an order. Both are nexuses with events.

## Key Design Properties

### Immutability
No row is ever updated or deleted. Facts accrete. The current state is always computed, never stored. Corrections are new events. Cancellations are new events.

### UUIDs everywhere
Every event has a UUID. Every nexus reference is a UUID. No integer sequences. Any node in a distributed system can create nexuses independently without coordination. Sync between systems is append-only merge — push events the other node doesn't have. No conflict resolution needed at the write level.

### One table
The schema does not encode business domain knowledge. It does not know what an order is, what flows an order has, or what fields a shipping flow contains. All of that is in the data. This means:
- New entity types require no schema changes
- New flows require no schema changes
- New fields require no schema changes
- The system evolves entirely through the events it records

### Trace is structural
Every event has `at` (when), `by` (who), and `origin` (where). The full history of every entity is preserved — not in a separate audit log, but as the primary data. The audit trail and the data are the same thing.

### Computed values
Values that derive from multiple flows (e.g. order total = sum of line item subtotals + tax + shipping) are never stored. They are computed at query time by reading across flows. These cross-flow computations are **transductions** — information crossing between contexts.

## Flows Identified in Northwind

Starting from the Access order form, these flows converge at the order nexus:

| Flow | Fields | Description |
|------|--------|-------------|
| order | created, ordernumber, orderdate, invoiced, shipped, paid, closed, cancelled | The nexus lifecycle |
| customer | customerid | Links to customer nexus |
| employee | employeeid, notes | Who handles the order and adds context |
| shipping | shippeddate, shipperid, shippingfee | The logistics flow |
| payment | paymentmethod, paiddate, taxrate, taxstatusid | The financial flow |
| lineitem | (sub-nexus) created, productid, quantity, unitprice, discount, status | Each line item is its own nexus |

Other entity types in Northwind follow the same pattern:
- **Customer** nexus: companyname, phone, address, city, etc.
- **Product** nexus: productname, unitprice, category, discontinued, etc.
- **Employee** nexus: firstname, lastname, jobtitle, supervisor (nexus ref), etc.
- **Purchase Order** nexus: vendorid, submittedby, approvedby, status events, line items as sub-nexuses

## Relationship to Formfold Theory

This implementation maps directly to the Formfold theoretical framework:

- **Agencement model**: Entities are nexuses — convergences of flows, not records. The implementation makes this literal.
- **Five primitives**: Boundary (flow labels), Transduction (cross-nexus references and computed values), Resolution (workflow events), Trace (every event has at/by/origin), Reflection (LLM layer reads the event substrate — not yet implemented).
- **Attractor basins**: Full trajectories are preserved. You can cluster historical event sequences by outcome to empirically identify basin patterns.
- **Event discipline**: Solved structurally — there is no write path that bypasses events.
- **Substrate/Reflection separation**: The events table is the immutable substrate. LLM Reflection reads it and appends interpretation events subject to the same governance.
- **Pacioli's ledger restored**: Financial and operational events share the same table and mechanics. No reconciliation needed.
- **Distributed operation**: UUIDs enable independent nexus creation. Sync is append-only merge.

## Open Questions

1. **Current state materialization**: Computing current state from events on every read may not scale. Materialized views, snapshot caching, or CQRS-style read models may be needed. The theory calls this "resolution as stability parameter" — how to expose the right level of detail without drowning in event noise.

2. **Governance**: The `by` field seeds governance, but role-based access, approval requirements, and separation of duties need to be modeled as events themselves — governance facts in the same substrate as operational facts.

3. **The fold UI**: The substrate is ready for a topological navigator (unfold from any nexus, explore edges, collapse for context). Not yet built.

4. **Saved collections**: Navigational stances — which nexuses to foreground, which flows to expand — stored as configurations that capture how a role thinks about a problem.

5. **LLM Reflection**: Positioning an LLM within the topology to read event trajectories, identify patterns, surface anomalies, and propose navigational stances.

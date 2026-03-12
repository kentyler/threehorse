# Threehorse

Threehorse is a fresh rebuild centered on a simpler canonical model:

- `databases` are containers
- `objects` are the first-class units
- `object_edges` capture lineage and semantic relationships
- `skills` describe import and transformation competencies

This repo starts from the data model first so import, editing, reasoning, and
runtime behavior can layer on top of a stable substrate.

## Core Principle

Threehorse should be structured for maximum traction from an LLM, not maximum
convenience for a human maintainer.

That means we prefer:

- complete, self-contained object layers over patch-only representations
- explicit lineage over implicit mutation
- consistent object shapes over object-type-specific special cases
- durable provenance and change summaries over undocumented transformations
- code and data layouts that make it easier for an LLM to inspect, compare,
  and reason across the whole system

Human readability still matters, but it is secondary to building a substrate
that future LLMs can understand, trace, and transform safely.

## Current Scope

The initial foundation is intentionally small:

- a dedicated PostgreSQL database named `threehorse`
- a `shared` schema
- core tables for containers, raw discovery, objects, edges, and skills
- seed data that describes the shared substrate inside the substrate itself
- an install script that can create the database and apply all SQL files

## Design Direction

The system is meant to support both:

- imported applications
- applications created natively from scratch

Every first-class object belongs to exactly one database container, while LLM
reasoning may span objects across all containers.

Each stage/layer should be stored as a complete object in its own right, with
explicit parent linkage and concise change metadata. Full diffs are optional
and can be added later if they materially improve LLM reasoning.

## Current Foundation

The base schema currently defines:

- `shared.databases`
- `shared.source_discovery`
- `shared.objects`
- `shared.object_edges`
- `shared.skills`
- `shared.current_objects` (view)

It also seeds a system container, `threehorse_system`, with object records that
represent the base shared tables and view. This makes the substrate partially
self-describing from the beginning.

The near-term import plan is:

1. register databases
2. store raw discovery for all imported Access objects
3. import all objects into `shared.objects`
4. create runtime tables/views in database-specific schemas as a later step

## Install

Run:

```powershell
.\install.ps1
```

This will:

1. create the `threehorse` PostgreSQL database if it does not already exist
2. apply all `.sql` files in the `sql` folder in name order

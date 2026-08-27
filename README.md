# tsfy27 — Volta Industrial (Tech Summit FY27 Build Challenge)

Workspace for the Tech Summit FY27 AI Customer Challenge: Volta Industrial downtime & maintenance rescue.

---

First prompt used in Genie Code: 

> "make project memory that states the volta-industrial-origin... is the original bundle from the Tech Summit FY27 build challenge, and that it should not be touched.  it should be used as a reference, especially any of the readme files that contain the requirements for getting a full score on the builld.   volta-industrial is where we will work and the files here are where any edits should be made.   docs are the design docs I created based on the customer's requirements and the understanding of the current setup from a white boarding session.  we're about to begin the work on this repo and want to ensure two things:
> 
> 1.  we want to incorporate any of the best practices from the design while also adding in any details we can learn now from the files in @volta-industrial-original and then create new set of design documents for us follow in a subfolder next to @docs 
> 2.  run any set up that is required in the @volta-industrial bundle so that we can get the additional context of the data model, etc.  
> 
> invetigate everything and let me know what our plan should be to execute on this first part of the work and any open questions you have before we start.   also update the readme with the details listed here."

## Folder Layout

| Folder | Purpose | Editable |
|--------|---------|----------|
| `volta-industrial-original/` | Original challenge bundle (frozen reference) | NO |
| `volta-industrial/` | Working bundle — all edits and deployments here | YES |
| `docs/genie-one-design/` | Design documents (L100–L400) from customer requirements + whiteboarding | Reference |
| `docs/build-specs/` | Consolidated build specs (to be created from design + original specs) | YES |

---

## Key Rules

- **Do not modify** `volta-industrial-original/`. It is the pristine challenge template and contains the grading rubric in its README and `specifications/` folder.
- All implementation work happens in `volta-industrial/`.
- `docs/genie-one-design/` contains the architecture vision and detailed designs created from the customer's requirements and whiteboarding session.
- `docs/build-specs/` will contain a new set of consolidated build documents that merge the best practices from the design docs with the specific requirements from the original bundle's specifications.

---

## Getting Started

1. Read `PROJECT_MEMORY.md` for full project context
2. Deploy the bundle: `cd volta-industrial && databricks bundle deploy`
3. Generate data: `databricks bundle run volta_setup`
4. Build the four milestones (Data, Lakebase, App, AI Gateway)

---

## Milestones

1. **Data** — SDP pipeline + metric view + dashboard + Genie space
2. **Lakebase** — Synced gold tables + writable app table + search
3. **Databricks App** — Visualize / Assist / Act with human-in-the-loop
4. **Unity AI Gateway** — Governed, capped, traceable AI spend
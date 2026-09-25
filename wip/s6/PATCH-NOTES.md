# S6 integration notes

Reviewed the live App Review Guidelines on 2026-09-25. Apple's page identified June 8, 2026 as its last update. The Introduction, Before You Submit, and After You Submit sections were compared against the private requirement catalog; source prose was not copied into the public section file.

`skills/appstore-precheck/references/obligations/intro.json` classifies every catalog fragment in these sections and retains the scaffold IDs, source hashes, and anchors. Source fragments that restate a canonical atom are informational aliases with `related` links. This avoids counting the same testing, metadata, contact, demo account, demo-mode parity, and backend duty twice. `atom-8ec7a1f236414c65a4604e3c7e1fe1bb` is treated as a non-testable pointer to external guidance; `atom-cceffef53c7640dc8158f299f656ff99` is platform capability context.

The following obligation IDs have intentionally empty `routes`. No check implementation is claimed by this section worker. Proposed target and gap IDs for Wave 2:

| Gap | Obligation IDs | Proposed target |
| --- | --- | --- |
| S6-GAP-01 | `atom-aa8284569e164afb823d07720c3ca324`, `atom-7660b11f2dad457fbefdac9a83a74d99` | Runtime service/function checks plus maintenance attestation; check existing 5.6.4 and 2.1 mappings. |
| S6-GAP-02 | `atom-c44cce19b9104b2ca5f658e0dd2a93a5` | Semantic review of accessible child and teen experiences; age rating alone cannot decide. |
| S6-GAP-03 | `atom-a386ca273c58478cb0f5608babab9a81`, `atom-240f52a443aa466f840ab6ee91f0811d` | Semantic content/quality assessment with runtime evidence. |
| S6-GAP-04 | `atom-f7d015611dde4efda35fcf052340c2f6` | Attestation with supporting records, plus semantic review where deceptive conduct is observable. Intent cannot be inferred from a keyword hit. |
| S6-GAP-05 | `atom-f65a3e371c2c49229e0449753fef6859` | Artifact dependency inventory plus developer attestation of vendor assessment. |
| S6-GAP-06 | `atom-884097dadb564c018667d7c730d75f61` | Runtime review-access exercise and attestation for inaccessible gates. |
| S6-GAP-07 | `atom-e7ac52bbed6742cea1216b232bf01b1a` | Metadata/ASC review-note inspection and attestation of hardware or sample resources. |
| S6-GAP-08 | `atom-f9a98fc9b0544658a3b9a4b0152a160e`, `atom-89ba978493b44f34a8ed0f9e9d4b9bb1` | Metadata/ASC review-note inspection, with semantic sufficiency assessment. |
| S6-GAP-09 | `atom-a9c3f3d5e7344174860729bd57ddfa21` | Conditional attestation about expedite requests. This is developer process conduct, not app behavior. |
| S6-GAP-10 | `atom-fb4cb3107c0940c49cb5b9268e624813` | Conditional attestation about the App Store Connect communication when the bug-fix review path is requested. |

The checklist source aliases link to canonical atoms from other sections. Coordinate with S2/S5 before registry merging: testing `atom-3c95a205dfc5469d86927977e0e7c636`, metadata completeness `atom-da5c1a8b088e415799ddc357c2f628fa`, metadata accuracy `atom-edd8489e47804bd6abc3972fd96b18f0`, developer contact currency `atom-21008b99be694b86ac628de503f46e07`, demo credentials `atom-e575151c903d4c8fb72cede56c55c136`, demo parity `atom-98d454c351724f8b83bd56473cb39b85`, and backend availability `atom-b2f36389d4ea4b93a7c399473abdefba`.

Review outcome caveat: when the backend is unavailable, demo credential testing lacks a valid basis. Report `INSUFFICIENT` or `NEEDS_REVIEW` for demo credentials and investigate backend availability as the primary issue. Do not emit a demo credential `FINDING` solely from the unavailable backend.

Run `APPSTORE_PRECHECK_PRIVATE_CATALOG=/Users/bt/claude/appstore-precheck/.planning/opus-work/skills/appstore-precheck/references/requirement-catalog.json bash tests/test-obligations-intro.sh` locally. Without the private catalog, the overlap check skips; the public structure checks still run.

# Independent source review: Section 2

Reviewed the 2026-09-26 live [Apple App Review Guidelines, Section 2](https://developer.apple.com/app-store/review/guidelines/#2) against the private source inventory and `references/obligations/2.json`. All 125 private Section 2 source fragments have a public record by persistent ID. The public section contains 141 obligation atoms. The findings below concern meaning and traceability, not missing source fragments. No Apple source text is reproduced here.

## Findings

1. **2.1(a), demo access exception loses its conditions.** `req-cfecb4c630e6425fb0e66478a005c2cd` has a generic criterion, so its linked credential duty `atom-e575151c903d4c8fb72cede56c55c136` cannot distinguish an ordinary demo mode from the narrow alternative. State explicitly that inability to provide a demo account must arise from legal or security obligations, that Apple approval is prior, and that the mode must expose full functionality. The separate full-feature atom `atom-98d454c351724f8b83bd56473cb39b85` already covers the last condition; link it to the exception as well. Otherwise an attestation or runtime route could treat an unapproved partial demo as sufficient.

2. **2.1(a), on-device test atom adds a mandatory record.** `atom-3c95a205dfc5469d86927977e0e7c636` makes recording defects and fixes part of the decision criterion. The source requires pre-submission testing on device for bugs and stability, but does not require a written defect log. Keep a record as suggested evidence, not a pass condition, to avoid an unsupported failure.

3. **2.3.10, exception is narrower than the restriction it qualifies.** `atom-b2b4076815824dc6a628c8d0d352c64d` mentions only other-platform imagery; `atom-9db9677a29c5465aac9b166f78fe5950` also covers names and icons in the app or metadata. Extend the approved interactive-function exception to the entire restricted class, with the same approval condition. Otherwise a justified name or icon may be flagged despite the source exception.

4. **2.4.1, iPad feasibility exception invents a documentation condition.** `atom-b05afb92394740e4ac5d57768caf349b` describes a *documented* platform or feature limitation. The source qualifies iPad support by feasibility, but does not mandate documentation. Ask for evidence when feasibility is disputed without encoding the presence of a document as a policy prerequisite.

5. **2.5.1, HealthKit atom weakens one stated expectation.** `atom-0162f240996e46ff9c4167f88c7efaa2` makes Health app integration conditional on an undefined “where required.” The source gives HealthKit integration with the Health app as its example of intended API use without that extra condition. Remove the added qualifier; keep the atom applicable only when HealthKit is used.

6. **2.5.2, educational code exception adds a source restriction.** `atom-a794bf1568084157961eca5a24a2fc49` limits the downloaded code to *user-provided* code. The source allows qualifying educational coding apps to download code in limited circumstances, provided the code is confined to that educational purpose and the app makes its supplied source viewable and editable. Preserve those limits, but remove the unsupported origin restriction. Also reassess `atom-770691ed891c49268f287bc54203bac2`: its unspecified “permitted exception” to the container rule is not identified in this guideline and could silently weaken the duty.

7. **2.4.5(vii), source-to-atom trace is incomplete.** `req-64c0bfff78f54602a90869b702ebe02d` carries the prohibition on alternative Mac App Store update mechanisms but has no `related` link. Link it to `atom-5dae75e9eb9d47baba6e8af50f85422b`, whose criterion already captures the exclusive store-update rule. This avoids treating a binding source fragment as context without an operative target.

The 115 currently empty obligation routes are implementation gaps already recorded by S2, rather than source classification findings. Existing partial routes remain partial and should not imply a complete Section 2 verdict.

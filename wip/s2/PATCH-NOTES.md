# S2 integration notes

Apple source reviewed against the [live Performance section](https://developer.apple.com/app-store/review/guidelines/#2) on 2026-09-25. The June 8, 2026 private snapshot and live 2.x headings, duties, and exception themes showed no apparent material drift. This is a manual comparison, not a byte-identical page hash. No source prose is included here.

`skills/appstore-precheck/references/obligations/2.json` replaces all 2.x skeleton entries by persistent ID. It preserves source hashes and anchors; all carried check links are `partial`. The accepted 2.1(a) atoms were paraphrased for the public catalog. A formerly informational enforcement fragment in 2.1(a) is an obligation because a shipped crash or incomplete package is an app condition; `dyn-launch` and `dyn-first-screen` are partial evidence.

## Gaps requiring Dalga 2 routes

These 115 obligations currently have no implemented route. IDs are exact integration targets. Proposed routes are implementation requests, not registry entries. Do not insert a `check_id` until its check and fixture exist.

| Apple ref | Proposed route work | Unrouted obligation IDs |
|---|---|---|
| 2.1(a) | runtime + metadata + attestation (real-device test and backend availability need attested evidence) | `atom-bcc5e1c47ad942c992deac8363bd0d78`, `atom-022f8d501aee473fb3feecfeeba4cf71`, `atom-da5c1a8b088e415799ddc357c2f628fa`, `atom-3c95a205dfc5469d86927977e0e7c636`, `atom-b2f36389d4ea4b93a7c399473abdefba`, `atom-98d454c351724f8b83bd56473cb39b85` |
| 2.1(b) | metadata (ASC purchase inventory) + runtime + attestation | `atom-480ab89df4f34502a50e8fdd6485c2f5`, `atom-f1ad5ba672064b06a7999013a7f9e60a`, `atom-2e86ab0ea8624da08e7a081a50b90ce3`, `atom-26cf6458c05541869843bb236e088a76` |
| 2.2 | metadata (distribution/TestFlight records) + attestation | `atom-537a0112fd81465ea93e66802fd79534`, `atom-f25230e8a6004edbb77c8f422de49d65`, `atom-a4d2b77d8ff942679010f433dc9e19bc`, `atom-fc833c57c3024ec29ca3b1c81fbc7043` |
| 2.3.1(a) | metadata (review notes) + semantic/runtime for shipped feature access | `atom-1e5da57b9b5f418cbfed204ac0698f62`, `atom-d79c71f22baa4b1d85f84e1fdbd8f89c`, `atom-2471c65fff8442c8942b9c746975c731` |
| 2.3.2 | metadata (promoted IAP) + semantic/runtime purchase journey | `atom-26707ff0c3f04fc48c8d9cba22adb583`, `atom-bc52f44a1c904218b6c8e56f18b2e65e`, `atom-8686be1b06dc40a2b8db1920306fde4f` |
| 2.3.4 | semantic video review; existing preview-consistency checks parity, not capture origin | `atom-b4d5eed51a6245dda00826ef43148049` |
| 2.3.6 | metadata (age-rating answers) + semantic + territorial attestation | `atom-504a8494ddbe4fe4bca64d5d7dab9177`, `atom-789bdc933c474241b69f852f5dfd81b5` |
| 2.3.7 | metadata + semantic for name/keyword/subtitle meaning | `atom-4ce5277e9ca64bacb43032a88e36ddc9`, `atom-fad9dada6bdd482990b4f2871db577d9`, `atom-97aa60928d3a40e6b8d023bd16fc61ac`, `atom-5deb3f638fd544fe8571f44736f90bad` |
| 2.3.8 | semantic image review + metadata category check | `atom-f2aabf7980e5450f9be01a60557d7cc3`, `atom-4a55247181204104965cdfaaaf78b188` |
| 2.3.9 | attestation (rights provenance) + semantic visual PII review | `atom-c568f26de7444ff59dfb492fdb9ce4d5`, `atom-4a04e741bb5e4b0d8b5aa0d9bdc1b6e7` |
| 2.3.10 | semantic app/listing review + approved-function attestation | `atom-74fbb357ec7248f4a6579b70b3f80d36`, `atom-a0fad48dc2f14f018fbfdbb018e703f6` |
| 2.3.11 | metadata (pre-order history) + semantic/runtime + attestation | `atom-142947eaa09c4b0ba55d784fbf6b99ff`, `atom-8b806a7555a54445b3fb528d0eb014b5`, `atom-6b3f135b76954fd9a8022fd23d402a53` |
| 2.3.12 | metadata release-note review + semantic change comparison | `atom-9c2c65e3051541c291b4eea66e0d5a86` |
| 2.3.13 | metadata (ASC events) + runtime deep-link check + attestation for actual schedule | `atom-0cf07fdf80a54ce6802790b6716b9232`, `atom-a4355e306bbd460bbcb25366cc997f93`, `atom-c0857e55558348dcb1ee87d6ae8c3897`, `atom-3eda34046051401f8a2cd172d453d8ef`, `atom-bb3b8be7c0924b608600a9158f361304` |
| 2.4.2 | attestation (device power/thermal measurements) + runtime where hardware is available | `atom-f1f851ad4e0341298c3cb4f4fd0f4d9a`, `atom-bdd79b9987db49eba42feb75a1a013b7`, `atom-f77576632ab3416089355b49e027d4ee`, `atom-b0faf1f2127d48639d20ad867a729be5`, `atom-cbc112473b68450288dfed343e8cd591`, `atom-67ab76073de04afd9a7f8e1867942296` |
| 2.4.3 | runtime tvOS controller test + metadata; current iOS simulator scope requires attestation gap | `atom-26be828bac124f4d84cd54e1067f6b12`, `atom-a0cb0b0c8341445c8601fde841dd5719` |
| 2.4.4 | semantic copy review + runtime prompt observation | `atom-65f90c54bb344871b76e99b86bf89ee6`, `atom-68a2c49a54074ee9b46ac9b510dc3027` |
| 2.4.5(i) | artifact/macOS package inspection + attestation; Mac targets currently platform-not-audited | `atom-0e8825a62d2b413fb5268095982b68e5`, `atom-6c722ce67613460fb35b0736aa297d11`, `atom-0c7f47dbb9384e1f80d0b3039773cd38` |
| 2.4.5(ii) | artifact/macOS package inspection + attestation; Mac targets currently platform-not-audited | `atom-fe36028e269244cf841654a0f5b9dca5`, `atom-87dee9a6a6c84c6b8ab6a08c35299e12`, `atom-775011efd03340c2b097e71667c95bb9`, `atom-0533fe9c07884058a6de6911c7649e32` |
| 2.4.5(iii) | artifact/macOS package inspection + attestation; Mac targets currently platform-not-audited | `atom-5d94c888569a49a0a24af0eb863a479c`, `atom-27e0dd6085d343b2b6e697322eb3688f`, `atom-a7de176aa7db4bce89b78db9fda4c246`, `atom-4093d96d0c33494293c02b33a8ae320d` |
| 2.4.5(iv) | artifact/macOS package inspection + attestation; Mac targets currently platform-not-audited | `atom-503911f138af48b48a3d6b3e7a15a2ff`, `atom-fd73c4026bbc402093fda4a7d8ba49b0` |
| 2.4.5(v) | artifact/macOS package inspection + attestation; Mac targets currently platform-not-audited | `atom-a634a4f88f774f699988397e4335f909`, `atom-693301486c0b44ffaf94f2e557644f8b` |
| 2.4.5(vi) | artifact/macOS package inspection + attestation; Mac targets currently platform-not-audited | `atom-f0aac438b6fb456fb7bddb238a98bdf9`, `atom-9b0838b9b8ac472b956321fe66848797`, `atom-7818702d8b2e42bfb1bcf7f60edadfef` |
| 2.4.5(vii) | artifact/macOS package inspection + attestation; Mac targets currently platform-not-audited | `atom-5dae75e9eb9d47baba6e8af50f85422b` |
| 2.4.5(viii) | artifact/macOS package inspection + attestation; Mac targets currently platform-not-audited | `atom-131b2d1e33bb42989dbfe5c3b2c10266`, `atom-133bd645375c4195adbc41e7e3b4bfb9` |
| 2.4.5(ix) | artifact/macOS package inspection + attestation; Mac targets currently platform-not-audited | `atom-3005822c01fa4ef9bfe3e295e9f7abdd` |
| 2.5.1 | artifact symbol/framework inspection + runtime OS compatibility + semantic integration review | `atom-ee93e56edba3419f84ac316b0da1f8f8`, `atom-d93aa7a8e4c743debc0e2b1119d49946`, `atom-83a80f632b4140a9b43c37e9da73037f` |
| 2.5.2 | artifact code/container inspection + runtime behavior + attestation for educational exception | `atom-710fe555195141d28464263c1bb7f725`, `atom-770691ed891c49268f287bc54203bac2`, `atom-6d19e409a4c44687a04b3e6bf3eefc3d` |
| 2.5.3 | artifact security scan + attestation for behavior outside observable run | `atom-a92e61f23c06461fa08971d3f8bdb5da` |
| 2.5.6 | artifact framework/entitlement check + runtime browser behavior | `atom-1540dc9f7e9449ff9a508b3253ad84ba` |
| 2.5.8 | runtime/semantic UI inspection | `atom-ed0dec3e64734a49b0ce3f98d5188b19` |
| 2.5.9 | runtime control and outbound-link behavior | `atom-d5c354dc0a26495bb9f5da025c615b86` |
| 2.5.11(i) | artifact symbol/framework inspection + runtime OS compatibility + semantic integration review | `atom-1b18e840083244aead0be31b487c7058`, `atom-844b8364da344feabffbdb41fc841e79` |
| 2.5.11(ii) | artifact symbol/framework inspection + runtime OS compatibility + semantic integration review | `atom-32dcc77ad20a42ff84c4f86151911a09`, `atom-4ff5050a2d494957b136db0682d6a522`, `atom-745ad7b1034b49d790675c8733b82467` |
| 2.5.11(iii) | artifact symbol/framework inspection + runtime OS compatibility + semantic integration review | `atom-3b10c9fb693c475aaf1aa36a561fa56b`, `atom-878565a246224f57bb78cde7986fe187`, `atom-e2bb5dc03b2d4c72a0600c5beaa0f974` |
| 2.5.12 | artifact symbol/framework inspection + runtime OS compatibility + semantic integration review | `atom-3940a243bb9b4d17a0a4b790076c162f`, `atom-0eefa6ba21024058bb75316cb42de4d6`, `atom-4126138c06f84ecdbadbdffb8e228fc9`, `atom-0057d65618a7482caca0753c574cdcd7` |
| 2.5.13 | artifact symbol/framework inspection + runtime OS compatibility + semantic integration review | `atom-1386c41a24c643fdb20000fcaefc0821`, `atom-278df0505134493782dab1b40f540527` |
| 2.5.14 | artifact symbol/framework inspection + runtime OS compatibility + semantic integration review | `atom-515c453beb284e17b2b76a3ec9da0d9e`, `atom-05e2a3b4e13148cfb1346b72f06554cc` |
| 2.5.15 | artifact symbol/framework inspection + runtime OS compatibility + semantic integration review | `atom-3595d905f8f749dfb185ebc63a569514`, `atom-23ff6a342b554e8a9908588b0731e7a2` |
| 2.5.16 | artifact symbol/framework inspection + runtime OS compatibility + semantic integration review | `atom-d6bfb90a962c4dd39f042d00a582bc47` |
| 2.5.16(a) | artifact symbol/framework inspection + runtime OS compatibility + semantic integration review | `atom-1f77bf82172d4cfa80969a23c86c46f4`, `atom-322563ebb1c548c18815b05ff0d013ac` |
| 2.5.17 | artifact symbol/framework inspection + runtime OS compatibility + semantic integration review | `atom-b3fcc4ed783340f1aee3fea92ae7b3bb`, `atom-0c62e14c97974eaf95c413cb93cf16db` |
| 2.5.18 | artifact symbol/framework inspection + runtime OS compatibility + semantic integration review | `atom-01ad1dd07c5c4f539db0d42e987e1959`, `atom-f635b829c9db4040acbd5f08fb43a680`, `atom-4ef52dc6f7e947ba8bd07e8f41812976`, `atom-b80610a405da445a99321dd8c85c5ae8`, `atom-87b5107fbcc8416e80c69e6b51329a58`, `atom-6f25f94a1886450c9600463229b1b52a`, `atom-08289924f1294a30b65bfc6084911175`, `atom-0dbb61034ab2445d9939c489525cb04d` |

## Existing partial evidence

The other 26 Section 2 obligations have at least one existing check, but none of those checks establishes the entire duty. Their `decides` fields stay `partial`; each still needs a scoped full decision route or a recorded attestation question where behavior cannot be observed reliably. The existing check association is intentionally narrower than the old section-wide fan-out.

Partial-only IDs: `atom-27c1bcb131ec4062aba7bc9362d42302`, `atom-e575151c903d4c8fb72cede56c55c136`, `req-2f2096c499274b42bfe329048e038a33`, `atom-ea124ccce4354665991b411600d9eeaf`, `atom-f796bdeba806404d9d1caeb611d8732e`, `atom-cd12f23d19f343c1950ed58269e45360`, `atom-edd8489e47804bd6abc3972fd96b18f0`, `atom-334bde17ed704ef28c7949af2291fb13`, `atom-6805b1286df343709017cbde58dbf50e`, `atom-0f3c924c69bc46a19fe491245db2aa77`, `atom-b3f1b8ff2f154c76a76e8ad53c9933b1`, `atom-3367a8ec9d40428e9485fa06d6404903`, `atom-bef9722d5ab84f6db904c80fccdbf6a5`, `atom-c8d26ba611cb48fa8201dea7d711113b`, `atom-9518097ae09743e8a5d0e3a752b262aa`, `atom-d74e200dcb6642a7ae70e7f83e8a5645`, `atom-0ca323d6528245c3a1abfe1ae09bb627`, `atom-1eb522be2fd7493e81e6115fa15cbeec`, `atom-9db9677a29c5465aac9b166f78fe5950`, `atom-e1a97fafa5914e39be621f180bc1a137`, `atom-96d20ed02de5492290c863e05b2854d4`, `atom-7d829d5c917947adb6a8fb6872e8f6bc`, `atom-0162f240996e46ff9c4167f88c7efaa2`, `atom-7eaa8420985d4f51856fd1e7314316ef`, `atom-fac8c4a06bdb4184a49787b404f2c1ab`, `atom-17d97473b1734f77a5309a54e43743d4`.

## Integration requests

- Merge this section with `python3 scripts/coverage.py --merge` after peer review, then rerun coverage validation.
- Add `tests/test-obligations-2.sh` to `tests/all.sh` (integrator-owned).
- Route missing macOS/tvOS duties honestly: build/run currently audits iOS simulators; preserve `platform-not-audited` and request developer evidence instead of implying a simulator pass.
- For 2.1(a), a dark backend should leave login evidence inconclusive and prompt backend remediation; it must not be reported as a proven bad credential.
- `2.5.6` alternative-engine permission depends on entitlement and applicable storefront; `2.5.2` educational code exception depends on app purpose and source visibility. Keep these predicates linked to the operative atoms.

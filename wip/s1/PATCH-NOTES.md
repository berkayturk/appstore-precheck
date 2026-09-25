# S1 section 1.x integration notes

Section 1 fragment: `skills/appstore-precheck/references/obligations/1.json`. Merge with `coverage.py --merge` on the integration branch.

All existing check mappings in this fragment are **partial**. The following obligation IDs need implemented, registered, fixture-tested routes; the final column is the target route family, not an implemented check ID. No `not_app_checkable` entry is used for a genuine developer duty.

| Obligation ID | Apple ref | Suggested future routes |
|---|---|---|
| `atom-6a9ccd921f234306b5c47b9eb2cfc16b` | 1.1 | semantic |
| `atom-a4f2adc1120b4379883ed7055ffc2a8f` | 1.1.1 | semantic |
| `atom-54af33f29d8f46dfadc64688752cfba3` | 1.1.2 | semantic |
| `atom-40fe49bd689740b4a9de179221c187e6` | 1.1.2 | semantic |
| `atom-058d7ffef5fa4358b935b69aa1ef6e15` | 1.1.2 | semantic |
| `atom-2fcd0b8878af4175b4809085a400c4d6` | 1.1.3 | semantic |
| `atom-a97b9a857f9149958f63e5c1ea5bb7d4` | 1.1.3 | semantic |
| `atom-e1e5dd4351284c3cb362052ede106689` | 1.1.4 | semantic |
| `atom-a406cb745b2647ebab05e63c34564938` | 1.1.4 | semantic |
| `atom-4d0fbfc8ac274eb6b65f5ca81789322b` | 1.1.5 | semantic |
| `atom-abc7a5dcc4ea4dd39e530b5efdc6ef4c` | 1.1.5 | semantic |
| `atom-d21d8f8c5f4244f19324b26d9d109c57` | 1.1.6 | semantic |
| `atom-a2a5e40a2f5946c7bfd103f3e7a02ad2` | 1.1.6 | semantic |
| `atom-9209336ae03545949fabe472e53b563f` | 1.1.7 | semantic |
| `atom-e90ce97c6e7d4632b40f9f6fefe9c4d0` | 1.2 | runtime+semantic+attestation |
| `atom-e728e9764730455ab83bcf4a37e92384` | 1.2 | runtime+semantic+attestation |
| `atom-0dc300f5137a4c7e9833c5f4cca8bc24` | 1.2 | runtime+semantic+attestation |
| `atom-3695711bedf344469b8442714d23fca5` | 1.2 | runtime+semantic+attestation |
| `atom-dc2caed931c44f58abc0fc8807b00cfc` | 1.2 | runtime+semantic+attestation |
| `atom-5f9ba791c2b746daa65864befd7bc7f9` | 1.2.1 | runtime+semantic |
| `atom-3d7e6af4e0984c4daeab01f0b2f02244` | 1.2.1 | runtime+semantic |
| `atom-3deb247ab0e740c9afb2f58c46fd852a` | 1.2.1(a) | runtime+semantic |
| `atom-57e208a826334b3792bb5b8484e236a2` | 1.2.1(a) | runtime+semantic |
| `atom-557e5451c175420c8b8992d746b49a07` | 1.3 | runtime+artifact+semantic+attestation |
| `atom-9c53e07611ad4df3b1fda0d14b0ab465` | 1.3 | runtime+artifact+semantic+attestation |
| `atom-bb3fb63adabe4a5dbb7b9f569018a8c2` | 1.3 | runtime+artifact+semantic+attestation |
| `atom-6186554d692347f783bbb47b9052e065` | 1.3 | runtime+artifact+semantic+attestation |
| `atom-3e0f0c34543d434ba957cd1d634af137` | 1.3 | runtime+artifact+semantic+attestation |
| `atom-5f0e9701e9e84c24a76a30ecac3b7379` | 1.4 | runtime+semantic |
| `atom-51aba889f71c499eb7faca3ed514d66b` | 1.4.1 | semantic+attestation |
| `atom-cf0dd5a70e5a47c8bd3ecd533d4c9c0d` | 1.4.1 | semantic+attestation |
| `atom-9b4aa004dae84a22a66c46f674f29272` | 1.4.1 | semantic+attestation |
| `atom-a7348ccb4c63425ca0384e3ee4c9e339` | 1.4.2 | attestation+semantic |
| `atom-98d88ec86acc4741b25278e5405454bb` | 1.4.3 | semantic+metadata |
| `atom-e8f1053816464b5d9cc0200dac37129f` | 1.4.3 | semantic+metadata |
| `atom-e96ea933c0be4bafada64388114da3e5` | 1.4.3 | semantic+metadata |
| `atom-5cfe6efad6b0475fa06cbfd8233f675b` | 1.4.3 | semantic+metadata |
| `atom-1120cf24fc3e431b87ba3e7bf5583dd5` | 1.4.3 | semantic+metadata |
| `atom-a11ad225300a477d8bdef0b539f52389` | 1.4.3 | semantic+metadata |
| `atom-2cfda6d6703b4610aac220d3f6bfafc9` | 1.4.4 | semantic+attestation |
| `atom-98dd49825df5474bb71c4d416caf00b8` | 1.4.4 | semantic+attestation |
| `atom-8e828e3910c64410ba6ef42c1155a17b` | 1.4.5 | semantic+runtime |
| `atom-7c7546436ef84b0c99c309a7bde451bc` | 1.4.5 | semantic+runtime |
| `atom-d188d94683794eb6a1e3977400195292` | 1.5 | runtime+metadata+artifact |
| `atom-d1a35f3c93ba453fb776bf0a5b2a9612` | 1.5 | runtime+metadata+artifact |
| `atom-564c86e5c2b44721aacf6d633eec6024` | 1.5 | runtime+metadata+artifact |
| `atom-5185983edd3c4ce6b703a88850a08ad3` | 1.6 | artifact+runtime+attestation |
| `atom-07be96c43fdd40c9a9a80c9dad4e5094` | 1.7 | metadata+attestation |
| `atom-e3de8c3eed2c43fca45d753b8816164e` | 1.7 | metadata+attestation |
| `atom-cd332aacc916d543227d199423c74576` | 1.1.6 | semantic |
| `atom-a737e601b645d959436ab8f711a3015f` | 1.1.4 | semantic |
| `atom-726881973a096ad43aa49a76b2f997b1` | 1.4.1 | semantic+attestation |
| `atom-c969c9f28aa1f547adc9c2c637bb10fb` | 1.4.1 | semantic+attestation |
| `atom-55729f8061e341b694c5caac2a81bc92` | 1.4.2 | attestation+semantic |
| `atom-3e6c8461610ea4b69e9d276e85b06725` | 1.4.2 | attestation+semantic |

Kids 1.3 third-party information transfer remains under interpretation review because the linked Kids guidance describes a parental-consent case absent from this guideline paragraph. A source review must resolve the scope before claiming a final PASS/FINDING.

Live section 1.1–1.7 checked against https://developer.apple.com/app-store/review/guidelines/ on 2026-09-25; section headings and operative conditions agree with the private June 8 snapshot.

Existing partial routes do not by themselves make a full decision. Every obligation in the table needs a registered route; obligations already linked to partial checks also need stronger evidence before a definitive result.

The 1.2 UGC and 1.5 in-app contact obligations overlap; implementation should share evidence without double counting. The 1.6 candidate was merged into one security-protection duty, with the retired candidate preserved as a lineage marker.

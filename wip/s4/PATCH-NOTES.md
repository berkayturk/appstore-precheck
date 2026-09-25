# 4.x integration notes

Apple's live [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) were checked on 2026-09-25; the page reports June 8, 2026 as its last update. The 4.x wording and structure matched the private catalog snapshot. This branch contains only paraphrased criteria, stable IDs, URLs, and hashes.

The section file has **246 entries**: 104 obligations, 16 exceptions, 6 definitions, and 120 informational/source-lineage entries. Fifteen obligations have an existing partial route; **89 obligations still have no implemented route**. Source-fragment records link to their atomic children. No legacy atom was retired, so `retired_from` remains empty. The private source catalog is read only and is not committed.

## Route changes requested for the integrator

- Merge `references/obligations/4.json` into the public catalog. Preserve the empty `routes` arrays for the 89 gaps until an actual check and fixture exist.
- Existing `safari-extension` warns when an extension exists, but does not check Safari compatibility, UI interference, content, or website scope. Do not count it as a 4.4.2 coverage route.
- Existing `keyboard-full-access` only inspects `RequestsOpenAccess`; it is partial evidence for the Full Access duty, not keyboard input, network independence, data collection, or button behavior.
- Existing `applepay-recurring-disclosure` detects `PKRecurringPaymentRequest` and asks for review. It partially routes the renewal disclosures only; it does not inspect general purchase information or branding.
- Existing `push-marketing-optout` looks for notification-preference source signals. It partially routes the in-app opt-out duty only; it does not verify consent, sensitive payloads, or that app functionality works with push disabled.
- `saturated-category` detects category words in metadata. It is partial exposure evidence for the established-category differentiation rule, never a decision that the experience is unique.
- `webview-wrapper` and `minimum-functionality` are partial evidence for 4.2. `min-functionality-nav` was removed because absence of navigation containers does not establish any particular 4.2 duty.
- `siwa-parity` is partial detection of a login implementation; 4.8 accepts any equivalent alternative satisfying its three properties and includes five exceptions. The semantic `login-parity` route remains partial.

## Suggested new checks

- **Semantic + attestation:** 4.1 originality, impersonation, and third-party brand permission; 4.2 utility, AR quality, template ownership, and remote-desktop host/topology; 4.3 duplicate submissions and distinctiveness. Ask for proof of ownership and a comparison to related submissions where needed.
- **Runtime + metadata:** 4.2 first-launch resource disclosure and consent; 4.4 extension features and accurate marketing copy; 4.4.1 keyboard behavior; 4.4.2 Safari compatibility; 4.7 software index, links, age controls, consent, and moderation; 4.9 Apple Pay pre-sale information and branding.
- **Artifact + static:** 4.4 extension point and embedded purchase markers; 4.5 MusicKit purpose strings and resource usage; 4.5.6 embedded emoji artwork. Treat static hits as triage when actual behavior is required.
- **Attestation with cited evidence:** 4.5 Apple Music rights and permitted file operations, Apple-service and Game Center usage, push payload policy, Apple emoji distribution; 4.7 externally delivered software and legal compliance; 4.10 monetization of built-in capabilities. Questions should request evidence rather than turn developer answers into automatic PASS.

## Exact unrouted obligation IDs

### 4.1 (6)

- `atom-91ef4a8ef9524e4caba9432c1d056179`
- `atom-3efadb4870674cbd9a976c627abb6d95`
- `atom-eacb9f7c1602497890620dc60bacd562`
- `atom-ac7d46f547ea4b6b8d278dcc51494420`
- `atom-7226bc48bdc744bda367b8d3cda612ea`
- `atom-6b47b98f42ff4f178ff08b3db7131dec`

### 4.2 (2)

- `atom-5f4bebf5f0a74666b56a59333a1dded6`
- `atom-61f625798f274ef2ba5d46a6588e69ba`

### 4.2.1 (1)

- `atom-1868742025354677afbcfe25351860cc`

### 4.2.3 (3)

- `atom-cef8a9b87e1b4153814bb9832fa39557`
- `atom-4d8625d340b04ca89df9c09e85536ffe`
- `atom-22d8f2ed0bf34f9d9a4cc7f9e0a59516`

### 4.2.6 (3)

- `atom-571ea61296c44520bcf2d352c6b7258c`
- `atom-0f3dad5bca96441087dba6280914f3e1`
- `atom-2eafcc549fa34aa49ab5c66ede354584`

### 4.2.7 (11)

- `atom-43f3fac4df96422cb0464d76837fd9bf`
- `atom-c1e5a01ecec24a48bae2b840b899cee8`
- `atom-ac6b8fbef89e4bc2940be15482483253`
- `atom-c3f30bf439ab4bf7bab25b1464f43f9a`
- `atom-3173324d3c4640f3b4899edbfe4ec07a`
- `atom-d60945af298c431fae4736243ed83d9b`
- `atom-fc0cbe63158d4d87b0e15111ccb60c0e`
- `atom-485b3d0f67174dfa91c3e38665be0bde`
- `atom-bb5db11a64c442ed8c7d1c757c6bae6d`
- `atom-6dbde25a19fe40f1b5d37e92616b1de1`
- `atom-7e063c8db4674d2580970f3502fe8c05`

### 4.3 (2)

- `atom-cdc698f5a38544a192ea0296bc37e1fc`
- `atom-50eecf6e15f04b2db421de1994162175`

### 4.4 (6)

- `atom-aaafc08b9579440b8fa49684043cbe04`
- `atom-32e5b23ed6f749e6b67ca38184aa4fba`
- `atom-040b4f344e2a48798706832bb71ecbaf`
- `atom-fd2c644f97b34398ad0d88dadb904e33`
- `atom-594295e698124ecb868b7ed2e13ce3ed`
- `atom-ccf6410b7f2e40f69727f00eb0ee2fc2`

### 4.4.1 (7)

- `atom-0bbe4775c5c74d30aa392855e1b5a95b`
- `atom-e5ac4e44356f4044a7b93f52c9538ca3`
- `atom-ff52aa5fd3964b6794a25afe4266c124`
- `atom-85676598717d41d9932bf58e4cc1ed2f`
- `atom-1a37dc947e1a4c09b78dc649f90861db`
- `atom-7408ffab15ac40a1956049e440a8665e`
- `atom-6f5cf1036bb6444e91e7e880dee98dc2`

### 4.4.2 (5)

- `atom-f2a6619e8dd44de2bb7f23e570527f8a`
- `atom-32eea0fe94264d1e8abf7fa4ccc2943f`
- `atom-f318928d9cd44a78aacd41e9770747fe`
- `atom-1e9b7daba76645a999792eb2e324e9e7`
- `atom-0ddc92636653494299a5386150c8b9bf`

### 4.5.1 (2)

- `atom-d5429e6aa0b14c9da0fab53a0a821415`
- `atom-218085b57ed7404fbd7277dbb662eeca`

### 4.5.2 (15)

- `atom-2c11eb4e666c4036bec7f84d85356185`
- `atom-8040c00964ee4b078c2a2cd12ba27fbc`
- `atom-4d4dcded01ff42879e31d65779442d59`
- `atom-715ec1b4db554d688d27584d68a05493`
- `atom-bccea28625044678a61f12bb0caec086`
- `atom-fde2b694f3c8446a94b9571769e19443`
- `atom-581110bae9594bee87f173927142d9da`
- `atom-012fc7a56b904148be5bee6fdb1e4cf7`
- `atom-1eab217a6dc44a9dbf44ae4ce476b12c`
- `atom-177f8cb4e4aa4635b7e9e3aedf9b2000`
- `atom-9bffc375db2e43a983370fa37b0dfaa0`
- `atom-d6e0985d310c44fd899a77160eae579c`
- `atom-45b1a1f740bd4c4098035e8381fbc606`
- `atom-781dd8b7d32e44ff9cd50351bd7af6b7`
- `atom-c5d23911647e4577a92e25b2aaf74ae6`

### 4.5.3 (2)

- `atom-d9bb49e55b0d475db29b41f1b6646173`
- `atom-e90fcaa886e34e3aa890743f9b2ac524`

### 4.5.4 (3)

- `atom-0ea43ac08bbe45ee8142fb83bec4f49d`
- `atom-23977ffa0128474aa82267c1d967db43`
- `atom-c094d84bc7bf46a2a1ed6451b1744b22`

### 4.5.5 (3)

- `atom-585a71d359ce4a07a7c8df351b0da39a`
- `atom-652c375c2c5340e4bba332ec1d37fc0f`
- `atom-a76a8f96217b4eaa938e947152a9be0a`

### 4.5.6 (2)

- `atom-f9a75981f1664ada908c7d91b6e9081b`
- `atom-61e0a7fff6b4439ab5b47909b0ef7be7`

### 4.7 (1)

- `atom-364236cc9fd5406b82119942b6b07c9e`

### 4.7.1 (5)

- `atom-61d63b96e47649e3b75576a7a549d513`
- `atom-709d3d5132d5453aab70eef8eb84f50c`
- `atom-1cf1c65d615e4afda04bbe94b25cfa06`
- `atom-a793a07557994f63819fa767b554ffa7`
- `atom-d771a66bcb6148c2a9ddb04872efe2d9`

### 4.7.2 (1)

- `atom-e55f90814f264da8af6fdd40ca3f9a58`

### 4.7.3 (1)

- `atom-575bc6fc52584f87ab3e1cf72a82ffa8`

### 4.7.4 (2)

- `atom-208c77ee42f64ca19c1b9dda226b7dd0`
- `atom-5883c3b5e7f94ea1bf7e1bc838ac1126`

### 4.7.5 (2)

- `atom-39bf00b84967456c84aa561e239e79d4`
- `atom-d5728942b0084df8bb28b6bdd3368266`

### 4.9 (2)

- `atom-1abe4f651e6e4fd4b64ceeada46e5806`
- `atom-54ed20a61aa74eeead50ac2f7960ccd9`

### 4.10 (2)

- `atom-53ab44d76c4e40c5b4d24b2febe80814`
- `atom-c38322d596c14993add7e247e19cea65`

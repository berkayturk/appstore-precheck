# Section 5 integration notes

Apple live page checked on 2026-09-25: <https://developer.apple.com/app-store/review/guidelines/> (page says last updated June 8, 2026).

The section file contains 327 records, including 153 obligations. 48 obligations have an existing partial check; 105 still need a real implementation. No unimplemented check ID was placed in the JSON.

Merge `skills/appstore-precheck/references/obligations/5.json` into the shared public catalog. Register and implement the following route targets during R5/C/D/E/F; each must get a passing and failing fixture before it is counted as a route. A target here is a request, not current coverage.

| Gap ID | Obligation ID | Target route | Criterion |
|---|---|---|---|
| `gap-5-7e03867476aa` | `atom-7e03867476aa4cc18bae2fca15c601af` | `attestation` | App complies with applicable law in each jurisdiction where it is distributed. |
| `gap-5-eeabb9f540ca` | `atom-eeabb9f540ca4925878c50301cab752f` | `attestation` | Reject features that invite unlawful acts or behavior posing an obvious danger. |
| `gap-5-8acd67995bb5` | `atom-8acd67995bb540da8799affe1d0ce235` | `runtime` | Paid functionality is available without requiring consent to collect user or usage data. |
| `gap-5-bb20ccdb4098` | `atom-bb20ccdb409842d0adbfcf265851b93a` | `runtime` | App provides an easily accessible, understandable way to withdraw consent. |
| `gap-5-ce94405f21d2` | `atom-ce94405f21d247f8855d6a6dbe2869a3` | `attestation` | When collecting on a legitimate-interest basis without consent, app complies with every applicable term of the relied-on law. |
| `gap-5-772324aedc87` | `atom-772324aedc8748a0b372895fb000d55e` | `attestation` | App does not require personal information merely to function unless directly relevant to core functionality or required by law. |
| `gap-5-8b1c9735bb4b` | `atom-8b1c9735bb4b42f5b0edcb8aa1b8b2cc` | `runtime` | App offers in-app revocation of social-network credentials and disconnection of app/social-network data access. |
| `gap-5-247787870da9` | `atom-247787870da948778d03304e00f03c69` | `runtime` | App does not store social-network credentials or tokens off device. |
| `gap-5-a5d47e7b7cd6` | `atom-a5d47e7b7cd64ff6aebc51096764bf2b` | `semantic` | App uses social credentials or tokens only to connect directly from the app to the social network while the app is in use. |
| `gap-5-567fcfe39966` | `atom-567fcfe399664139bc470039a64ca7c3` | `artifact` | App does not surreptitiously discover passwords or other private user data. |
| `gap-5-d92f12086757` | `atom-d92f120867574355af6017dbf32a1942` | `runtime` | App uses SafariViewController only to visibly present information to users. |
| `gap-5-f42158db06de` | `atom-f42158db06de4196a0aaa0f39193cfe5` | `runtime` | App does not hide or obscure SafariViewController with other views or layers. |
| `gap-5-24f8d7b97d14` | `atom-24f8d7b97d144e308987cdc80ae3ed1c` | `runtime` | Do not turn a displayed SafariViewController into an undisclosed tracking mechanism; obtain informed permission before tracking. |
| `gap-5-7cb28983fd1b` | `atom-7cb28983fd1b400a97da56fdf9f7c6da` | `semantic` | Do not assemble personal profiles from indirect sources unless each affected person expressly agrees. |
| `gap-5-70d35afde54d` | `atom-70d35afde54d41ba86a5ef3c35eec61b` | `attestation` | A highly regulated or sensitive-data service app is submitted by the legal entity providing that service rather than an individual developer. |
| `gap-5-f410a13ed4c3` | `atom-f410a13ed4c3466d9e11459c1b650f0a` | `attestation` | App facilitating legal cannabis sales restricts those sales to corresponding legal jurisdictions. |
| `gap-5-ba721daeb5b5` | `atom-ba721daeb5b543bc8488e50734fd0dcc` | `semantic` | Basic contact-information request is optional. |
| `gap-5-ab1d52065265` | `atom-ab1d520652654d109e2d31be463c1d44` | `runtime` | Features and services remain available when basic contact information is withheld. |
| `gap-5-e3f3c55abc10` | `atom-e3f3c55abc10411d9d9d920ac373e4e2` | `attestation` | Do not use personal data without first obtaining permission or evidencing an applicable legal permission. |
| `gap-5-7df23b628e4c` | `atom-7df23b628e4c4db1915e7502b8873319` | `attestation` | Do not transmit personal data without first obtaining permission or evidencing an applicable legal permission. |
| `gap-5-11e76e5edaae` | `atom-11e76e5edaae4ce6b23b847674e46853` | `attestation` | Do not share personal data without first obtaining permission or evidencing an applicable legal permission. |
| `gap-5-79c635c3c990` | `atom-79c635c3c990448e94377af84bf555bb` | `artifact` | Provide accessible information about how personal data will be used. |
| `gap-5-677ed971d76d` | `atom-677ed971d76d47f9acc3043b6d9317fe` | `artifact` | Provide accessible information about where personal data will be used. |
| `gap-5-1bc7e5b4546c` | `atom-1bc7e5b4546c4c45ab14f701114dc5cc` | `attestation` | Share app-collected data with third parties only to improve the app or serve advertising under applicable Developer Program License Agreement terms. |
| `gap-5-00204211686c` | `atom-00204211686c46b09e24f3191affb97c` | `runtime` | Obtain explicit permission through App Tracking Transparency APIs before tracking user activity. |
| `gap-5-8fd93bdceb64` | `atom-8fd93bdceb6444498609324b7c61e3d8` | `artifact` | App does not require enabling push, location, tracking or other system functionality to access functionality or content. |
| `gap-5-520e10834c0a` | `atom-520e10834c0a4530824bcbc2a64747df` | `semantic` | App does not require enabling system functionality to receive monetary or other compensation. |
| `gap-5-9a95aa0d44d5` | `atom-9a95aa0d44d54296922ecee0f77b6bdc` | `runtime` | Do not repurpose collected data beyond its original purpose without further consent. |
| `gap-5-763515db4a4c` | `atom-763515db4a4c47959997735cab09c052` | `artifact` | Do not secretly build user profiles from collected data. |
| `gap-5-a977ae613673` | `atom-a977ae61367344ee9bc7f051b747a19f` | `runtime` | Do not attempt, facilitate or encourage identifying anonymous users or reconstructing profiles from Apple API data or data claimed to be anonymous, aggregated or non-identifiable. |
| `gap-5-014698fe8c18` | `atom-014698fe8c1847f8862cf769b30ca51e` | `artifact` | Do not use Contacts, Photos or other user-data API information to build a contact database for own use or third-party distribution. |
| `gap-5-c65ebb9d7f72` | `atom-c65ebb9d7f7244b7a38c4ddbb3e64fff` | `semantic` | Do not collect the user’s installed-app list for analytics, advertising or marketing. |
| `gap-5-0c7f04014605` | `atom-0c7f040146054195b3bc6d0930acf17a` | `runtime` | Contact a person using Contacts/Photos information only at the user’s explicit initiative on an individualized basis. |
| `gap-5-65dfb80eab8a` | `atom-65dfb80eab8a41aaa181d00193cea796` | `runtime` | Contacts/Photos-based outreach flow does not offer a Select All control. |
| `gap-5-fdf16daf58bd` | `atom-fdf16daf58bd4bafa2113eec8e4e0c5f` | `semantic` | Contacts/Photos-based outreach flow does not preselect all contacts. |
| `gap-5-ff59fd94cf24` | `atom-ff59fd94cf244bcb93683f762aef55c9` | `runtime` | Before sending a Contacts/Photos-based message, clearly show how it will appear to the recipient, including message text and sender identity. |
| `gap-5-7bf8c3705406` | `atom-7bf8c37054064b7dad74dc80aee26117` | `artifact` | Exclude protected health, home, education, depth, and face data from ad targeting and behavioral mining by the app or vendors. |
| `gap-5-3a537a6bfc9a` | `atom-3a537a6bfc9a4cada31f0e71a523dfbb` | `artifact` | Limit third-party access to Apple Pay customer data to fulfillment or improvement of the purchased offering. |
| `gap-5-ab5fede52052` | `atom-ab5fede520524d80a3cc78a7f60fba2b` | `runtime` | Do not write false or inaccurate data to HealthKit or other medical research/management apps. |
| `gap-5-5345fc39e338` | `atom-5345fc39e3384d7d877bbc3ab4690564` | `runtime` | Obtain research participation consent from the participant or, for a minor, a parent or guardian. |
| `gap-5-17d9787fe0d6` | `atom-17d9787fe0d6421c8d75312e2e90b399` | `runtime` | Research consent describes the study nature, purpose and duration. |
| `gap-5-961ef578802a` | `atom-961ef578802a49a49644105cea490520` | `runtime` | Research consent describes participant procedures, risks and benefits. |
| `gap-5-cb20c1aeb866` | `atom-cb20c1aeb8664768a562a997a5637d0e` | `runtime` | Research consent describes confidentiality and data handling, including third-party sharing. |
| `gap-5-6a3b78e8f9fb` | `atom-6a3b78e8f9fb44ee898de3187f91ba88` | `runtime` | Research consent supplies a reachable contact for participant questions. |
| `gap-5-ca3179bd26c1` | `atom-ca3179bd26c14413bba212bbebf6d6a9` | `runtime` | Research consent explains the withdrawal process. |
| `gap-5-45f00d84ec5d` | `atom-45f00d84ec5d429e9c09b6420254ba9c` | `semantic` | Obtain approval from an independent ethics review board before conducting health-related human subject research. |
| `gap-5-aff1d3b887b7` | `atom-aff1d3b887b74dc0bf870a020d0b7e5c` | `attestation` | Provide proof of independent ethics board approval when requested. |
| `gap-5-52e7a8b0d587` | `atom-52e7a8b0d58746329256d94a7cf4d08b` | `runtime` | Request a child’s birthdate or parental contact information only to comply with an identified applicable child-privacy statute. |
| `gap-5-c75ba1451958` | `atom-c75ba14519584289821143d84f4ce260` | `runtime` | Offer useful functionality or entertainment regardless of a person’s age. |
| `gap-5-17970632211d` | `atom-17970632211d46b690515a03c100a3a8` | `artifact` | An app intended primarily for kids does not include third-party analytics absent a verified limited exception. |
| `gap-5-0f27633791cf` | `atom-0f27633791cf4eecba0ba3d066755670` | `artifact` | An app intended primarily for kids does not include third-party advertising absent a verified limited exception. |
| `gap-5-925e6d260557` | `atom-925e6d2605574764808aef786bcf60f1` | `artifact` | Kids Category or qualifying minor-data app complies with all applicable children’s privacy statutes. |
| `gap-5-6c7298fe0e60` | `atom-6c7298fe0e60432aa202d451d5d91095` | `semantic` | A non-Kids Category app avoids any name, subtitle, icon, screenshot or description term implying its main audience is children. |
| `gap-5-fbb93f8e7fbd` | `atom-fbb93f8e7fbd419dbcf8198a6e4f745c` | `runtime` | Use Location Services only when directly relevant to features or services the app provides. |
| `gap-5-f6af4b2b516f` | `atom-f6af4b2b516f455da08e1216c4c00397` | `artifact` | Do not use location-based APIs to provide emergency services under the stated restriction. |
| `gap-5-f6d778971eed` | `atom-f6d778971eed4d17958fb4135ef91319` | `runtime` | Do not use location-based APIs for autonomous control of vehicles, aircraft or other devices outside the stated small-device exception. |
| `gap-5-c556fa0944be` | `atom-c556fa0944be4a9083d1edf566eff01c` | `artifact` | Notify users before collecting, transmitting or using location data. |
| `gap-5-2bc80710fdb7` | `atom-2bc80710fdb74e07a10fe67992557c50` | `runtime` | Secure permission before any collection, transfer, or use of a person’s location. |
| `gap-5-e439b234d805` | `atom-e439b234d8054804b4f719c288748a7c` | `runtime` | App explains the purpose of Location Services to users within the app. |
| `gap-5-add39d454b9d` | `atom-add39d454b9d4973b5438574d37eedb2` | `attestation` | All app content is created by the developer or used under a license. |
| `gap-5-41c5d2552e85` | `atom-41c5d2552e854bf68481269e574babdd` | `attestation` | The submitting person or legal entity owns or licenses the app intellectual property and relevant rights. |
| `gap-5-5b22e14eeb3f` | `atom-5b22e14eeb3f4a6babc545a485387628` | `semantic` | That use is specifically permitted under the current service terms. |
| `gap-5-2f14eed6c557` | `atom-2f14eed6c5574d76811dbe25ce3af0b5` | `attestation` | When App Review requests it, provide authorization covering the identified third-party service access or content use. |
| `gap-5-74090a65c867` | `atom-74090a65c8674858ae889e161dfac187` | `attestation` | The app does not facilitate illegal file sharing. |
| `gap-5-12c2449b917d` | `atom-12c2449b917d4e8184e852a24fc58f00` | `attestation` | Require specific source authorization before enabling third-party media capture, conversion, or offline saving. |
| `gap-5-cab0d99ae5fd` | `atom-cab0d99ae5fd4afe9d4aa4caa42e3188` | `attestation` | When App Review requests it, provide authorization covering the identified media source and saving, conversion, download, or streaming operation. |
| `gap-5-d1942b8d7266` | `atom-d1942b8d72664e62977a447e35bc033d` | `semantic` | The app does not imply Apple supplies or endorses the app or its quality or functionality. |
| `gap-5-2ba643771a14` | `atom-2ba643771a144366a3edd3d22f2b2821` | `semantic` | Distinguish the product, interface, and marketing identity from Apple’s own offerings. |
| `gap-5-ab7c53b3e758` | `atom-ab7c53b3e758410ba76e7b4860efb4e6` | `artifact` | The app and extensions do not include Apple emoji. |
| `gap-5-dea5dcf0c192` | `atom-dea5dcf0c1924c22ad9f808954e562d9` | `attestation` | Preview music is not used for entertainment value or any other unauthorized purpose. |
| `gap-5-fc3bf099d5e6` | `atom-fc3bf099d5e640739bddbd4d682eee85` | `artifact` | Present an appropriate destination link for each iTunes or Apple Music preview offered. |
| `gap-5-082c9313d633` | `atom-082c9313d6334971a66bb09f9b9a4c2a` | `runtime` | Move, Exercise and Stand data are not visualized in a way resembling the Activity control. |
| `gap-5-b615317e8229` | `atom-b615317e82294f26950c88c94b100f57` | `semantic` | The display follows current WeatherKit attribution requirements. |
| `gap-5-012fd8342432` | `atom-012fd83424324b45b0bb8ae62b355585` | `attestation` | Gaming, gambling or lottery functionality is offered only after its legal obligations have been assessed for every distribution territory. |
| `gap-5-9cee242a0201` | `atom-9cee242a020143f9bdbe68a1861f3e2b` | `runtime` | App does not sell credits or currency through in-app purchase for use with real-money gaming. |
| `gap-5-78f312ec6cf0` | `atom-78f312ec6cf04db4913d28c197c363b8` | `attestation` | VPN app is offered by an organization-enrolled developer. |
| `gap-5-fa591b0a5a0a` | `atom-fa591b0a5a0a46c7b4065a857dc24730` | `artifact` | VPN app does not sell VPN user data. |
| `gap-5-c2e46b4ee9a2` | `atom-c2e46b4ee9a24f2494b96b9e2657ddbc` | `artifact` | VPN app does not use VPN user data for a separate purpose prohibited by this clause. |
| `gap-5-f1e2d49b361e` | `atom-f1e2d49b361e4aa2bd28d71508586fd8` | `artifact` | VPN app does not disclose VPN user data to third parties for any purpose. |
| `gap-5-8116e55d4922` | `atom-8116e55d49224629bc42c51e4b953b1f` | `attestation` | VPN app complies with applicable local law in each territory where offered. |
| `gap-5-5dbfbb56b2f2` | `atom-5dbfbb56b2f24dc68e899b34ad4f7f9b` | `attestation` | VPN license information is supplied in App Review Notes for every territory requiring a VPN license. |
| `gap-5-c04cdf6675c0` | `atom-c04cdf6675c044958452daefd7a8b545` | `attestation` | MDM app is offered by a qualifying commercial enterprise, educational institution or government agency. |
| `gap-5-b480b51d1412` | `atom-b480b51d141242809e25a1049c9e423d` | `runtime` | MDM app clearly declares user-data collection and uses on screen before purchase or use. |
| `gap-5-4d1e304f7545` | `atom-4d1e304f75454effa650679c9bfba5f3` | `attestation` | MDM app complies with applicable local laws in each offered territory. |
| `gap-5-1c570ec994cd` | `atom-1c570ec994cd459facac23fe6583a1a2` | `runtime` | MDM app does not sell user, device or managed-app data. |
| `gap-5-0d5d7c64c4a9` | `atom-0d5d7c64c4a9440994be9ba845e06ac0` | `artifact` | MDM app does not use such data for a prohibited separate purpose. |
| `gap-5-d0d728497c3a` | `atom-d0d728497c3a44908d4742c6c793e704` | `artifact` | MDM app does not disclose such data to third parties outside a supported narrow analytics exception. |
| `gap-5-b42c3f70b6bc` | `atom-b42c3f70b6bc4e89a92a90c6b4be0369` | `artifact` | MDM privacy policy commits to the data restrictions. |
| `gap-5-400b2c4ef57c` | `atom-400b2c4ef57c4a4c92bc6730ee42c447` | `metadata` | Developer communications with customers, reviewers and Apple treat recipients respectfully. |
| `gap-5-088ba6e7e738` | `atom-088ba6e7e73842f8acc25c1b7bd96745` | `semantic` | Developer does not harass people. |
| `gap-5-7f7d9a21d982` | `atom-7f7d9a21d98241ebac3fecba43cfe19a` | `runtime` | Developer does not engage in discriminatory practices. |
| `gap-5-977d672e184a` | `atom-977d672e184a48bc82db0e1bf061d484` | `semantic` | Developer does not intimidate people. |
| `gap-5-d6ab20800d21` | `atom-d6ab20800d2149738191c9fbf1df906c` | `semantic` | Developer does not bully people. |
| `gap-5-2202bf737f4c` | `atom-2202bf737f4c45e4ab452c151214444b` | `runtime` | Developer does not encourage others to engage in harassment, discrimination, intimidation or bullying. |
| `gap-5-4f82ed2750de` | `atom-4f82ed2750de4cea9b57cf6ae7c20cd3` | `semantic` | App/developer does not prey on users or rip off customers. |
| `gap-5-0131dc175ab5` | `atom-0131dc175ab54b7f808d5b0b5337c458` | `semantic` | App/developer does not trick users into unwanted purchases. |
| `gap-5-646f22c0e861` | `atom-646f22c0e861405db627da967ec103a7` | `artifact` | App/developer does not force sharing of unnecessary data. |
| `gap-5-80d54627ed05` | `atom-80d54627ed054880b813c856b194e878` | `semantic` | App/developer does not raise prices deceptively. |
| `gap-5-9c250fe27954` | `atom-9c250fe279544f489dc6ad9cab16261c` | `semantic` | Do not bill customers for promised digital value that they never receive. |
| `gap-5-d1a8bf9c8c06` | `atom-d1a8bf9c8c064dcab7468a951d1aa352` | `runtime` | App/developer does not engage in other manipulative practices inside or outside the app. |
| `gap-5-6bf9ff414943` | `atom-6bf9ff4149434d63b5552995ca167862` | `metadata` | Developer review replies address the user’s comment. |
| `gap-5-25326c8d8ae6` | `atom-25326c8d8ae6494b94b14df8d84aeece` | `metadata` | Developer review replies do not include personal information. |
| `gap-5-558161f2c559` | `atom-558161f2c5594db5a429a533f418ad9c` | `metadata` | Developer review replies do not include spam. |
| `gap-5-8073a2a06fae` | `atom-8073a2a06fae4fd5a2177ddd2060f5d0` | `metadata` | Developer review replies do not include marketing content. |
| `gap-5-272cc4613bd9` | `atom-272cc4613bd9fafd09e58bcf425d944e` | `metadata` | Maintain a functioning, dependable customer experience; investigate sustained complaint and refund patterns as potential quality evidence. |

## Integration cautions

- The `5.1.1(v)` personal-information exception applies only when data is needed for core functionality or a concrete legal duty. The account-deletion obligation has no general login exception.
- Consent exceptions in `5.1.2(i)` and `(ii)` require a named legal basis; a missing consent UI does not prove an exception.
- `5.1.3` health research conditions and `5.1.4` child-data clauses require product-specific legal and operational evidence. Static source signals alone cannot close them.
- `5.3.4` territory, license, and storefront price claims require live distribution context. The existing gambling keyword check is only partial.
- `5.4` VPN and `5.5` MDM static checks establish possible feature use, not organizational eligibility, lawful data handling, or availability of licenses.
- `5.6.4` has one added atom for the ongoing quality duty; its ID is derived from the source fragment because the private draft had no candidate atom. Independent review should confirm whether this is an obligation or informational quality signal.

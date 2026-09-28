# Guideline obligation coverage

This counts available routes, not checks that ran for an app. Routes can overlap.

Every obligation carries the generic developer-attestation route, so the routed share is complete by construction. It shows that each obligation has a documented way to be answered, not that the tool can decide it automatically. This report does not certify App Store compliance.

Condition-based executable capability is reported separately in [verification-capability.md](verification-capability.md). Legacy full-route labels do not establish evidence-bound readiness.

| Measure | Count | Share |
|---|---:|---:|
| Obligations | 580 | 100% |
| Routed (including developer attestation) | 580 | 100.0% |
| Without route | 0 | 0.0% |
| With a route other than attestation | 155 | 26.7% |
| With an automated route (static, artifact, runtime or metadata) | 117 | 20.2% |
| Full positive automatic decision capability | 1 | 0.17% |
| Legacy full-route declarations | 0 | 0.0% |
| Semantic route | 66 | 11.4% |
| Attestation only (developer attestation or evidence) | 425 | 73.3% |

Automated and semantic routes are partial signals unless the capability row says otherwise.

## Route counts

| Route | Obligations |
|---|---:|
| artifact | 10 |
| attestation | 580 |
| metadata | 12 |
| not_app_checkable | 0 |
| runtime | 28 |
| semantic | 66 |
| static | 106 |

Section classifications and atomic splits received an independent review; the route count is not an App Store approval guarantee.

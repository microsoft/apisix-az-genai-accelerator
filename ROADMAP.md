# Future Enhancements

## Advanced Gateway Capabilities

- Backend Authentication via Managed Identity
  - Allow APISIX to call Azure OpenAI (and other managed services) using managed identities instead of API keys, mirroring APIM’s MSI-based backend auth and simplifying secret rotation.
- E2E Test: ACA Request-Based Gateway Scaling
  - Build an automated test that drives sustained, bursty traffic through the APISIX gateway ACA and asserts scale-out/scale-in based on requests-per-second thresholds (e.g., KEDA HTTP add-on). Validate replicas, latency, and error rates before and after scaling, and surface results in CI as a gating signal.

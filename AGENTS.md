# APISIX Azure GenAI Accelerator – Agent Guide

## Retrieving Available Metrics

1. Identify the Azure Monitor account resource ID if you do not have it cached:
   ```bash
   az resource list --name azmon-apisix-monitor-dev-eus-r2qsfg --query "[0].id" -o tsv
   ```
2. List platform metrics exposed via the Azure Metrics API:
   ```bash
   ACCOUNT_ID=/subscriptions/a68fcd37-74e0-4dae-94eb-7c1f33a36b4c/resourceGroups/rg-apisix-aca-dev-eus/providers/Microsoft.Monitor/accounts/azmon-apisix-monitor-dev-eus-r2qsfg
   az monitor metrics list-definitions --resource "$ACCOUNT_ID" | jq -r '.[].name.value'
   ```
3. Discover custom Prometheus metrics (APISIX, LLM, tracing) exposed by the managed workspace:
   ```bash
   TOKEN=$(az account get-access-token --resource https://prometheus.monitor.azure.com/ --query accessToken -o tsv)
   PROM_ENDPOINT=$(az resource show --ids "$ACCOUNT_ID" --query "properties.metrics.prometheusQueryEndpoint" -o tsv)
   curl -sS -H "Authorization: Bearer $TOKEN" "$PROM_ENDPOINT/api/v1/label/__name__/values"
   ```
4. Inspect labels for a specific metric when needed (example: latency histogram):
   ```bash
   curl -sS -G -H "Authorization: Bearer $TOKEN" \
     --data-urlencode "match[]=apisix_llm_latency_bucket" \
     "$PROM_ENDPOINT/api/v1/series"
   ```

- Store tokens securely; they expire after the standard Azure AD interval (typically 1 hour).

## Hydrenv Init Container Logs

Hydrenv runs as an init container on the gateway ACA, so `az containerapp logs show` cannot stream it directly. Use Log Analytics instead:

1. Locate the workspace ID (tenant GUID) from Terraform outputs or the ACA resource group:
   ```bash
   az monitor log-analytics workspace list \
     --resource-group rg-apisix-aca-<env>-eus \
     --query "[0].customerId" -o tsv
   ```
2. Query recent hydrenv runs (adjust revision list or time window as needed):
   ```bash
   WORKSPACE_ID=<customerId from step 1>
   az monitor log-analytics query \
     --workspace "$WORKSPACE_ID" \
     --analytics-query "ContainerAppConsoleLogs_CL
       | where ContainerAppName_s == 'ca-apisix-gateway-<env>-eus-<suffix>'
       | where ContainerName_s == 'hydrenv-init'
       | order by TimeGenerated desc
       | take 50" \
     --output table
   ```

This returns the latest rendered-template logs (render count, Key Vault enrichment, etc.) for hydrenv across revisions.

## Scripts

- Keep runs consistent across agents: build/deploy with our `uv` scripts; run tests with the right env so telemetry queries succeed.

## How to work here

- Use `uv run` helpers under `ops` for builds and deploys (e.g., `uv run python -m ops.build_images …`, `uv run python -m ops.deploy_gateway …`).
- Don’t edit submodules unless explicitly approved.

## Running the prioritization E2E test

- When invoking `apim-genai-gateway-toolkit/scripts/run-end-to-end-prioritization.sh`, set the Log Analytics table env var the toolkit reads:
  - `APIM_GATEWAY_LOGS_TABLE=APISIXGatewayLogs_CL`
- Ensure the toolkit output files point to the current workspace before running (or supply workspace via env if supported).

## Quick checklist

- Build/deploy: `uv run python -m ops.build_images …` and related `uv run` commands only.
- Tests: pass `LOG_ANALYTICS_TABLE=APISIXGatewayLogs_CL` for prioritization runs.
- No changes in submodules without approval.

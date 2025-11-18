# Deployment Guide

This guide explains how to deploy the accelerator using the recommended uv-based CLI workflow and, for teams that prefer full manual control, a stack-by-stack Terraform walkthrough.

## 1. Automated Deployment (Recommended)

### Prerequisites
- Azure CLI authenticated (`az login`) with the subscription selected via `az account set`.
- Terraform and Docker (with Buildx) available on the PATH.
- `uv` installed from https://github.com/astral-sh/uv.
- Azure subscription permissions to create resource groups, Container Apps environments, Azure Container Registry, Key Vault, and (optionally) Azure AI Foundry resources.
- Azure OpenAI quota in the regions defined in the `15-openai` stack if you plan to provision Azure OpenAI resources.

### Workspace Preparation
1. Run `uv sync` once per workstation to install the CLI environment.
2. Copy `config/appsettings.example.env` to `config/appsettings.<env>.env` and populate non-secret settings.
3. Copy `config/secrets.example.env` to `config/secrets.<env>.env` (leave empty when using managed identity); keep this file out of source control.
4. (Optional) Create a stub `env/.env.<env>` file so the CLI can infer the environment suffix. The file can remain empty.
5. Review the Terraform variable templates in each stack directory (for example `infra/terraform/stacks/10-platform/dev.tfvars`) and customise them for the target environment.
6. Ensure the deploying principal has sufficient Azure AD rights (for example, Key Vault Administrator) if you expect Terraform to assign RBAC.
7. Optionally set CLI environment overrides such as `ACCELERATOR_DOCKER_PLATFORM` to control image build targets.

### Running the CLI
1. Sync configuration into Key Vault and regenerate Terraform inputs:
   ```bash
   KV_NAME=$(terraform -chdir infra/terraform/stacks/10-platform output -raw key_vault_name)
   uv run sync-env -- <env> --key-vault "$KV_NAME"
   ```
2. Execute `uv run deploy --env-file env/.env.<env>` to launch the full deployment. Optional flag:
   - `--skip-azure-openai` prevents the CLI from provisioning Azure OpenAI resources so you can reuse existing endpoints from the environment file.

### What the CLI Automates
1. **Validation** – Detects the environment suffix from the `.env` filename, verifies Azure CLI authentication, and checks required tooling.
2. **Bootstrap stack (`00-bootstrap`)** – Creates remote Terraform state storage and records metadata under `.state/<environment>/bootstrap.tfstate`.
3. **Platform stack (`10-platform`)** – Deploys platform and network resource groups, optional VNets, Azure Container Registry, and Key Vault with managed identity.
4. **Azure OpenAI stack (`15-openai`)** – (Optional) Provisions Azure AI Foundry instances, private endpoints, and records secrets for later consumption.
5. **Environment synthesis** – Invokes `uv run sync-env` to push app settings and secrets into Key Vault, then serialises the snapshot into `environment.auto.tfvars.json`.
6. **Image build & push** – Logs into the platform ACR and builds/pushes the `gateway` and `hydrenv` images using Docker Buildx.
7. **Workload stack (`20-workload`)** – Applies Terraform to create the Container Apps environment, deploy the gateway, configure observability, and (optionally) enable alerts.
8. **Cleanup** – Removes generated Terraform plan files.

Re-run the command after resolving any errors; completed stages are idempotent because Terraform refreshes state before planning updates.

### Additional CLI Entry Points
- `uv run deploy-bootstrap --environment <env>` – bootstrap stack only.
- `uv run deploy-foundation --environment <env>` – foundation stack only.
- `uv run deploy-openai --environment <env> [--skip-azure-openai]` – Azure OpenAI stack.
- `uv run deploy-aca --environment <env>` – workload stack only.
- `uv run build-images --registry <acr>` – rebuild gateway and hydrenv images.
- `uv run setup-environment --env-file <path>` – regenerate `environment.auto.tfvars` after editing `.env` files.

All commands use the current Azure CLI context; ensure `az account show` returns the intended subscription before running them.

### Environment File Expectations
- Production environments typically omit inline secrets so the CLI writes Key Vault entries and references them from Terraform.
- When Terraform provisions Azure OpenAI instances, leave the `AZURE_OPENAI_*` variables blank in the `.env` file; the CLI fills them from stack outputs. Any manually supplied values take precedence.

### Customisation Tips
- Adjust CPU/memory, ingress exposure, and observability options in `infra/terraform/stacks/20-workload/<environment>.tfvars` before running the CLI.
- Modify Azure OpenAI topology in `infra/terraform/stacks/15-openai/<environment>.tfvars`.
- Use shell aliases or environment variables to store frequently used CLI arguments (such as the env file path) to keep invocations consistent.

Refer to `README.md` for architectural context and `TROUBLESHOOTING.md` for diagnostic workflows.

---

## 2. Manual Deployment Workflow

Follow these steps if you prefer to run each Terraform stack, image build, and configuration step yourself. The sequence mirrors the automated workflow.

### 2.1 Prepare the Environment
- Authenticate with Azure CLI and select the deployment subscription.
- Ensure the principal has rights for resource groups, ACR, Key Vault, Container Apps, and Azure AI Foundry (if used).
- Populate `<environment>.tfvars` files inside each Terraform stack directory (`00-bootstrap`, `10-platform`, `15-openai`, `20-workload`).
- Copy `config/appsettings.example.env` / `config/secrets.example.env` into environment-specific files under `config/`, then run `uv run sync-env -- <environment> --key-vault <name>` (using the Key Vault from `terraform output -raw key_vault_name`) to produce `environment.auto.tfvars.json`.
- Optionally create a stub `env/.env.<environment>` file (used solely to infer the environment name when running the CLI).

### 2.2 Bootstrap Remote State (`infra/terraform/stacks/00-bootstrap`)
- Run `terraform init` using the local backend included in the stack.
- Apply the plan with the environment tfvars to create the remote state resource group, storage account, and blob container.
- Record outputs: storage account name, container name, blob key, resource group.

### 2.3 Configure Remote Backends
- For every subsequent stack, supply the remote backend configuration (tenant ID, resource group, storage account, container, blob key) obtained from the bootstrap outputs.
- Keep `use_azuread_auth = true` so Terraform authenticates with the Azure CLI session.

### 2.4 Platform Stack (`infra/terraform/stacks/10-platform`)
- Initialize Terraform with the remote backend settings from step 2.3.
- Provide Terraform variables for subscription ID, tenant ID, environment code, and location (via `TF_VAR_*` or a `.tfvars` file).
- Apply the configuration to create platform/network resource groups, VNets/subnets (if enabled), Azure Container Registry, and Key Vault with managed identity.
- Capture outputs: platform resource group name, ACR name, optional subnet IDs, Key Vault name, managed identity IDs.

### 2.5 Azure OpenAI Stack (`infra/terraform/stacks/15-openai`) — Optional
- Skip if you will use existing Azure OpenAI deployments.
- Otherwise, initialize Terraform with the remote backend and apply the stack that defines Azure AI Foundry instances, private networking, and logging.
- Note outputs: endpoint URLs, Key Vault secret names, and API keys (if surfaced) for later use.

### 2.6 Environment Variable Synthesis
- Run `uv run sync-env -- <environment> --key-vault <name>` after updating the config files. This command:
  - Normalises `config/appsettings.<environment>.env` and stages the values for Terraform.
  - Mirrors secrets from `config/secrets.<environment>.env` to the specified Key Vault and records their names.
  - Writes `infra/terraform/stacks/20-workload/environment.auto.tfvars.json`, which Terraform consumes automatically.
- Re-run the script whenever you edit configuration values so the latest snapshot is recorded.

### 2.7 Build and Publish Images
- Retrieve the platform ACR login server from the foundation outputs.
- Authenticate to the registry and build/push the `gateway` and `hydrenv` images tagged with the expected names (`<acr>.azurecr.io/apisix-az-genai-accelerator/<image>:<tag>`).
- Ensure the workload tfvars reference the correct image tags.

### 2.8 Workload Stack (`infra/terraform/stacks/20-workload`)
- Supply Terraform with subscription ID, tenant ID, environment code, location, platform resource group, ACR name, subnet IDs, Key Vault name, managed identity IDs, and state storage metadata.
- Initialize Terraform with the remote backend pointing at `20-workload.tfstate`.
- Review and apply the plan to create the Container Apps environment, gateway deployment, observability resources, and optional alerts.

### 2.9 Post-Deployment Validation
- Check that container app revisions reach `Healthy` and that ingress endpoints respond as expected.
- Confirm logs, traces, and metrics appear in Application Insights and Azure Monitor.
- Verify Key Vault secret references resolve correctly (no secret binding errors in Container Apps).
- Update DNS, firewall rules, or identity mappings as needed to put the gateway into service.

### 2.10 Ongoing Operations
- Re-run individual stacks after adjusting Terraform variables or infrastructure settings.
- Rebuild and republish container images when gateway or renderer code changes.
- Use the troubleshooting guide to diagnose issues in Terraform, Container Apps, or telemetry streams.

## Migration from legacy `.env` workflow

If you previously maintained configuration solely in `env/.env.<environment>`:

1. Copy non-secret values into `config/appsettings.<environment>.env`.
2. Move any secrets into `config/secrets.<environment>.env` (or omit them when using managed identity).
3. Leave `env/.env.<environment>` in place as a minimal stub (it can be empty or contain comments).
4. Run `uv run sync-env -- <environment> --key-vault <name>` once to seed Key Vault and refresh `environment.auto.tfvars.json`.

The CLI and Terraform will now read configuration from the generated `environment.auto.tfvars.json`, and you can delete secret material from the legacy `.env` files.

This manual checklist mirrors the automated CLI flow while giving operators full control over each command.

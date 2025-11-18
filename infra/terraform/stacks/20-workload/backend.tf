terraform {
  backend "azurerm" {
    # Backend configuration is provided via command-line flags:
    # terraform init \
    #   -backend-config="use_azuread_auth=true" \
    #   -backend-config="tenant_id=${TENANT_ID}" \
    #   -backend-config="storage_account_name=${STORAGE_ACCOUNT_NAME}" \
    #   -backend-config="container_name=${CONTAINER_NAME}" \
    #   -backend-config="key=${KEY}"
  }
}

terraform {
  backend "azurerm" {
    # Backend configuration supplied via CLI similar to other stacks:
    # terraform init \
    #   -backend-config="use_azuread_auth=true" \
    #   -backend-config="tenant_id=${TENANT_ID}" \
    #   -backend-config="storage_account_name=${STORAGE_ACCOUNT_NAME}" \
    #   -backend-config="container_name=${CONTAINER_NAME}" \
    #   -backend-config="key=${KEY}"
  }
}

/// Stack: 00-bootstrap
/// Purpose: Provision remote state storage only

module "public_ip" {
  source = "github.com/lonegunmanb/terraform-lonegunmanb-public-ip?ref=v0.1.0"
}

module "state" {
  source = "../../modules/platform/state"

  subscription_id  = var.subscription_id
  tenant_id        = var.tenant_id
  environment_code = var.environment_code
  location         = var.location
  workload_name    = var.workload_name
  identifier       = var.identifier

  sa_replication_type              = var.sa_replication_type
  soft_delete_retention_days       = var.soft_delete_retention_days
  enable_state_sa_private_endpoint = var.enable_state_sa_private_endpoint
  private_link_subnet_id           = var.private_link_subnet_id
  state_rg_name_override           = var.state_rg_name_override
  allowed_public_ip_addresses      = module.public_ip.public_ip == "" ? [] : [module.public_ip.public_ip]

  tags = var.tags
}

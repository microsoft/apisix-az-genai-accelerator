terraform {
  # Path is supplied per-environment via -backend-config by the deploy script.
  backend "local" {}
}

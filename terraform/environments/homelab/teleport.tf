# Teleport resources are managed manually (not via Terraform provider)
# to avoid requiring a long-lived identity file in terraform.tfvars.
#
# One-time setup — run from a machine with tctl access:
#
#   tctl tokens add --type=node --ttl=87600h
#   # copy token → paste as vm_join_token in terraform.tfvars
#
#   tctl tokens add --type=node --ttl=87600h
#   # copy token → paste as lxc_join_token in terraform.tfvars
#
# Tokens are gitignored (only in terraform.tfvars).
# To rotate: generate new tokens, update tfvars, reprovision nodes.

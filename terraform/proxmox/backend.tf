# Terraform State Backend
#
# By default, Terraform stores state locally in terraform.tfstate.
# Local state is fine for a solo homelab, but has risks:
#   - Lost if the machine running Terraform is rebuilt
#   - No locking (concurrent runs can corrupt state)
#   - Not backed up automatically
#
# Recommended: Use an S3-compatible remote backend (MinIO on TrueNAS).
# This gives you: versioned state history, locking via DynamoDB or S3-native,
# and easy recovery if your workstation dies.
#
# ── Option A: MinIO on TrueNAS (on-prem, no cloud cost) ──────────────────────
#
# 1. Create a MinIO bucket named `terraform-state` on TrueNAS
# 2. Create an access key with read/write on that bucket
# 3. Uncomment the block below and fill in your MinIO endpoint + credentials
#
# terraform {
#   backend "s3" {
#     bucket                      = "terraform-state"
#     key                         = "proxmox/terraform.tfstate"
#     region                      = "us-east-1"       # any value, required by SDK
#     endpoint                    = "http://truenas.lan:9000"
#     access_key                  = "your-minio-access-key"
#     secret_key                  = "your-minio-secret-key"
#     skip_credentials_validation = true
#     skip_metadata_api_check     = true
#     skip_region_validation      = true
#     force_path_style            = true              # required for MinIO
#   }
# }
#
# ── Option B: Gitea-native HTTP backend ───────────────────────────────────────
#
# Gitea has a built-in Terraform HTTP backend (since Gitea 1.19).
# This stores state as a Gitea package — no S3 needed.
#
# terraform {
#   backend "http" {
#     address        = "https://gitea.hughboi.vip/api/packages/hughboi/terraform/state/proxmox"
#     lock_address   = "https://gitea.hughboi.vip/api/packages/hughboi/terraform/state/proxmox/lock"
#     unlock_address = "https://gitea.hughboi.vip/api/packages/hughboi/terraform/state/proxmox/lock"
#     username       = "hughboi"
#     password       = "<gitea-api-token>"   # store in env: TF_HTTP_PASSWORD
#     lock_method    = "POST"
#     unlock_method  = "DELETE"
#   }
# }
#
# Option B is the simplest for a self-hosted homelab — it uses Gitea you already run.
# Set TF_HTTP_PASSWORD=<token> in your shell or pass_store/Vaultwarden before running tf.
#
# ── Current state: local backend (default) ───────────────────────────────────
#
# Uncomment one of the options above to migrate. After switching:
#   terraform init -migrate-state
# This copies your existing local state to the new backend.
#
# IMPORTANT: add terraform.tfstate and terraform.tfstate.backup to .gitignore
# (already done) — never commit state files.

# MongoDB Atlas Project
resource "mongodbatlas_project" "main" {
  org_id = var.mongodb_atlas_organization_id
  name   = "${var.project_name}-mongodb"

  # Tags
  tags = merge(
    var.tags,
    {
      Name    = "${var.project_name}-mongodb"
      Project = var.project_name
    }
  )
}

# MongoDB Atlas Cluster (M0 Free Tier with 3-node replica set)
resource "mongodbatlas_cluster" "main" {
  project_id              = mongodbatlas_project.main.id
  name                    = var.cluster_name

  # M0 Free Tier uses TENANT provider (multi-tenant shared deployment)
  # with backing AWS provider
  provider_name           = "TENANT"
  backing_provider_name   = var.cloud_provider  # AWS
  provider_region_name    = var.region
  provider_instance_size_name = var.cluster_tier  # M0

  # IMPORTANT: M0 clusters have limited configurability
  # Many settings (mongo_db_major_version, auto_scaling, backup, etc.)
  # cannot be changed after creation via API. They are set at creation time
  # and managed through MongoDB Atlas console.

  # Note: Do NOT add settings like:
  # - mongo_db_major_version (set to 4.4 during creation, can't change via API)
  # - auto_scaling_disk_gb_enabled (not applicable to M0)
  # - backup_enabled (M0 doesn't support backups)
  # - pit_enabled (M0 doesn't support PITR)
  # - termination_protection_enabled (can't be changed via API for M0)
  #
  # These would cause "TENANT_CLUSTER_UPDATE_UNSUPPORTED" errors

  depends_on = [mongodbatlas_project.main]
}

# Database User for the space2study application
resource "mongodbatlas_database_user" "main" {
  project_id         = mongodbatlas_project.main.id
  auth_database_name = "admin"
  username           = var.database_username
  password           = var.database_password

  # Database user roles - readWrite access to the application database
  # Note: dbOwner is not available for M0 free tier, use readWrite instead
  roles {
    database_name = var.database_name
    role_name     = "readWrite"
  }

  depends_on = [mongodbatlas_cluster.main]
}

# IP Access List Entries - CIDR blocks
resource "mongodbatlas_project_ip_access_list" "main" {
  for_each = { for entry in var.ip_allowlist_entries : entry.cidr_block => entry }

  project_id = mongodbatlas_project.main.id
  cidr_block = each.value.cidr_block
  comment    = each.value.description
}

# IP Access List Entries - NAT Elastic IPs (individual IPs)
# Using count instead of for_each to handle dynamic IPs from VPC module
# for_each cannot work with apply-time unknown values, but count can use length()
resource "mongodbatlas_project_ip_access_list" "nat_elastic_ips" {
  count = length(var.nat_elastic_ips)

  project_id = mongodbatlas_project.main.id
  ip_address = var.nat_elastic_ips[count.index]
  comment    = "NAT Gateway Elastic IP for outbound connections"
}


// environments/dev/post-apply.tf
// Automatically commit Terraform state to Git after successful apply
// This triggers the GitHub webhook which fires the Jenkins infrastructure-trigger pipeline

// Create a bash script file for git operations
resource "local_file" "commit_script" {
  filename = "${path.module}/commit-terraform-state.sh"
  content = <<-SCRIPT
#!/bin/bash
set +e

echo ""
echo "================================================"
echo "📝 [$(date '+%Y-%m-%d %H:%M:%S')] Committing infrastructure state to Git..."
echo "================================================"

# Navigate to repo root
cd "./../.." || exit 1

# Configure git
git config user.email "terraform@space2study.pp.ua" 2>/dev/null || git config --global user.email "terraform@space2study.pp.ua"
git config user.name "Terraform Automation" 2>/dev/null || git config --global user.name "Terraform Automation"
echo "✓ Git config set"

# Save original branch to restore later
ORIGINAL_BRANCH=$(git rev-parse --abbrev-ref HEAD)
echo "Original branch: $ORIGINAL_BRANCH"

# Switch to or create terraform-state branch
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
echo "Current branch: $CURRENT_BRANCH"

if [ "$CURRENT_BRANCH" != "terraform-state" ]; then
  echo "Switching to 'terraform-state' branch..."
  if git rev-parse --verify terraform-state >/dev/null 2>&1; then
    echo "  → Local branch 'terraform-state' found, checking out..."
    git checkout terraform-state
  elif git ls-remote --exit-code --heads origin terraform-state >/dev/null 2>&1; then
    echo "  → Remote branch 'origin/terraform-state' found, creating local tracking branch..."
    git checkout -b terraform-state --track origin/terraform-state
  else
    echo "  → Creating new local branch 'terraform-state' (first push will create remote)..."
    git checkout -b terraform-state
  fi
  # Update CURRENT_BRANCH after checkout
  CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
  echo "Switched to: $CURRENT_BRANCH"
fi

# Wait for Jenkins to be accessible via public domain (for GitHub webhook)
echo ""
echo "⏳ Waiting for Jenkins to be ready at jenkins.space2study.pp.ua..."
JENKINS_URL="https://jenkins.space2study.pp.ua/login"
MAX_ATTEMPTS=120  # ~5 minutes with 5-second intervals
ATTEMPT=0
JENKINS_HEALTHY=false

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
  ATTEMPT=$((ATTEMPT + 1))

  # Check if Jenkins login page is accessible (GitHub webhook endpoint needs this)
  HTTP_CODE=$(curl -s -o /dev/null -w '%%{http_code}' -m 5 "$JENKINS_URL" 2>/dev/null || echo "000")

  # Accept 200, 403 (Jenkins is up but needs auth), or any 3xx redirect
  if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "403" ] || [ "$${HTTP_CODE:0:1}" = "3" ]; then
    echo "✅ Jenkins is ready (HTTP $HTTP_CODE)"
    JENKINS_HEALTHY=true
    break
  else
    REMAINING=$((MAX_ATTEMPTS - ATTEMPT))
    if [ $((ATTEMPT % 6)) -eq 0 ]; then
      echo "⏳ Waiting for Jenkins... HTTP $HTTP_CODE ($REMAINING attempts left, ~$((REMAINING * 5))s)"
    fi
    sleep 5
  fi
done

if [ "$JENKINS_HEALTHY" = false ]; then
  echo "⚠️  Jenkins not accessible at jenkins.space2study.pp.ua after $(($MAX_ATTEMPTS * 5)) seconds"
  echo "   GitHub webhook may not be received. Continuing anyway..."
  echo ""
fi

# Create a simple timestamp trigger file (avoids terraform output complexity)
echo "Creating trigger file..."
TRIGGER_FILE=".terraform-apply-trigger"
cat > "$TRIGGER_FILE" <<-TRIGGER
{
  "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "hostname": "$(hostname)",
  "user": "$(whoami)",
  "jenkins_health_check": "$JENKINS_HEALTHY"
}
TRIGGER

# Stage the trigger file
echo "Staging trigger file..."
git add "$TRIGGER_FILE" || true

# Check if there are changes to commit
if git diff --cached --quiet; then
    echo "ℹ️  No infrastructure output changes to commit"
    exit 0
fi

# Create meaningful commit message
COMMIT_MSG="[Terraform] Applied at $(date -u '+%Y-%m-%d %H:%M:%S UTC')"

echo "Committing infrastructure outputs..."
git commit -m "$COMMIT_MSG" || exit 1
echo "✓ Commit created"

echo "Pushing to GitHub with upstream tracking..."
git push -u origin $CURRENT_BRANCH || exit 1
echo "✓ Push successful"

# Return to original branch
echo ""
echo "Returning to original branch: $ORIGINAL_BRANCH"
git checkout $ORIGINAL_BRANCH
echo "✓ Switched back to $ORIGINAL_BRANCH"

echo ""
echo "================================================"
echo "✅ Trigger file committed and pushed!"
echo "================================================"
echo "State remains secure in S3 + DynamoDB"
echo ""
echo "GitHub webhook will now trigger:"
echo "  1. infrastructure-trigger pipeline starts"
echo "  2. Waits 60 seconds for Jenkins initialization"
echo "  3. Triggers deploy-backend-k3s pipeline"
echo "  4. Triggers deploy-frontend-k3s pipeline"
echo ""

SCRIPT
}

resource "null_resource" "commit_infrastructure_state" {
  depends_on = [
    module.ec2,
    module.k3s_cluster,
    module.route53,
    module.alb,
    module.cloudflare,
    local_file.commit_script
  ]

  triggers = {
    jenkins_id    = module.ec2.jenkins_instance_id
    k3s_master_id = module.k3s_cluster.master_instance_id
    alb_dns       = module.alb.alb_dns_name
    always_run    = timestamp()
  }

  provisioner "local-exec" {
    command = "bash ${local_file.commit_script.filename}"
  }
}

# Clean up the commit script after execution
resource "null_resource" "cleanup_commit_script" {
  depends_on = [null_resource.commit_infrastructure_state]

  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    command = "sleep 2 && rm -f ${local_file.commit_script.filename}"
  }

  provisioner "local-exec" {
    command = "rm -f ./commit-terraform-state.sh"
    when    = destroy
  }
}

# Output helpful information about the webhook trigger
output "gitops_webhook_info" {
  description = "Information about GitOps webhook trigger"
  value = {
    status          = "GitOps with GitHub webhook enabled"
    trigger_pipeline = "infrastructure-trigger"
    trigger_branch   = "terraform-state"
    outputs_file    = "environments/dev/infra-outputs.json"
    state_backend   = "S3 + DynamoDB (secure, not in Git)"
    backend_pipeline  = "deploy-backend-k3s"
    frontend_pipeline = "deploy-frontend-k3s"
    jenkins_url      = "http://jenkins.space2study.pp.ua"
  }
}

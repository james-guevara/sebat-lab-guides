# Minimal AWS Batch Terraform example

This sanitized example creates a small Spot-backed development compute environment, job
queue, launch template, and hello-world job definition. It uses an existing subnet and
security group. It does not create a VPC, S3 bucket, ECR repository, FSx filesystem, or
production IAM policy.

Copy the example values, then review the plan:

```bash
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform fmt -check
terraform validate
terraform plan -out=change.tfplan
terraform show change.tfplan
```

Applying creates resources and can incur charges. Submit only a one-job smoke test before
raising `max_vcpus`. Adapt the IAM role and container image before using private data.

resource "aws_launch_template" "batch" {
  name_prefix = "${var.project_name}-"

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      encrypted   = true
      volume_size = 100
      volume_type = "gp3"
    }
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }
}

resource "aws_batch_compute_environment" "spot" {
  compute_environment_name = "${var.project_name}-spot"
  type                     = "MANAGED"

  compute_resources {
    type                = "SPOT"
    allocation_strategy = "SPOT_CAPACITY_OPTIMIZED"
    min_vcpus           = 0
    desired_vcpus       = 0
    max_vcpus           = var.max_vcpus
    instance_role       = aws_iam_instance_profile.ecs_instance.arn
    spot_iam_fleet_role = aws_iam_role.spot_fleet.arn
    instance_type       = var.instance_types
    subnets             = var.subnet_ids
    security_group_ids  = var.security_group_ids

    ec2_configuration {
      image_type = "ECS_AL2023"
    }

    launch_template {
      launch_template_id = aws_launch_template.batch.id
      version            = "$Latest"
    }
  }
}

resource "aws_batch_job_queue" "development" {
  name     = "${var.project_name}-queue"
  state    = "ENABLED"
  priority = 1

  compute_environment_order {
    order               = 1
    compute_environment = aws_batch_compute_environment.spot.arn
  }
}

resource "aws_batch_job_definition" "hello" {
  name = "${var.project_name}-hello"
  type = "container"

  platform_capabilities = ["EC2"]

  container_properties = jsonencode({
    image   = "public.ecr.aws/docker/library/alpine:3.20"
    command = ["sh", "-c", "echo Batch smoke test completed"]
    resourceRequirements = [
      { type = "VCPU", value = "1" },
      { type = "MEMORY", value = "512" }
    ]
    readonlyRootFilesystem = true
  })
}

output "job_queue" {
  value = aws_batch_job_queue.development.name
}

output "hello_job_definition" {
  value = aws_batch_job_definition.hello.arn
}

output "submit_smoke_test" {
  value = "aws batch submit-job --job-name hello --job-queue ${aws_batch_job_queue.development.name} --job-definition ${aws_batch_job_definition.hello.arn}"
}

output "input_bucket" {
  value = aws_s3_bucket.input.bucket
}

output "output_bucket" {
  value = aws_s3_bucket.output.bucket
}

output "lambda_function_name" {
  value = aws_lambda_function.converter.function_name
}

output "log_group" {
  value = aws_cloudwatch_log_group.lambda.name
}
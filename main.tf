data "aws_caller_identity" "current" {}

locals {
  suffix        = "${data.aws_caller_identity.current.account_id}-${var.aws_region}"
  input_bucket  = "${var.project_name}-input-${local.suffix}"
  output_bucket = "${var.project_name}-output-${local.suffix}"
  function_name = "${var.project_name}-converter"
}

# ---------- 1. S3 bucket for JPEG uploads ----------
resource "aws_s3_bucket" "input" {
  bucket        = local.input_bucket
  force_destroy = var.force_destroy_buckets
}

resource "aws_s3_bucket_public_access_block" "input" {
  bucket                  = aws_s3_bucket.input.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "input" {
  bucket = aws_s3_bucket.input.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ---------- 3. S3 bucket for PDF output ----------
resource "aws_s3_bucket" "output" {
  bucket        = local.output_bucket
  force_destroy = var.force_destroy_buckets
}

resource "aws_s3_bucket_public_access_block" "output" {
  bucket                  = aws_s3_bucket.output.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "output" {
  bucket = aws_s3_bucket.output.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ---------- IAM role for Lambda ----------
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${local.function_name}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "lambda_s3" {
  statement {
    sid       = "ReadJpegUploads"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.input.arn}/*"]
  }
  statement {
    sid       = "WritePdfOutput"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.output.arn}/*"]
  }
}

resource "aws_iam_role_policy" "lambda_s3" {
  name   = "s3-access"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_s3.json
}

# ---------- 2. Lambda function ----------
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/app.py"
  output_path = "${path.module}/lambda.zip"
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "converter" {
  function_name    = local.function_name
  role             = aws_iam_role.lambda.arn
  runtime          = "python3.12"
  architectures    = ["arm64"]
  handler          = "app.lambda_handler"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  memory_size      = var.lambda_memory_mb
  timeout          = var.lambda_timeout_seconds

  environment {
    variables = {
      OUTPUT_BUCKET = aws_s3_bucket.output.bucket
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_logs,
    aws_cloudwatch_log_group.lambda,
  ]
}

# ---------- S3 -> Lambda trigger ----------
resource "aws_lambda_permission" "allow_s3" {
  statement_id   = "AllowS3Invoke"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.converter.function_name
  principal      = "s3.amazonaws.com"
  source_arn     = aws_s3_bucket.input.arn
  source_account = data.aws_caller_identity.current.account_id
}

resource "aws_s3_bucket_notification" "input_upload" {
  bucket = aws_s3_bucket.input.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.converter.arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".jpg"
  }

  lambda_function {
    lambda_function_arn = aws_lambda_function.converter.arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".jpeg"
  }

  depends_on = [aws_lambda_permission.allow_s3]
}
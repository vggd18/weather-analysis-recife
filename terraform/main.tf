provider "aws" {
  region = "us-east-2"
}

resource "aws_s3_bucket" "data_lake" {
  bucket = "weather-data-lake-bucket"

  tags = {
    Project = "WeatherDataLake",
    Name    = "Weather Data Lake Bucket",
    owner   = "DataEngineeringTeam"
  }
}

resource "aws_iam_role" "lambda_execution_role" {
  assume_role_policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Action": "sts:AssumeRole",
        "Principal": {
          "Service": "lambda.amazonaws.com"
        },
        "Effect": "Allow",
        "Sid": ""
      }
    ]
  })
}

resource "aws_iam_policy" "lambda_policy" {
  name = "weather_lambda_policy"
  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement" = [
      {
        "Effect": "Allow",
        "Action": [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        "Resource": "arn:aws:logs:*:*:*"
      },
      {      
        "Effect": "Allow",
        "Action": ["s3:PutObject"],
        "Resource": ["${aws_s3_bucket.data_lake.arn}/*"]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

data "archive_file" "lambda_zip" {
  type = "zip"
  source_dir  = "../build/lambda_package"
  output_path = "lambda_function_payload.zip"
}

resource "aws_lambda_function" "weather_ingestion_lambda" {
  function_name     = "weather_ingestion_recife"
  role              = aws_iam_role.lambda_execution_role.arn
  handler           = "index.lambda_handler"
  runtime           = "python3.9"
  filename          = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
}


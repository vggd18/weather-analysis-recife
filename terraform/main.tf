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

variable "weather_api_key" {
  type      = string
  sensitive = true
}

resource "aws_lambda_function" "weather_ingestion_lambda" {
  function_name     = "weather_ingestion_recife"
  role              = aws_iam_role.lambda_execution_role.arn
  handler           = "index.lambda_handler"
  runtime           = "python3.9"
  filename          = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  timeout           = 30

  environment {
    variables = {
      S3_BUCKET_NAME = aws_s3_bucket.data_lake.bucket
      WEATHER_API_KEY = var.weather_api_key
    }
  }
}

resource "aws_iam_role" "event_bridge_role" {
   assume_role_policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Action": "sts:AssumeRole",
        "Principal": {
          "Service": "scheduler.amazonaws.com"
        },
        "Effect": "Allow",
        "Sid": ""
      }
    ]
  })

}
resource "aws_iam_policy" "event_bridge_policy" {
  name    = "scheduler_lambda_invoke_policy"
  policy  = jsonencode({
    "Version": "2012-10-17",
    "Statement" = [
      {      
        "Effect": "Allow",
        "Action": ["lambda:InvokeFunction"],
        "Resource": ["${aws_lambda_function.weather_ingestion_lambda.arn}/*"]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "event_bridge_policy_attachment" {
  role       = aws_iam_role.event_bridge_role.name
  policy_arn = aws_iam_policy.event_bridge_policy.arn
}

resource "aws_scheduler_schedule" "weather_data_schedule" {
  name = "trigger_weather_lambda"
  flexible_time_window {
    mode = "OFF"
  }
  schedule_expression = "rate(15 minute)"
  target {
    arn      = aws_lambda_function.weather_ingestion_lambda.arn
    role_arn = aws_iam_role.event_bridge_role.arn
  }

}
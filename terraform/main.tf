provider "aws" {
  region = "us-east-2"
}

##### S3 Config #####
resource "aws_s3_bucket" "data_lake" {
  bucket = "weather-data-lake-bucket"

  tags = {
    Project = "WeatherDataLake",
    Name    = "Weather Data Lake Bucket",
    owner   = "DataEngineeringTeam"
  }
}

##### Lambda Config #####
resource "aws_iam_role" "lambda_execution_role" {
  assume_role_policy = jsonencode({
    "Version" = "2012-10-17",
    "Statement" = [
      {
        "Action" = "sts:AssumeRole",
        "Principal" = {
          "Service" = "lambda.amazonaws.com"
        },
        "Effect" = "Allow",
        "Sid" = ""
      }
    ]
  })
}

resource "aws_iam_policy" "lambda_policy" {
  name   = "weather_lambda_policy"
  policy = jsonencode({
    "Version" = "2012-10-17",
    "Statement" = [
      {
        "Effect" = "Allow",
        "Action" = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        "Resource" = "arn:aws:logs:*:*:*"
      },
      {      
        "Effect"   = "Allow",
        "Action"   = ["s3:PutObject"],
        "Resource" = ["${aws_s3_bucket.data_lake.arn}/*"]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

data "archive_file" "lambda_zip" {
  type        = "zip"
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
  source_code_hash  = data.archive_file.lambda_zip.output_base64sha256
  timeout           = 30

  environment {
    variables = {
      S3_BUCKET_NAME = aws_s3_bucket.data_lake.bucket
      WEATHER_API_KEY = var.weather_api_key
    }
  }
}

##### Evend Bridge Config #####
resource "aws_iam_role" "event_bridge_role" {
   assume_role_policy = jsonencode({
    "Version" = "2012-10-17",
    "Statement" = [
      {
        "Action" = "sts:AssumeRole",
        "Principal" = {
          "Service" = "scheduler.amazonaws.com"
        },
        "Effect" = "Allow",
        "Sid" = ""
      }
    ]
  })

}
resource "aws_iam_policy" "event_bridge_policy" {
  name    = "scheduler_lambda_invoke_policy"
  policy  = jsonencode({
    "Version" = "2012-10-17",
    "Statement" = [
      {      
        "Effect" = "Allow",
        "Action" = ["lambda:InvokeFunction"],
        "Resource" = [aws_lambda_function.weather_ingestion_lambda.arn]
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

##### Glue Congfig #####
resource "aws_iam_role" "glue_role" {
  name = "weather_glue_role"
  assume_role_policy = jsonencode({
    "Version" = "2012-10-17",
    "Statement" = [
      {
        "Action" = "sts:AssumeRole",
        "Principal" = {
          "Service" = "glue.amazonaws.com"
        },
        "Effect" = "Allow",
        "Sid" = ""
      }
    ]
  })
}
resource "aws_iam_policy" "glue_policy" {
  name = "weather_glue_policy"
  policy = jsonencode({
    "Version" = "2012-10-17",
    "Statement" = [
      {
        "Effect" = "Allow",
        "Action" = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        "Resource" = "arn:aws:logs:*:*:*"
      }, 
      {
        "Effect"   = "Allow",
        "Action"   = "s3:ListBucket", 
        "Resource" = aws_s3_bucket.data_lake.arn
      }, 
      {
        "Effect" = "Allow",
        "Action" = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ],
        "Resource" = ["${aws_s3_bucket.data_lake.arn}/*"]
      }, 
      { # --- Bloco ÚNICO para Permissões de Sessão/Notebook ---
        "Effect": "Allow",
        "Action": [
          "glue:CreateSession", "glue:GetSession", "glue:DeleteSession", 
          "glue:ListSessions", "glue:RunStatement", "glue:TagResource",
          "glue:GetStatement",
          "glue:CancelStatement",
          "ec2:DescribeVpcEndpoints", "ec2:DescribeRouteTables",
          "ec2:CreateNetworkInterface", "ec2:DeleteNetworkInterface",
          "ec2:DescribeNetworkInterfaces", "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets", "ec2:DescribeVpcAttribute",
          "codewhisperer:GenerateRecommendations" 
        ],
        "Resource": "*" 
      },
      {
        "Effect"   = "Allow",
        "Action"   = "iam:PassRole",
        "Resource" = aws_iam_role.glue_role.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "glue_policy_attachment" {
  role       = aws_iam_role.glue_role.name
  policy_arn = aws_iam_policy.glue_policy.arn
}

resource "aws_s3_object" "glue_etl_script" {
  bucket = aws_s3_bucket.data_lake.id
  key    = "jobs/weather_transform.py"
  source = "../src/glue_transform/transform_script.py"

  etag   = filemd5("../src/glue_transform/transform_script.py")
}

resource "aws_glue_job" "weather_job" {
  name     = "weather_etl_job"
  role_arn = aws_iam_role.glue_role.arn
  timeout  = 2881
  command {
    script_location = "s3://${aws_s3_bucket.data_lake.bucket}/jobs/weather_transform.py"
    name            = "glueetl"
    python_version  = "3"
  }
  default_arguments = {
    "--S3_BUCKET_NAME" = aws_s3_bucket.data_lake.bucket  
  }
}

resource "aws_glue_trigger" "weather_job_trigger" {
  name     = "weather_job_trigger"
  type     = "SCHEDULED"
  schedule = "cron(0 0 * * ? *)"

  actions {
    job_name = aws_glue_job.weather_job.name
  }
}

##### Glue Crawler #####
resource "aws_iam_role" "glue_crawler_role" {
  name = "weather_glue_crawler_role"
  assume_role_policy = jsonencode({
    "Version" = "2012-10-17",
    "Statement" = [
      {
        "Action" = "sts:AssumeRole",
        "Principal" = {
          "Service" = "glue.amazonaws.com"
        },
        "Effect" = "Allow",
        "Sid" = ""
      }
    ]
  })
}

resource "aws_iam_policy" "glue_crawler_policy" {
  name   = "weather_glue_crawler_policy"
  policy = jsonencode({
    "Version" = "2012-10-17",
    "Statement" = [
      {
        "Effect"   = "Allow",
        "Action"   = "s3:ListBucket", 
        "Resource" = aws_s3_bucket.data_lake.arn
      }, 
      {
        "Effect" = "Allow",
        "Action" = [
          "s3:GetObject",
        ],
        "Resource" = ["${aws_s3_bucket.data_lake.arn}/*"]
      },
      {
        "Effect": "Allow",
        "Action": [
          # Permissões para gerenciar o Banco de Dados
          "glue:CreateDatabase",
          "glue:GetDatabase",
          "glue:GetDatabases",
          "glue:UpdateDatabase",
          "glue:DeleteDatabase",
          
          # Permissões para gerenciar a Tabela
          "glue:CreateTable",
          "glue:UpdateTable",
          "glue:GetTable",
          "glue:GetTables",
          "glue:DeleteTable",
          
          # Permissões para gerenciar as Partições
          "glue:BatchGetPartition",
          "glue:GetPartition",
          "glue:GetPartitions",
          "glue:CreatePartition",
          "glue:UpdatePartition",
          "glue:DeletePartition",
          "glue:BatchCreatePartition",
          "glue:BatchDeletePartition"
        ],
        "Resource": "*"
      },
      {
        "Effect" = "Allow",
        "Action" = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        "Resource" = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "glue_crawler_policy_attachment" {
  role       = aws_iam_role.glue_crawler_role.name
  policy_arn = aws_iam_policy.glue_crawler_policy.arn
}

resource "aws_glue_crawler" "weather_crawler" {
  database_name = "weather_data_db"
  schedule      = "cron(0 1 * * ? *)"
  name          = "weather_data_crawler"
  role          = aws_iam_role.glue_crawler_role.arn
  s3_target {
    path = "s3://${aws_s3_bucket.data_lake.bucket}/curated/weather/"
  }
}

##### Athena Config #####
resource "aws_athena_workgroup" "weather_athena_workgroup" {
  name = "weather_athena_workgroup"
  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true
    result_configuration {
      output_location = "s3://${aws_s3_bucket.data_lake.bucket}/athena/results/"
    }
  }
}


resource "aws_athena_named_query" "daily_summary" {
  name      = "daily_weather_summary"
  workgroup = aws_athena_workgroup.weather_athena_workgroup.name
  database  = aws_glue_crawler.weather_crawler.database_name
  query     = <<-EOF
    SELECT
      "year",
      "month",
      "day",
      CAST(CONCAT("year", '-', "month", '-', "day") AS date) AS "report_date",
      ROUND(AVG(main_temp), 2) AS "avg_temp_celsius",
      ROUND(MAX(main_temp_max), 2) AS "max_temp_celsius",
      ROUND(MIN(main_temp_min), 2) AS "min_temp_celsius",
      ROUND(AVG(main_feels_like), 2) AS "avg_feels_like",      
      ROUND(AVG(main_humidity), 1) AS "avg_humidity_percent",
      ROUND(MAX(wind_speed), 1) AS "max_wind_speed_ms",
      ROUND(AVG(clouds_all), 1) AS "avg_cloudiness_percent"  
    FROM weather
    GROUP BY "year", "month", "day"
    ORDER BY "year", "month", "day" DESC;
  EOF
}

resource "aws_athena_named_query" "day_vs_night_comparison" {
  name      = "day_vs_night_metrics"
  workgroup = aws_athena_workgroup.weather_athena_workgroup.name
  database  = aws_glue_crawler.weather_crawler.database_name
  query     = <<-EOF
    WITH classified_readings AS (
      SELECT
        *,
        CASE 
          WHEN dt > sys_sunrise_utc AND dt < sys_sunset_utc THEN 'Dia'
          ELSE 'Noite'
        END AS "period_of_day"
      FROM weather
    )
    SELECT
      period_of_day,
      COUNT(*) AS "reading_count",
      ROUND(AVG(main_temp), 2) AS "avg_temp",
      ROUND(AVG(main_humidity), 1) AS "avg_humidity",
      ROUND(AVG(wind_speed), 1) AS "avg_wind_speed"
    FROM classified_readings
    GROUP BY period_of_day;
  EOF
}

resource "aws_athena_named_query" "hourly_temp_delta" {
  name      = "hourly_temperature_delta"
  workgroup = aws_athena_workgroup.weather_athena_workgroup.name
  database  = aws_glue_crawler.weather_crawler.database_name
  query     = <<-EOF
    WITH hourly_avg AS (
      SELECT
        date_trunc('hour', from_unixtime(dt)) AS "hour_timestamp",            
        ROUND(AVG(main_temp), 2) AS "avg_hourly_temp"
      FROM weather
      GROUP BY 1
    )
    SELECT
      hour_timestamp,
      avg_hourly_temp,
      LAG(avg_hourly_temp, 1) OVER (ORDER BY hour_timestamp) AS "previous_hour_temp",        
      ROUND(avg_hourly_temp - (LAG(avg_hourly_temp, 1) OVER (ORDER BY hour_timestamp)), 2) AS "hourly_temp_change_delta"    
    FROM hourly_avg
    ORDER BY hour_timestamp DESC;
  EOF
}
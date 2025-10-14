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
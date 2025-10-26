import os
import requests
from dotenv import load_dotenv
import boto3
import json
from datetime import datetime

def lambda_handler(event, context):
  ##### ENVIRONMENT VARIABLES #####
  load_dotenv()
  s3_bucket_name = os.getenv("S3_BUCKET_NAME")
  weather_api_key = os.getenv("WEATHER_API_KEY") 

  ##### WEATHER API REQUEST #####
  city = "Recife,BR"
  parameters = {
    "q": city,
    "appid": weather_api_key,
    "units": "metric"
  }
  response = requests.get(
    f"https://api.openweathermap.org/data/2.5/weather",
    params=parameters
  )

  data = response.json()
  json_data = json.dumps(data, indent=2)

  now = datetime.now()
  file_key = f'raw/weather/{now.strftime("%Y/%m/%d/%H-%M-%S.json")}' 

  s3 = boto3.client('s3')
  s3.put_object(
      Bucket=s3_bucket_name,
      Key=file_key,
      Body=json_data
  )

  return {
      'statusCode': 200,
      'body': json.dumps(f'File {file_key} saved to {s3_bucket_name}!')
  }
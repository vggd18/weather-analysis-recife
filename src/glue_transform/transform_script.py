import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from awsglue.context import GlueContext
from awsglue.job import Job  
from pyspark.context import SparkContext
from pyspark.sql.functions import col, explode

args_list = ['JOB_NAME', 'S3_BUCKET_NAME']
args = getResolvedOptions(sys.argv, args_list)

glueContext = GlueContext(SparkContext.getOrCreate())
spark = glueContext.spark_session

job = Job(glueContext)
job.init(args['JOB_NAME'], args)

s3_bucket = args['S3_BUCKET_NAME']

input_path = f"s3://{s3_bucket}/raw/weather/*/*/*/*.json"
output_path =f"s3://{s3_bucket}/curated/weather"

print(f"Iniciando job. Lendo de: {input_path}")
raw_df = spark.read.format("json").option("multiline", "true").load(input_path)

print("Aplicando transformações (explode, select, flatten)...")
exploded_df = raw_df.select("*", explode(raw_df.weather).alias("weather_element"))

transformed_df = exploded_df.select(
    # --- Identifiers & Timestamps ---
    col("id"),
    col("name"),
    col("dt"),
    col("timezone").alias("timestamp_utc"),

    # --- Coordinates --- 
    col("coord.lat").alias("coord_lat"),
    col("coord.lon").alias("coord_lon"),

    # --- Main Weather Metrics ---
    col("main.feels_like").alias("main_feels_like"),
    col("main.grnd_level").alias("main_grnd_level"),
    col("main.humidity").alias("main_humidity"),
    col("main.pressure").alias("main_pressure"),
    col("main.sea_level").alias("main_sea_level"),
    col("main.temp").alias("main_temp"),
    col("main.temp_max").alias("main_temp_max"),
    col("main.temp_min").alias("main_temp_min"),

    # --- Wind ---
    col("wind.speed").alias("wind_speed"),
    col("wind.deg").alias("wind_deg"),
    col("wind.gust").alias("wind_gust_mps"),

    # --- Clouds & Visibility ---
    col("clouds.all").alias("clouds_all"),
    col("visibility"),

    # --- Weather Condition ---
    col("weather_element.description").alias("weather_element_description"),
    col("weather_element.icon").alias("weather_element_icon"),
    col("weather_element.id").alias("weather_element_id"),
    col("weather_element.main").alias("weather_element_main"),
    
    # --- System Info ---
    col("sys.id").alias("sys_id"),
    col("sys.type").alias("sys_type"),
    col("sys.country").alias("country_code"),
    col("sys.sunrise").alias("sys_sunrise_utc"),
    col("sys.sunset").alias("sys_sunset_utc"),
    
    # --- Other Info ---
    col("cod"),
    col("base")
)

print("Transformação concluída. Schema final:")
transformed_df.printSchema()

print(f"Escrevendo DataFrame transformado em Parquet para: {output_path}")
transformed_df.write.format("parquet").mode("overwrite").save(output_path)
print("Escrita concluída.")

# --- 6. Finalização (Salva o Bookmark) ---
print("Job concluído. Salvando bookmarks.")
job.commit()
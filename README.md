# Pipeline de Lakehouse Serverless para Análise Climática na AWS

## 🎯 Objetivo

Construir um data lakehouse confiável e 100% serverless na AWS, provisionado inteiramente com Terraform (IaC). O pipeline automatiza o ciclo completo de ETLT (Extração, Carga, Transformação e Orquestração) para capturar, processar e analisar dados climáticos em tempo real da cidade do Recife.

## 🏛️ Arquitetura

O pipeline funciona em cinco estágios principais, todos orquestrados e provisionados automaticamente:

1.  **Ingestão (Extract):** Um **Amazon EventBridge Scheduler** aciona uma **AWS Lambda** (Python/Boto3) a cada 15 minutos. A Lambda consome a API OpenWeatherMap e salva os dados brutos (JSON) na Camada Raw do S3, particionando por `ano/mês/dia`.
2.  **Transformação (Transform):** Um **AWS Glue Job (PySpark)**, disparado diariamente por um **AWS Glue Trigger**, lê os JSONs da Camada Raw (`multiline=true`). O script aplica transformações complexas, incluindo achatamento de schema (`explode`, `select`), limpeza otimizada de colunas nulas (O(N)), `dropDuplicates`, e cria colunas de partição (`year`, `month`, `day`).
3.  **Carga (Load):** O mesmo Glue Job salva o DataFrame limpo em formato **Parquet** na Camada Curated (Processed) do S3, usando as novas colunas para particionamento.
4.  **Catálogo (Catalog):** Um **AWS Glue Crawler**, agendado para rodar diariamente, escaneia a Camada Curated, detecta o schema dos Parquets e cria/atualiza uma tabela (`weather`) no **AWS Glue Data Catalog**.
5.  **Análise (Query):** Um **Amazon Athena Workgroup** está configurado para salvar resultados de consulta no S3. Múltiplas **Consultas Salvas (Named Queries)** (com CTEs e Window Functions) são provisionadas via Terraform para expor análises prontas para consumo em ferramentas de BI (como o QuickSight).

## ⚙️ Tecnologias Utilizadas

* **Infraestrutura como Código (IaC):** Terraform
* **Nuvem (AWS):**
    * **Armazenamento:** Amazon S3 (Data Lake)
    * **Ingestão:** AWS Lambda (Python/Boto3)
    * **Transformação:** AWS Glue Job (PySpark)
    * **Orquestração:** Amazon EventBridge Scheduler, AWS Glue Trigger
    * **Catálogo de Dados:** AWS Glue Crawler, AWS Glue Data Catalog
    * **Análise SQL:** Amazon Athena (Named Queries)
    * **Permissões:** AWS IAM (Roles e Policies)
* **Linguagens:** Python (Boto3, PySpark), SQL (Athena/Trino), HCL (Terraform)

## 🚀 Como Executar o Deploy

### Pré-requisitos
* Uma conta na AWS com o [AWS CLI](https://aws.amazon.com/cli/) instalado e configurado.
* [Terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli) instalado.
* Python 3.9+ e Pip instalados.

### Passos para o Deploy
1.  Clone este repositório.
2.  Na raiz do projeto, crie um arquivo `.env` a partir do `.env.example` e preencha com sua `WEATHER_API_KEY`.
3.  **Construa o pacote de deploy da Lambda** com os seguintes comandos na raiz do projeto:
    ```bash
    # Limpa o build antigo e cria a estrutura de pastas
    rm -rf build/
    mkdir -p build/lambda_package

    # Copia o código-fonte para a pasta de build
    cp src/lambda_ingestion/index.py build/lambda_package/

    # Instala as dependências dentro da pasta de build
    pip install -r src/lambda_ingestion/requirements.txt -t build/lambda_package/
    ```
4.  Navegue até a pasta de infraestrutura:
    ```bash
    cd terraform
    ```
5.  Inicialize o Terraform e aplique a configuração (será necessário informar sua `weather_api_key` quando solicitado):
    ```bash
    terraform init
    terraform plan
    terraform apply
    ```
6.  **(Opcional) Bootstrap Manual:** Após o `apply`, vá ao console do AWS Glue, encontre o Crawler `weather_data_crawler` e clique em "Run" (Rodar) uma vez para catalogar os dados imediatamente.

## 📊 Consultas de Análise (Amazon Athena)

Após o deploy, as seguintes consultas estarão prontas e salvas no Amazon Athena, prontas para serem usadas pelo Amazon QuickSight:

* **`daily_weather_summary`**: Um resumo diário com `AVG`, `MAX`, `MIN` de temperatura, umidade e vento.
* **`day_vs_night_metrics`**: (Usa `CTE`) Compara as métricas médias de "Dia" vs. "Noite", com base nos horários de nascer e pôr do sol.
* **`hourly_temperature_delta`**: (Usa `CTE` e `Window Function LAG`) Calcula a variação de temperatura média de uma hora para a outra.
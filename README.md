# Análise de Condições Climáticas em Tempo Quase-Real no Recife

## 🎯 Objetivo

Construir um data lakehouse confiável e automatizado que armazena dados históricos de clima para a cidade do Recife, permitindo análises de tendências.

## 🏛️ Arquitetura

O pipeline de dados funciona da seguinte maneira:
1.  Um **Amazon EventBridge Scheduler** é disparado a cada 15 minutos, invocando uma função **AWS Lambda**.
2.  A função **Lambda** busca os dados de clima atuais da API do **OpenWeatherMap**.
3.  Os dados são salvos como um arquivo JSON em um bucket no **Amazon S3** (Camada Raw), particionados por `ano/mês/dia`.
4.  Um **AWS Glue Job** lê os JSONs da camada Raw, aplica transformações (achatamento de schema, seleção de colunas) e salva os dados limpos em formato **Parquet** na Camada Curated (ou Processed) do S3.
5.  Toda a infraestrutura (S3, IAM, Lambda, EventBridge, Glue) é provisionada via **Terraform**.

## ⚙️ Tecnologias Utilizadas

* **Nuvem:** AWS (S3, Lambda, IAM, EventBridge, Glue)
* * **IaC:** Terraform
* **Linguagem:** Python 3.9
* **Fonte de Dados:** OpenWeatherMap API

## 🚀 Como Executar

### Pré-requisitos
* Uma conta na AWS.
* [Terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli) instalado.
* [AWS CLI](https://aws.amazon.com/cli/) instalado e configurado com suas credenciais.
* Python 3.9+ e Pip instalados.

### Passos para Deploy
1.  Clone este repositório.
2.  Na raiz do projeto, crie um arquivo `.env` a partir do `.env.example` e preencha com suas chaves.
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
5.  Inicialize o Terraform e aplique a configuração:
    ```bash
    terraform init
    terraform plan
    terraform apply
    ```

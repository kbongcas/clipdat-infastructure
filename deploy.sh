RESOURCE_GROUP="clipdat" #change this in master
LOCATION="eastus"
STORAGE_ACCOUNT="clipdatsa" #change this in master
COSMOSDB_ACCOUNT="clipdatcsmdba"
COSMOSDB_NAME="clipdatcsmdb"
COSMOSDB_CONTAINER="clips"
QUEUE_NAME="clips"
BLOBCON_CLIPS_NAME="clips"
BLOBCON_CONVERTED_NAME="converted"
ENV_NAME="clipdat-env"

# creating resource group
az group create \
    --name $RESOURCE_GROUP \
    --location $LOCATION

# creating azure storage account
az storage account create \
    --name $STORAGE_ACCOUNT \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION \
    --sku Standard_LRS \
    --kind StorageV2 \
    --allow-blob-public-access true

# Get connection string from storage account
AZ_STORAGE_CON=$(az storage account show-connection-string \
     -g $RESOURCE_GROUP \
     --name $STORAGE_ACCOUNT \
     --out tsv)

# creating azure storage account container
az storage container create  \
    --account-name $STORAGE_ACCOUNT  \
    --name $BLOBCON_CLIPS_NAME

# creating azure storage account container
az storage container create  \
    --account-name $STORAGE_ACCOUNT  \
    --name $BLOBCON_CONVERTED_NAME

# setting Public read access for blobs only
az storage container set-permission \
    --account-name $STORAGE_ACCOUNT  \
    --name $BLOBCON_CONVERTED_NAME \
    --public-access blob \
    --connection-string $AZ_STORAGE_CON

# creating azure storage queue
az storage queue create \
    --name $QUEUE_NAME \
    --account-name $STORAGE_ACCOUNT \
    --connection-string $AZ_STORAGE_CON

# creating cosmosdb account
az cosmosdb create \
    --name $COSMOSDB_ACCOUNT \
    --capabilities EnableServerless \
    --resource-group $RESOURCE_GROUP \
    --default-consistency-level Eventual \
    --location regionName="$LOCATION"

# creating cosmosdb db
az cosmosdb sql database create \
    --account-name $COSMOSDB_ACCOUNT \
    --resource-group $RESOURCE_GROUP \
    --name $COSMOSDB_NAME

# creating cosmosdb db container
# -partion-key-path: double forward slash if using gitbash
az cosmosdb sql container create \
    --account-name $COSMOSDB_ACCOUNT \
    --resource-group $RESOURCE_GROUP \
    --database-name $COSMOSDB_NAME \
    --name $COSMOSDB_CONTAINER \
    --partition-key-path "//userId" 

# get cosmos db connection string
COSMOS_DB_CON=$(az cosmosdb keys list \
         -g $RESOURCE_GROUP \
         -n $COSMOSDB_ACCOUNT \
         --type connection-strings \
         --query connectionStrings[0].connectionString \
         --output tsv)

 
# deploy clips service using template
az deployment group create \
     --resource-group $RESOURCE_GROUP \
     --template-file clips-service-template.json \
     --parameters cosmosDbConnectionString=$COSMOS_DB_CON \
     --parameters cosmosDbCosmosDbId=$COSMOSDB_NAME \
     --parameters cosmosDbUsersContainerId=$COSMOSDB_CONTAINER \
     --parameters environmentName=$ENV_NAME \
     --parameters blobDbConnection=$AZ_STORAGE_CON \
     --parameters convertedContainerName=$BLOBCON_CONVERTED_NAME

CLIPS_SERVICE_ENDPOINT="https://"
CLIPS_SERVICE_ENDPOINT+=$(az containerapp ingress show \
         -g $RESOURCE_GROUP \
         -n clipsservice \
         --query fqdn \
         --output tsv)
CLIPS_SERVICE_ENDPOINT="/users"

# deploy converter using template
az deployment group create \
    --resource-group $RESOURCE_GROUP \
    --template-file clip-converter-template.json \
    --parameters queueConnection=$AZ_STORAGE_CON \
    --parameters queueName=$QUEUE_NAME \
    --parameters storageAccountName=$STORAGE_ACCOUNT \
    --parameters environmentName=$ENV_NAME \
    --parameters clipsServiceEndpoint=$CLIPS_SERVICE_ENDPOINT

 
# deploy uploader using template
az deployment group create \
    --resource-group $RESOURCE_GROUP \
    --template-file clip-uploader-template.json \
    --parameters connectionString=$AZ_STORAGE_CON \
    --parameters queueName=$QUEUE_NAME \
    --parameters blobContainerName=$BLOBCON_CLIPS_NAME \
    --parameters environmentName=$ENV_NAME \
    --parameters clipsServiceEndpoint=$CLIPS_SERVICE_ENDPOINT
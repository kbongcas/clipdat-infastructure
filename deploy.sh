RESOURCE_GROUP="clipdat"
LOCATION="eastus"
STORAGE_ACCOUNT="clipdatsa"
COSMOSDB_ACCOUNT="clipdatcsmdba"
COSMOSDB_NAME="clipdatcmsdb"
COSMOSDB_CONTAINER="userclips"
QUEUE="clips"
ENV_NAME="clipdat-env"
SHARE_NAME="convertershare"

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
    --kind StorageV2

az storage container create  \
    --account-name $STORAGE_ACCOUNT  \
    --name clips

az storage container create  \
    --account-name $STORAGE_ACCOUNT  \
    --name converted

#TODO - set converted container to anon access
#TODO - Added ephemeralstorage
CONNECTION_STRING=$(az storage account show-connection-string \
     -g $RESOURCE_GROUP \
     --name $STORAGE_ACCOUNT \
     --out tsv)

# creating azure storage queue
az storage queue create \
    --name $QUEUE \
    --account-name $STORAGE_ACCOUNT \
    --connection-string $CONNECTION_STRING

az cosmosdb create \
    --name $COSMOSDB_ACCOUNT \
    --capabilities EnableServerless \
    --resource-group $RESOURCE_GROUP \
    --default-consistency-level Eventual \
    --location regionName="$LOCATION" \

az cosmosdb sql database create \
    --account-name $COSMOSDB_ACCOUNT \
    --resource-group $RESOURCE_GROUP \
    --name $COSMOSDB_NAME \

az cosmosdb sql container create \
    --account-name $COSMOSDB_ACCOUNT \
    --resource-group $RESOURCE_GROUP \
    --database-name $COSMOSDB_NAME \
    --name $COSMOSDB_CONTAINER \
    --partition-key-path "//id" #< double forward slash if using gitbash

# deploy template
az deployment group create \
    --resource-group $RESOURCE_GROUP \
    --template-file clip-converter-template.json \
    --parameters queueConnection=$CONNECTION_STRING \
    --parameters queueName=$QUEUE \
    --parameters storageAccountName=$STORAGE_ACCOUNT \
    --parameters environmentName=$ENV_NAME

 COSMOS_DB_CONNECTION_STRING=$(az cosmosdb keys list \
         -g $RESOURCE_GROUP \
         -n $COSMOSDB_ACCOUNT \
         --type connection-strings \
         --query connectionStrings[0].connectionString \
         --output tsv)
 
echo $COSMOS_DB_CONNECTION_STRING
 
 az deployment group create \
     --resource-group $RESOURCE_GROUP \
     --template-file clips-service-template.json \
     --parameters cosmosDbConnectionString=$COSMOS_DB_CONNECTION_STRING \
     --parameters cosmosDbCosmosDbId=$COSMOSDB_NAME \
     --parameters cosmosDbUsersContainerId=$COSMOSDB_CONTAINER \
     --parameters environmentName=$ENV_NAME

az deployment group create \
    --resource-group $RESOURCE_GROUP \
    --template-file clip-uploader-template.json \
    --parameters connectionString=$CONNECTION_STRING \
    --parameters queueName=$QUEUE \
    --parameters blobContainerName="clips" \
    --parameters environmentName=$ENV_NAME
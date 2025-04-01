param tags object
param environmentName string

@description('Location for all resources.')
param location string = resourceGroup().location

@description('Abbreviated Names of the Azure Services that can be used as part of naming resource convention')
var abbrs = loadJsonContent('./abbreviations.json')

@description('Id of the user or app to assign application roles')
param principalId string = ''

param copyImages bool = true
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))

module storageAccount 'br/public:avm/res/storage/storage-account:0.14.3' = {
  name: 'storageAccountDeployment'

  params: {
    name: '${abbrs.storageStorageAccounts}${resourceToken}'
    tags: tags
    allowBlobPublicAccess: true //is a false here needed?
    defaultToOAuthAuthentication: true // Default to Entra ID Authentication
    supportsHttpsTrafficOnly: true
    kind: 'StorageV2'
    location: location
    skuName: 'Standard_LRS'
    blobServices: {
      enabled: true
      containers: [
        {
          name: 'images'
          publicAccess: 'Blob'
        }
      ]
    }
    fileServices: {
      enabled: true
      shares:[
        {
          name: 'fileshare'
          shareName: 'fileshare'
          enabledProtocols: 'SMB'
          shareQuota: 10
        }

      ]
    }
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
    roleAssignments: [
      
      {
        principalId: dataUploadIdentity.outputs.principalId
        principalType: 'ServicePrincipal'
        roleDefinitionIdOrName: 'Storage Blob Data Contributor'
      }
      {
        principalId: principalId //providing necessary permissions to the Azure Sub Admin account used for deploy
        principalType: 'User'
        roleDefinitionIdOrName: 'Storage Blob Data Contributor'
      }
      {
        principalId: dataUploadIdentity.outputs.principalId
        principalType: 'ServicePrincipal'
        roleDefinitionIdOrName: 'Storage File Data SMB Share Contributor'
      }
      {
        principalId: principalId //providing necessary permissions to the Azure Sub Admin account used for deploy
        principalType: 'User'
        roleDefinitionIdOrName: 'Storage File Data SMB Share Contributor'
      }
      {
        principalId: dataUploadIdentity.outputs.principalId
        principalType: 'ServicePrincipal'
        roleDefinitionIdOrName: 'Storage File Data Privileged Contributor'
      }
      {
        principalId: principalId //providing necessary permissions to the Azure Sub Admin account used for deploy
        principalType: 'User'
        roleDefinitionIdOrName: 'Storage File Data Privileged Contributor'
      }
    ]
    }  
  }




module dataUploadIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.2.1' = {
  name: 'dataUploadIdentityDeployment'
  params: {
    name: '${abbrs.managedIdentityUserAssignedIdentities}upload-${resourceToken}'
    location: location
  }
}

module ScriptManagedIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.2.1' = {
  name: 'ScriptManagedIdentityDeployment'
  params: {
    name: '${abbrs.managedIdentityUserAssignedIdentities}Script-${resourceToken}'
    location: location
  }    
}

// add role assignment to the scriptmanagedidentity as contributor to the resoruce group
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
name: guid(resourceGroup().id, ScriptManagedIdentity.name)
scope: resourceGroup()
properties: {
  principalId: ScriptManagedIdentity.outputs.principalId
  roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
  principalType: 'ServicePrincipal'
}
}



// This module is used to upload the images to the storage account. It uses a PowerShell script to download the images from a public URL and upload them to the storage account.
  module uploadBlobsScript 'br/public:avm/res/resources/deployment-script:0.5.0' = if (copyImages) {
    name: 'uploadDatasScriptDeployment'
    params: {
      kind: 'AzurePowerShell'
      name: 'pwscript-uploadDatasScript'
      azPowerShellVersion: '12.3'
      location: location
      managedIdentities: {
        userAssignedResourceIds: [
          dataUploadIdentity.outputs.resourceId
        ]
      }
      cleanupPreference: 'OnSuccess'
      retentionInterval: 'P1D'
      enableTelemetry: true
      storageAccountResourceId: storageAccount.outputs.resourceId
      arguments: '-StorageAccountName ${storageAccount.outputs.name}' //multi line strings do not support interpolation in bicep yet
      scriptContent: '''
        param([string] $StorageAccountName)
    
        Invoke-WebRequest -Uri "https://github.com/petender/azd-fdcdn/blob/2522659eeb200bfb36d11cdb0f8805a01cc23529/WebSite/images/image-01.jpg?raw=true" -OutFile image-01.jpg
        Invoke-WebRequest -Uri "https://github.com/petender/azd-fdcdn/blob/2522659eeb200bfb36d11cdb0f8805a01cc23529/WebSite/images/image-02.jpg?raw=true" -OutFile image-02.jpg
        Invoke-WebRequest -Uri "https://github.com/petender/azd-fdcdn/blob/2522659eeb200bfb36d11cdb0f8805a01cc23529/WebSite/images/image-03.jpg?raw=true" -OutFile image-03.jpg
        Invoke-WebRequest -Uri "https://github.com/petender/azd-fdcdn/blob/2522659eeb200bfb36d11cdb0f8805a01cc23529/WebSite/images/image-04.jpg?raw=true" -OutFile image-04.jpg
        Invoke-WebRequest -Uri "https://github.com/petender/azd-fdcdn/blob/2522659eeb200bfb36d11cdb0f8805a01cc23529/WebSite/images/image-05.jpg?raw=true" -OutFile image-05.jpg
        Invoke-WebRequest -Uri "https://github.com/petender/azd-fdcdn/blob/2522659eeb200bfb36d11cdb0f8805a01cc23529/WebSite/images/image-06.jpg?raw=true" -OutFile image-06.jpg

        $blobcontext = New-AzStorageContext -StorageAccountName $StorageAccountName
        $filecontext = New-AzStorageContext -StorageAccountName $StorageAccountName -UseConnectedAccount -EnableFileBackupRequestIntent
        $fileShareName = "fileshare"
        $folderPath = "/"
  
        Set-AzStorageBlobContent -Context $blobcontext -Container "images" -File image-01.jpg -Blob image-01.jpg -Force
        Set-AzStorageBlobContent -Context $blobcontext -Container "images" -File image-02.jpg -Blob image-02.jpg -Force
        Set-AzStorageBlobContent -Context $blobcontext -Container "images" -File image-03.jpg -Blob image-03.jpg -Force
        Set-AzStorageBlobContent -Context $blobcontext -Container "images" -File image-04.jpg -Blob image-04.jpg -Force
        Set-AzStorageBlobContent -Context $blobcontext -Container "images" -File image-05.jpg -Blob image-05.jpg -Force
        Set-AzStorageBlobContent -Context $blobcontext -Container "images" -File image-06.jpg -Blob image-06.jpg -Force

        Set-AzStorageFileContent -Context $filecontext -ShareName $fileShareName -Source image-01.jpg -Path image-01.jpg -Force
        Set-AzStorageFileContent -Context $filecontext -ShareName $fileShareName -Source image-02.jpg -Path image-02.jpg -Force
        Set-AzStorageFileContent -Context $filecontext -ShareName $fileShareName -Source image-03.jpg -Path image-03.jpg -Force
        Set-AzStorageFileContent -Context $filecontext -ShareName $fileShareName -Source image-04.jpg -Path image-04.jpg -Force
        Set-AzStorageFileContent -Context $filecontext -ShareName $fileShareName -Source image-05.jpg -Path image-05.jpg -Force
        Set-AzStorageFileContent -Context $filecontext -ShareName $fileShareName -Source image-06.jpg -Path image-06.jpg -Force
        '''
    }
  }


output StorageAccountId string = storageAccount.outputs.resourceId
output ScriptManagedIdentityResId string = ScriptManagedIdentity.outputs.resourceId
output BlobImageBaseUrl string = 'https://${storageAccount.outputs.name}.blob.core.windows.net/images'

targetScope = 'subscription'

param rgName string
param location string
param sqlServerName string
param sqlDbName string
param clientIpAddress string
param logAnalyticsWorkspaceName string
param appInsightsName string
param webAppName string
param appServicePlanName string
param appServicePlanSku string
param keyVaultName string
param identityDBConnectionStringKey string
param managerDBConnectionStringKey string

@secure()
param sqlLogin string

@description('The admin password for the database server.')
@secure()
param sqlPassword string

@allowed(['dev','prod'])
param environment string

var uniqueIdentifier = substring(uniqueString(rgName),0,11)
var sqlDBServerName = '${sqlServerName}${uniqueIdentifier}${environment}'

resource contactWebResourceGroup 'Microsoft.Resources/resourceGroups@2018-05-01' = {
  name: rgName
  location: location
}

module sqlServer 'br/public:avm/res/sql/server:0.4.1' = {  
  name: 'sqlServerDeployment'
  scope: contactWebResourceGroup
  params: {
    // Required parameters
    name: sqlDBServerName
    // Non-required parameters
    administratorLogin: sqlLogin
    administratorLoginPassword: sqlPassword    
    location: location
    databases: [
      {
        capacity: 5
        collation: 'SQL_Latin1_General_CP1_CI_AS'   
        maxSizeBytes: 2147483648                     
        name: sqlDbName
        skuName: 'Basic'      
        skuTier: 'Basic'    
      }
    ]
    firewallRules: [
      {
        endIpAddress: '0.0.0.0'
        name: 'AllowAllWindowsAzureIps'
        startIpAddress: '0.0.0.0'
      }
      {
        endIpAddress: clientIpAddress
        name: 'clientIpAddress'
        startIpAddress: clientIpAddress
      }
    ]
    managedIdentities: {
      systemAssigned: true
    }
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    restrictOutboundNetworkAccess: 'Disabled'
  }  
}

module logAnalyticsWorkspace 'br:bicepregistrydemo.azurecr.io/bicep/modules/loganalyticsworkspace:v2' = {
  scope: contactWebResourceGroup
  name: '${logAnalyticsWorkspaceName}-deployment'
  params: {
    logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
    location: contactWebResourceGroup.location
  }
}

module appInsights 'modules/appInsights/appInsights.bicep' = {
  scope: contactWebResourceGroup
  name: '${appInsightsName}-deployment'
  params: {
    location: contactWebResourceGroup.location
    appInsightsName: appInsightsName
    logAnalyticsWorkspaceId: logAnalyticsWorkspace.outputs.logAnalyticsWorkspaceId
  }
}

module appPlanAndSite 'modules/appService/appService.bicep' = {
  name: '${webAppName}-deployment'
  scope: contactWebResourceGroup
  params: {
    location: contactWebResourceGroup.location
    uniqueIdentifier: uniqueIdentifier
    appInsightsName: appInsights.outputs.applicationInsightsName
    appServicePlanName: appServicePlanName
    appServicePlanSku: appServicePlanSku
    webAppName: webAppName
  }
}

module contactWebVault 'modules/keyvault/keyvault.bicep' = {
  name: '${keyVaultName}-deployment'
  scope: contactWebResourceGroup
  params: {
    location: contactWebResourceGroup.location
    uniqueIdentifier: uniqueIdentifier
    webAppFullName: appPlanAndSite.outputs.webAppFullName
    databaseServerName: sqlServer.outputs.name
    keyVaultName: keyVaultName
    sqlDatabaseName: sqlDbName
    sqlServerAdminPassword: sqlPassword
  }
}

module updateContactWebAppSettings 'appSettingsUpdate.bicep' = {
  name: '${webAppName}-updatingAppSettings'
  scope: contactWebResourceGroup
  params: {
    webAppName: appPlanAndSite.outputs.webAppFullName
    defaultDBSecretURI: contactWebVault.outputs.identityDBConnectionSecretURI
    managerDBSecretURI: contactWebVault.outputs.managerDBConnectionSecretURI
    identityDBConnectionStringKey: identityDBConnectionStringKey
    managerDBConnectionStringKey: managerDBConnectionStringKey
  }
}

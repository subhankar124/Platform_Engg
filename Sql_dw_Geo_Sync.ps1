
#Create restorepoint and take back and delete the old restore point more than 12 hours(tosave the cost). 
###########################################################################################################
$ProgressPreference='SilentlyContinue'

# to run in KUDU
#Import-Module -name "D:\home\site\PSModule\azuremodules\AzureRM.profile\5.7.0\AzureRM.Profile.psd1"
#Import-Module -name "D:\home\site\PSModule\azuremodules\AzureRM.Sql\4.11.5\AzureRM.Sql.psd1"




$SubscriptionName = 'XXXXXX'

$tenantid = 'YYYYYY'


Set-AzureRmContext -SubscriptionId $SubscriptionName

############################################################ Storage Account Details#########################################################################

$storageAccountName = 'abcd'

$tableName = 'abcdtable'

$newPartitionKey = 'abcdpartitionkey'

$accesskey = "xyz=="


######################### Primary Connection for creating restore point #####################################

$newGuid = ([guid]::NewGuid().tostring())
$PriResourceGroupName = 'prodprirg'
$PriServerName = 'prodpriserver'

[string] $PriServer= "prodpriserver.database.windows.net"

$PriDatabaseName = 'pridb'
$PriRestorePointLabel = 'RestorePoint' + '_' + $newGuid 
[string] $uid = 'abcd' ### read from AKV
[string] $pwd = 'abcd' ### read from AKV
[string] $ConnectionString = "Server = $PriServer; Database = $PriDatabaseName; Integrated Security = false; User ID = $uid; Password = $pwd;"



$strongpassword = 'BBBB='

$serviceprincipalname = 'BBB' # client ID

$retainCounter = 12

######################### SQL Login DR ##################################################
[string] $Server= "proddr.database.windows.net"
[string] $Database = "pridb"
[string] $uid1 = 'abcd' ### read from AKV
[string] $pwd1 = 'abcds' ### read from AKV
[string] $ConnectionStringDR = "Server = $Server; Database = $Database; Integrated Security = false; User ID = $uid1; Password = $pwd1;"

####################################

################################### DR Config#############################
$DRResourceGroupName = 'v-proddr-rg'
$DRServerName='proddr'
$DRDatabaseName='vlwarehouse'


$APIVersion = "2015-10-01"
#########################################################################



$securepassword = convertto-securestring $strongpassword -asplaintext -force
$securecredential = new-object system.management.automation.pscredential($serviceprincipalname, $securepassword)
login-azurermaccount -serviceprincipal -credential $securecredential -tenant $tenantid -SubscriptionId $SubscriptionName


################################# Helper function ##################################
 function UpdateSqlQuery ($ConnectionString, $SQLQuery) {
        
    $Connection = New-Object System.Data.SQLClient.SQLConnection
    $Connection.ConnectionString = $ConnectionString
    $Connection.Open()
    $Command = New-Object System.Data.SQLClient.SQLCommand
    $Command.Connection = $Connection
    $Command.CommandText = $SQLQuery
    $no = $Command.ExecuteNonQuery()
 
    $Connection.Close()
    
    return $no
}

function GenericSqlQuery ($ConnectionString, $SQLQuery) {
    $Datatable = New-Object System.Data.DataTable
    
    $Connection = New-Object System.Data.SQLClient.SQLConnection
    $Connection.ConnectionString = $ConnectionString
    $Connection.Open()
    $Command = New-Object System.Data.SQLClient.SQLCommand
    $Command.Connection = $Connection
    $Command.CommandText = $SQLQuery

    $DataAdapter = new-object System.Data.SqlClient.SqlDataAdapter $Command
    $Dataset = new-object System.Data.Dataset
    $DataAdapter.Fill($Dataset)
    $Connection.Close()
    
    return $Dataset.Tables[0]
}



function InsertReplaceTableEntity($TableName, $PartitionKey, $RowKey, $entity) {
    $version = "2017-04-17"
    $resource = "$tableName(PartitionKey='$PartitionKey',RowKey='$Rowkey')"
    $table_url = "https://$storageAccountName.table.core.windows.net/$resource"
    $GMTTime = (Get-Date).ToUniversalTime().toString('R')
    $stringToSign = "$GMTTime`n/$storageAccountName/$resource"
    $hmacsha = New-Object System.Security.Cryptography.HMACSHA256
    $hmacsha.key = [Convert]::FromBase64String($accesskey)
    $signature = $hmacsha.ComputeHash([Text.Encoding]::UTF8.GetBytes($stringToSign))
    $signature = [Convert]::ToBase64String($signature)
    $headers = @{
        'x-ms-date'    = $GMTTime
        Authorization  = "SharedKeyLite " + $storageAccountName + ":" + $signature
        "x-ms-version" = $version
        Accept         = "application/json;odata=fullmetadata"
    }
    $body = $entity | ConvertTo-Json
    $item = Invoke-RestMethod -Method PUT -Uri $table_url -Headers $headers -Body $body -ContentType application/json
}
 
 function MergeTableEntity($TableName, $PartitionKey, $RowKey, $entity) {
    $version = "2017-04-17"
    $resource = "$tableName(PartitionKey='$PartitionKey',RowKey='$Rowkey')"
    $table_url = "https://$storageAccountName.table.core.windows.net/$resource"
    $GMTTime = (Get-Date).ToUniversalTime().toString('R')
    $stringToSign = "$GMTTime`n/$storageAccountName/$resource"
    $hmacsha = New-Object System.Security.Cryptography.HMACSHA256
    $hmacsha.key = [Convert]::FromBase64String($accesskey)
    $signature = $hmacsha.ComputeHash([Text.Encoding]::UTF8.GetBytes($stringToSign))
    $signature = [Convert]::ToBase64String($signature)
    $body = $entity | ConvertTo-Json
    $headers = @{
        'x-ms-date'      = $GMTTime
        Authorization    = "SharedKeyLite " + $storageAccountName + ":" + $signature
        "x-ms-version"   = $version
        Accept           = "application/json;odata=minimalmetadata"
        'If-Match'       = "*"
        'Content-Length' = $body.length
    }
    $item = Invoke-RestMethod -Method MERGE -Uri $table_url -Headers $headers -ContentType application/json -Body $body
 
}

function GetTableEntityAll($TableName) {
    $version = "2017-04-17"
    $resource = "$tableName"
    $table_url = "https://$storageAccountName.table.core.windows.net/$resource"
    $GMTTime = (Get-Date).ToUniversalTime().toString('R')
    $stringToSign = "$GMTTime`n/$storageAccountName/$resource"
    $hmacsha = New-Object System.Security.Cryptography.HMACSHA256
    $hmacsha.key = [Convert]::FromBase64String($accesskey)
    $signature = $hmacsha.ComputeHash([Text.Encoding]::UTF8.GetBytes($stringToSign))
    $signature = [Convert]::ToBase64String($signature)
    $headers = @{
        'x-ms-date'    = $GMTTime
        Authorization  = "SharedKeyLite " + $storageAccountName+ ":" + $signature
        "x-ms-version" = $version
        Accept         = "application/json;odata=fullmetadata"
    }
    $item = Invoke-RestMethod -Method GET -Uri $table_url -Headers $headers -ContentType application/json
    return $item.value
}

######################################

################################## Create restore Point ####################################################

try
{
        Write-Output 'Start creation restorepoint!'
    
        $DatabaseT = Get-AzureRmSqlDatabase -ResourceGroupName $PriResourceGroupName -ServerName $PriServerName -DatabaseName $PriDatabaseName
        $aListDate = New-Object System.Collections.Generic.List[System.Object]

        if($DatabaseT.Status -eq 'Online')
        {
            $Status = New-AzureRmSqlDatabaseRestorePoint -ResourceGroupName $PriResourceGroupName -ServerName $PriServerName -DatabaseName $PriDatabaseName -RestorePointLabel $PriRestorePointLabel

            $restorePointCollection = (Get-AzureRmSqlDatabaseRestorePoints -ResourceGroupName $PriResourceGroupName -ServerName $PriServerName -DatabaseName $PriDatabaseName)

            foreach($restorePoint in $restorePointCollection )
            {
                $date = $restorePoint.RestorePointCreationDate.ToString()
                $aListDate.Add($date)
                #check sorting logic        
            }
        Write-Output 'End creation restorepoint!'
            $aListDateSort = $aListDate | ForEach-Object {[datetime]::Parse("$_",(Get-Culture))} | sort | ForEach-Object { $_.ToString() }

            if($aListDate.Count -ge $retainCounter)
            {
                $diff = $aListDate.Count - $retainCounter
                # delete the oldest retention back up.
                $selectDeleteRecord = $aListDateSort | Select -First $diff 
        Write-Output 'Start removing restorepoint!'
                foreach($RestorePointCreationDate in $selectDeleteRecord )
                {
                    if( (($restorePointCollection | Select-Object "RestorePointCreationDate","RestorePointLabel" | where {($_.RestorePointLabel -like '*UNSRestorePoint*') -and ($_.RestorePointCreationDate -eq $RestorePointCreationDate)}) | ForEach-Object { $_.RestorePointCreationDate }).Count -eq 1)
                    {
                        $deleteStatus =  Remove-AzureRmSqlDatabaseRestorePoint -ResourceGroupName $PriResourceGroupName -ServerName $PriServerName -DatabaseName $PriDatabaseName -RestorePointCreationDate $RestorePointCreationDate
                        Write-Output  $deleteStatus
                    }
                }
        

            }
        }
        Write-Output 'End removing restorepoint!'

        Write-Output 'Start updating restorepointdate!'
    
        $selectedRestorePoint = $aListDateSort | Select -Last 1

            $tableOutputALL  = GetTableEntityAll -TableName $tableName| Where-Object {$_.ConfigurationName -eq 'RestorePointDateTime'}
    
            if(($tableOutputALL | foreach-object  {$_.ConfigurationName} | select -first 5000).Count -eq 0)
            {

                $body = @{
                        RowKey       = ([guid]::NewGuid().tostring())
                        PartitionKey = $newPartitionKey
                        ConfigurationName = 'RestorePointDateTime'
                        ConfigurationValue = $selectedRestorePoint
                        }

                InsertReplaceTableEntity -TableName $tableName -RowKey $body.RowKey -PartitionKey $body.PartitionKey -entity $body
            }
            else
            {
        
                $body = @{
                            RowKey       = $tableOutputALL.RowKey
                            PartitionKey = $newPartitionKey
                            ConfigurationName = 'RestorePointDateTime'
                            ConfigurationValue = $selectedRestorePoint
                        }

                MergeTableEntity -TableName $tableName -RowKey $body.RowKey -PartitionKey $body.PartitionKey -entity $body
            }

        Write-Output 'End updating restorepointdate!'

}
catch
{
    Write-Output $_.Exception.Message
}



# Above logic Every 15 mins in KUDU or Runbook
##########################################################################################################################################################
##########################################################################################################################################################
# Below logic every 30 mins in KUDU or Runbook -->




#################################################################################################################

# Take a the latest back up and restore to DR DB by deleting the existing DB in the DR and create the new DB with same name

#################################################################################################################

############################# Update system config table with the restore point DateTime and IS_LatestRestore(if restore point is not accessble then make this flag ZERO)- Corner case

try
{

        if((Get-AzureRmSqlDatabase -ResourceGroupName $DRResourceGroupName -ServerName $DRServerName | Select-Object "DatabaseName" | where {$_.DatabaseName -eq $DRDatabaseName} | foreach-object  {$_.DatabaseName}).Length -ge 1)
        {
   
            Write-Output 'Start Getting restorepointdate!'


            ############################################Storing into blob###############################

            $tableOutputALLRestorePointDateTime  = GetTableEntityAll -TableName $tableName | Where-Object {$_.ConfigurationName -eq 'RestorePointDateTime'}
            $tableOutputALLRestoreDateTime  = GetTableEntityAll -TableName $tableName  | Where-Object {$_.ConfigurationName -eq 'RestoreDateTime'}
            
            
            
            if(($tableOutputALLRestoreDateTime | foreach-object  {$_.ConfigurationValue} | select -first 5000).Count -ge 1 )
            {
                $RestoreDateTime = $tableOutputALLRestoreDateTime | foreach-object  {$_.ConfigurationValue} | select -first 5000
            }
               $RestorePointDateTime = $tableOutputALLRestorePointDateTime | foreach-object  {$_.ConfigurationValue} | select -first 5000

            Write-Output $RestoreDateTime
            Write-Output $RestorePointDateTime
            Write-Output 'End Getting restorepointdate!'

            $global:DBStatusCheck = $false

            if(($tableOutputALLRestoreDateTime | foreach-object  {$_.ConfigurationValue} | select -first 5000).Count -eq 0 -and ($tableOutputALLRestorePointDateTime | foreach-object  {$_.ConfigurationValue} | select -first 5000).Count -ge 1)
            {
                $global:DBStatusCheck = $true

            }
            else
            {

                $dateDiff =  ($RestorePointDateTime - $RestoreDateTime).TotalHours # need to vlidate this
                if($dateDiff -ge 2)
                {
                    $global:DBStatusCheck = $true
                }
            }

            if($global:DBStatusCheck -eq $true)
            {
                 Write-Output 'DR Database is available and ready for delete!'

                $DatabaseP = Get-AzureRmSqlDatabase -ResourceGroupName $PriResourceGroupName -ServerName $PriServerName -DatabaseName $PriDatabaseName


                ############################# Restore point check and then delete DR DB - Done
                ############################# Check if failover time and restore point time diff less than 15 mins then no need to restore.-- Not one yet

        
                if((Get-AzureRmSqlDatabase -ResourceGroupName $DRResourceGroupName -ServerName $DRServerName | Select-Object "DatabaseName" | where {$_.DatabaseName -eq $DRDatabaseName} | foreach-object  {$_.DatabaseName}).Length -ge 1)
                {
                    $restorePointCollectionCheck = ((Get-AzureRmSqlDatabaseRestorePoints -ResourceGroupName $PriResourceGroupName -ServerName $PriServerName -DatabaseName $PriDatabaseName) | Select-Object "RestorePointCreationDate" | where {$_.RestorePointCreationDate -eq $RestorePointDateTime} | foreach-object  {$_.RestorePointCreationDate})
                    if($restorePointCollectionCheck.count -ge 1)
                    {
                        Write-Output 'Start Removing Database!'
                        $global:RemoveDBStatus = Remove-AzureRmSqlDatabase -ResourceGroupName $DRResourceGroupName -ServerName $DRServerName -DatabaseName $DRDatabaseName
                       
                    }
                }

                $global:DRDBStatusDel = $true

                do
                {


                    Start-Sleep -s 180

                    if((Get-AzureRmSqlDatabase -ResourceGroupName $DRResourceGroupName -ServerName $DRServerName | Select-Object "DatabaseName" | where {$_.DatabaseName -eq $DRDatabaseName} | foreach-object  {$_.DatabaseName}).Length -ge 1)
                    {
                        
                        $global:DRDBStatusDel = $flase
                    }
                    else
                    {
                         $global:DRDBStatusDel = $true
                    
                    }
                }while((Get-AzureRmSqlDatabase -ResourceGroupName $DRResourceGroupName -ServerName $DRServerName | Select-Object "DatabaseName" | where {$_.DatabaseName -eq $DRDatabaseName} | foreach-object  {$_.DatabaseName}).Length -ge 1)
        
                 Write-Output 'End Removing Database!'

                if($global:DRDBStatusDel)
                {
                        Write-Output 'Start Database restore!'

                        if((Get-AzureRmSqlDatabase -ResourceGroupName $DRResourceGroupName -ServerName $DRServerName | Select-Object "DatabaseName" | where {$_.DatabaseName -eq $DRDatabaseName} | foreach-object  {$_.DatabaseName}).Length -le 1)
                        {
                            $RestoredDatabase = Restore-AzureRmSqlDatabase –FromPointInTimeBackup –PointInTime $RestorePointDateTime -ResourceGroupName $DRResourceGroupName -ServerName $DRServerName -TargetDatabaseName $DRDatabaseName –ResourceId $DatabaseP.ResourceId
                        
                        }
                       


                        ####################################################################################################

                        #########################After Restoration Of the DB setup user and Role############################

                        ####################################################################################################


                        ######################################### 1) Users login 2) Roles 3)firewall 

                        do
                        {
               
                            Start-Sleep -s 120

                        }while((Get-AzureRmSqlDatabase -ResourceGroupName $DRResourceGroupName -ServerName $DRServerName | Select-Object "DatabaseName" | where {$_.DatabaseName -eq $DRDatabaseName} | foreach-object  {$_.DatabaseName}).Length -le 1)
        
                         Write-Output 'End Database has been restored!'

                        ############################################################################ Update Restore Date Time###########################################
                         Write-Output 'Start updating restorepoint date!'
                       
                         ################################################Storing to Blob###################################
                         $tableOutputALLResDT  = GetTableEntityAll -TableName $tableName| Where-Object {$_.ConfigurationName -eq 'RestoreDateTime'}
                
                        if(($tableOutputALLResDT | foreach-object  {$_.ConfigurationName} | select -first 5000).Count -eq 0)
                        {

                        $body = @{
                                RowKey       = ([guid]::NewGuid().tostring())
                                PartitionKey = $newPartitionKey
                                ConfigurationName = 'RestoreDateTime'
                                ConfigurationValue = $RestorePointDateTime
                                }

                        InsertReplaceTableEntity -TableName $tableName -RowKey $body.RowKey -PartitionKey $body.PartitionKey -entity $body
                        }
                        else
                        {
        
                        $body = @{
                                    RowKey       = $tableOutputALLResDT.RowKey
                                    PartitionKey = $newPartitionKey
                                    ConfigurationName = 'RestoreDateTime'
                                    ConfigurationValue = $RestorePointDateTime
                                }

                        MergeTableEntity -TableName $tableName -RowKey $body.RowKey -PartitionKey $body.PartitionKey -entity $body
                        }
                
                        
                         Write-Output 'End User Creation!'

                        
                        Write-Output 'Database is ready for use!'

  
                  }
            }
        }
        else
        {
             Write-Output 'DR Database is NOT available, Direct restore!'

            
                $DatabaseP = Get-AzureRmSqlDatabase -ResourceGroupName $PriResourceGroupName -ServerName $PriServerName -DatabaseName $PriDatabaseName


                $tableOutputALLRestorePointDateTime  = GetTableEntityAll -TableName $tableName | Where-Object {$_.ConfigurationName -eq 'RestorePointDateTime'}
                           
            
                $RestorePointDateTimeNDR = $tableOutputALLRestorePointDateTime | foreach-object  {$_.ConfigurationValue} | select -first 5000



                ############################# Restore point check and then delete DR DB - Done
                ############################# Check if failover time and restore point time diff less than 15 mins then no need to restore.-- Not one yet

        
                if((Get-AzureRmSqlDatabase -ResourceGroupName $DRResourceGroupName -ServerName $DRServerName | Select-Object "DatabaseName" | where {$_.DatabaseName -eq $DRDatabaseName} | foreach-object  {$_.DatabaseName}).Length -ge 1)
                {
                    $restorePointCollectionCheck = ((Get-AzureRmSqlDatabaseRestorePoints -ResourceGroupName $PriResourceGroupName -ServerName $PriServerName -DatabaseName $PriDatabaseName) | Select-Object "RestorePointCreationDate" | where {$_.RestorePointCreationDate -eq $RestorePointDateTimeNDR} | foreach-object  {$_.RestorePointCreationDate})
                    if($restorePointCollectionCheck.count -ge 1)
                    {
                        Write-Output 'Start Removing Database!'
                       $global:RemoveDBStatus = Remove-AzureRmSqlDatabase -ResourceGroupName $DRResourceGroupName -ServerName $DRServerName -DatabaseName $DRDatabaseName
                        Write-Output 'End Removing Database!'
                    }
                }

                $global:DRDBStatusDel = $true

                do
                {
                    if((Get-AzureRmSqlDatabase -ResourceGroupName $DRResourceGroupName -ServerName $DRServerName | Select-Object "DatabaseName" | where {$_.DatabaseName -eq $DRDatabaseName} | foreach-object  {$_.DatabaseName}).Length -ge 1)
                    {
                        Start-Sleep -s 180

                        $global:DRDBStatusDel = $flase
                    }
                    else
                    {
                         $global:DRDBStatusDel = $true
                    }
                }while((Get-AzureRmSqlDatabase -ResourceGroupName $DRResourceGroupName -ServerName $DRServerName | Select-Object "DatabaseName" | where {$_.DatabaseName -eq $DRDatabaseName} | foreach-object  {$_.DatabaseName}).Length -ge 1)
        
        
                if($global:DRDBStatusDel)
                {
                        Write-Output 'Start Database restore!'

                        if((Get-AzureRmSqlDatabase -ResourceGroupName $DRResourceGroupName -ServerName $DRServerName | Select-Object "DatabaseName" | where {$_.DatabaseName -eq $DRDatabaseName} | foreach-object  {$_.DatabaseName}).Length -le 1)
                        {
                            $RestoredDatabase = Restore-AzureRmSqlDatabase –FromPointInTimeBackup –PointInTime $RestorePointDateTimeNDR -ResourceGroupName $DRResourceGroupName -ServerName $DRServerName -TargetDatabaseName $DRDatabaseName –ResourceId $DatabaseP.ResourceId
                        }
                       


                        ####################################################################################################

                        #########################After Restoration Of the DB setup user and Role############################

                        ####################################################################################################


                        ######################################### 1) Users login 2) Roles 3)firewall 

                        do
                        {
               
                            Start-Sleep -s 120

                        }while((Get-AzureRmSqlDatabase -ResourceGroupName $DRResourceGroupName -ServerName $DRServerName | Select-Object "DatabaseName" | where {$_.DatabaseName -eq $DRDatabaseName} | foreach-object  {$_.DatabaseName}).Length -le 1)
                        
                         Write-Output 'End Database has been restored!'

                         $tableOutputALLResDTD  = GetTableEntityAll -TableName $tableName| Where-Object {$_.ConfigurationName -eq 'RestoreDateTime'}
                
                        if(($tableOutputALLResDTD | foreach-object  {$_.ConfigurationName} | select -first 5000).Count -eq 0)
                        {

                            $body = @{
                                    RowKey       = ([guid]::NewGuid().tostring())
                                    PartitionKey = $newPartitionKey
                                    ConfigurationName = 'RestoreDateTime'
                                    ConfigurationValue = $RestorePointDateTimeNDR
                                    }

                            InsertReplaceTableEntity -TableName $tableName -RowKey $body.RowKey -PartitionKey $body.PartitionKey -entity $body
                        }
                        else
                        {
        
                            $body = @{
                                        RowKey       = $tableOutputALLResDTD.RowKey
                                        PartitionKey = $newPartitionKey
                                        ConfigurationName = 'RestoreDateTime'
                                        ConfigurationValue = $RestorePointDateTimeNDR
                                    }

                            MergeTableEntity -TableName $tableName -RowKey $body.RowKey -PartitionKey $body.PartitionKey -entity $body
                        }
                                    
                                       
                        Write-Output 'Database is ready for use!'


                  }
        }

      

}
catch
{
    Write-Output $_.Exception.Message
}










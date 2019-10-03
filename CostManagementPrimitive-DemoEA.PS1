#
# Demo n°1 : Demo sur une souscription avec un peu de conso
#
$SubscriptionGUID = '<SubscriptionID>'  # Ne fonctionne qu'avec une souscription EA
$[String]$BudgetName = "<Budgetname>" # Nom de l'Azure Budget positionné au niveau de la souscription
function Get-AzCachedAccessToken()
{
    #
    # Get Current token for connected user
    #
    # https://www.codeisahighway.com/how-to-easily-and-silently-obtain-accesstoken-bearer-from-an-existing-azure-powershell-session/
    $ErrorActionPreference = 'Stop'
    if(-not (Get-Module Az.Accounts)) {
        Import-Module Az.Accounts
    }
    $azProfile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile
    if(-not $azProfile.Accounts.Count) {
        Write-Error "Ensure you have logged in before calling this function."    
    }
    $currentAzureContext = Get-AzContext
    $profileClient = New-Object Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient($azProfile)
    Write-Debug ("Getting access token for tenant" + $currentAzureContext.Tenant.TenantId)
    $token = $profileClient.AcquireAccessToken($currentAzureContext.Tenant.TenantId)
    $token.AccessToken
}
$token =  Get-AzCachedAccessToken 
$headers = @{"authorization"="bearer $token"} 
#
# Calcul du Forecast de consommation
#
Set-AzContext -SubscriptionId $SubscriptionGUID
$uri =  "https://management.azure.com/subscriptions/$SubscriptionGUID/providers/Microsoft.Consumption/forecasts?api-version=2019-01-01"
$results = Invoke-RestMethod $uri -Headers $headers -ContentType "application/json" -Method Get
$PresentationTable = @()
$CumulatedCost = 0
Foreach ($Forecast in $Results.Value)
{
    $item = New-Object PSObject
    $item | Add-Member -Type NoteProperty -Name "UsageDate"  -Value $Forecast.properties.usageDate
    $item | Add-Member -Type NoteProperty -Name "Grain"  -Value $Forecast.properties.grain
    $item | Add-Member -Type NoteProperty -Name "ChargeType"  -Value $Forecast.properties.ChargeType
    $item | Add-Member -Type NoteProperty -Name "Charge"  -Value $("{0:N2}" -f ($Forecast.properties.Charge))     
    $item | Add-Member -Type NoteProperty -Name "Currency"  -Value $Forecast.properties.Currency
    $CumulatedCost += $Forecast.properties.Charge
    Switch ($Forecast.properties.chargeType)
    {
        "ForeCast"
        {
            $UpperBound = $Forecast.properties.confidenceLevels | Where-Object {$_.Bound -eq "Upper"}
            $item | Add-Member -Type NoteProperty -Name "UpperPercentage"  -Value $UpperBound.Percentage
            $item | Add-Member -Type NoteProperty -Name "UpperValue"  -Value $("{0:N2}" -f ($UpperBound.value))     
            $LowerBound = $Forecast.properties.confidenceLevels | Where-Object {$_.Bound -eq "Lower"}
            $item | Add-Member -Type NoteProperty -Name "LowerPercentage"  -Value $LowerBound.Percentage
            $item | Add-Member -Type NoteProperty -Name "LowerValue"  -Value $("{0:N2}" -f ($LowerBound.value))     
        }
        "Actual"
        {
            $item | Add-Member -Type NoteProperty -Name "UpperPercentage"  -Value "N/A"
            $item | Add-Member -Type NoteProperty -Name "UpperValue"  -Value "N/A"
            $item | Add-Member -Type NoteProperty -Name "LowerPercentage"  -Value "N/A"
            $item | Add-Member -Type NoteProperty -Name "LowerValue"  -Value "N/A" 
        }
    }
    $PresentationTable += $Item
}
$PresentationTable | Sort-Object UsageDate | format-table -AutoSize 
$budget = Get-AzConsumptionBudget -Name $BudgetName
Write-Host "Budget $($Budget.Amount) - Cummulated Costs : $("{0:N2}" -f ($CumulatedCost))"
If ($CumulatedCost -Gt $Budget.Amount)
{
    Write-Warning "Forecasting Overbudget"
}
else {
    Write-host -ForegroundColor Green "Budget is Good!!"    
}
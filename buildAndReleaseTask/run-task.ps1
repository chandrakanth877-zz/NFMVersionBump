Trace-VstsEnteringInvocation $MyInvocation

$path = Get-VstsInput -Name path -Require
$VersionVariable = Get-VstsInput -Name VersionVariable -Require
$devOpsPat = Get-VstsInput -Name devOpsPat -Require

$devOpsUri = $env:SYSTEM_TEAMFOUNDATIONSERVERURI
$projectName = $env:SYSTEM_TEAMPROJECT
$projectId = $env:SYSTEM_TEAMPROJECTID 
$buildId = $env:BUILD_BUILDID

Write-Output "Path                 : $($path)";
Write-Output "versionvarible       : $($VersionVariable)";
Write-Output "DevOpsPAT            : $(if (![System.String]::IsNullOrWhiteSpace($devOpsPat)) { '***'; } else { '<not present>'; })"; ;
Write-Output "DevOps Uri           : $($devOpsUri)";
Write-Output "Project Name         : $($projectName)";
Write-Output "Project Id           : $($projectId)";
Write-Output "BuildId              : $($buildId)";

$buildUri = "$($devOpsUri)$($projectName)/_apis/build/builds/$($buildId)?api-version=4.1"


# enconding PAT
$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f "", $devOpsPat)))
$devOpsHeader = @{Authorization = ("Basic {0}" -f $base64AuthInfo)}


Write-Host "Invoking rest method 'Get' for the url: $($buildUri)."
$buildDef = Invoke-RestMethod -Uri $buildUri -Method Get -ContentType "application/json" -Headers $devOpsHeader

if ($buildDef) {
    $definitionId = $buildDef.definition.id
    $defUri = "$($devOpsUri)$($projectName)/_apis/build/definitions/$($definitionId)?api-version=4.1"

    Write-Host "Trying to retrieve the build definition with the url: $($defUri)."
    $definition = Invoke-RestMethod -Method Get -Uri $defUri -Headers $devOpsHeader -ContentType "application/json"

    if ($definition.variables.$VersionVariable) {
        Write-Host "Value of the Major Version Variable: $($definition.variables.$VersionVariable.Value)"
        $version = $definition.variables.$VersionVariable.Value
        if (!$version) {
            $version = "1.0.0"
        }
        $proj = [xml](get-content $path)
        $proj.GetElementsByTagName("Version") | ForEach-Object{

            $fileversionText = $_."#text"
            $fileVersionTextArray = $_."#text".Split(".")
            $fileVersionWithOutPeriod = $fileVersionTextArray[0] + $fileVersionTextArray[1] + $fileVersionTextArray[2]
            
            Write-Output "file version $fileversionText"
            Write-Output "file version without period $fileVersionWithOutPeriod"

            $versionFromVariableArray = $version.Split(".")
            $versionFromVariableWithOutPeriod = $versionFromVariableArray[0] + $versionFromVariableArray[1] + $versionFromVariableArray[2]
            
            $updateVersion = ""
            Write-Output "Increment version $version"
            Write-Output "Increment version $versionFromVariableWithOutPeriod"

            $fileVersionCount = $fileVersionWithOutPeriod.length
            $pipelineVersionCount = $versionFromVariableWithOutPeriod.length
            if(-NOT  ($fileVersionCount -eq $pipelineVersionCount)){
                if($fileVersionCount -gt $pipelineVersionCount){
                    $versionFromVariableWithOutPeriod = $versionFromVariableWithOutPeriod.PadRight($fileVersionCount, "0")
                }else{
                    $fileVersionWithOutPeriod = $fileVersionWithOutPeriod.PadRight($pipelineVersionCount, "0")
                }
            }


            $versionFromVariableWithOutPeriodInt = [convert]::ToInt32($versionFromVariableWithOutPeriod)
            $fileVersionWithOutPeriodInt = [convert]::ToInt32($fileVersionWithOutPeriod)
            Write-Output "Increment version $versionFromVariableWithOutPeriodInt"
            Write-Output "File version $fileVersionWithOutPeriodInt"

            if($versionFromVariableWithOutPeriodInt -ge $fileVersionWithOutPeriodInt){
                $updateVersion = $versionFromVariableArray[0] +  "." + $versionFromVariableArray[1] +  "." + (([convert]::ToInt32($versionFromVariableArray[2]) + 1).ToString())
            }else{
                $updateVersion = $fileversionText
            }
            Write-Host "updating to version $updateVersion"
            $definition.variables.$VersionVariable.Value = $updateVersion
            $definitionJson = $definition | ConvertTo-Json -Depth 50 -Compress
            Write-Verbose "Updating Project Build number with URL: $($defUri)"
            Invoke-RestMethod -Method Put -Uri $defUri -Headers $devOpsHeader -ContentType "application/json" -Body ([System.Text.Encoding]::UTF8.GetBytes($definitionJson)) | Out-Null
            "##vso[task.setvariable variable=$VersionVariable;]$updateVersion"
            Write-Output "$($VersionVariable)"
        }
    }
    else {
        Write-Error "The variables can not be found on the definition: $($MajorVersionVariable), $($MinorVersionVariable), $($PatchVersionVariable)"
    }
}
else {
    Write-Error "Unable to find a build definition for Project $($ProjectName) with the build id: $($buildId)."
}
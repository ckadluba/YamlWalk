[CmdletBinding()]
param (
    [string] $YamlFile,
    [Parameter(Mandatory=$false)]
    [switch] $RemoveDuplicates
)

function ProcessYamlFiles (
    [string] $directoryPath,
    [string] $relativeFilePath,
    [switch] $RemoveDuplicates,
    $yamlParameters,
    [int] $depth
) {
    $fullYamlPath = GetNormalizedFilePath $directoryPath $relativeFilePath

    $fileExists = Test-Path $fullYamlPath -PathType Leaf
    PrintFileTreeEntry $relativeFilePath $depth $fileExists

    if ($fileExists)
    {
        $yamlDirPath = Split-Path -Path $fullYamlPath
        $subYamlFiles = GetSubfiles $fullYamlPath $yamlParameters
        $subDepth = $depth + 1

        foreach ($subYamlFile in $subYamlFiles) {
            ProcessYamlFiles $yamlDirPath $subYamlFile.FileName $subYamlFile.Parameters $subDepth
        }
    }
}

function GetNormalizedFilePath (
    [string] $directoryPath,
    [string] $filePath
) {
    if ([System.IO.Path]::IsPathRooted($filePath))
    {
        $directoryPath = $null
    }

    return [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($directoryPath, $filePath))
}

function PrintFileTreeEntry (
    [string] $fileName, 
    [int] $depth,
    [bool] $fileExists
) {

    $i = 0
    while ($i -lt $depth) {
        Write-Host -n "  |"
        $i++
    }

    if ($depth -gt 0) {
        Write-Host -n "- "
    }

    Write-Host -n $fileName

    if ($fileExists) {
        Write-Host  ""
    }
    else
    {
        Write-Host " [not found]"
    }
}

function GetSubfiles(
    [string] $yamlFilePath,
    $yamlFileParameters
) {
    # 1. Pass a template file path and yaml parameters key value list as to this function.
    #
    # 2. Iterate complete file, line by line, search only for "template:". When a block is found, check the expression 
    # following "template:". If it contains the parameter name, replace it with the corresponding value from the "parameters" 
    # passed to this function. If not, return the filename as found.
    #
    # 3. After the "template:" line, also capture its following parameter lines and return them along with the yaml 
    # filename (return an object with properties FilePath and Parameters).

    $subParameters = New-Object -TypeName 'System.Collections.ArrayList';
    $parsingState = 0
    $subFileName = ""
    $parametersIndent = 0
    $lines = Get-Content $yamlFilePath
    foreach ($line in $lines)
    {
        switch ($parsingState)
        {
            0 {
                # 0 - default (look for template line)
                $templateMatch = $line | Select-String -Pattern "- template:[ \t]*(.*)" -AllMatches
                if ($templateMatch -ne $null)
                {
                    $subFileName = ResolveParameterExpression $templateMatch.matches.groups[1].value $yamlFileParameters
                    $parsingState = 1
                }
            }
            1 {
                # 1 - passed template line (look for parameters line)
                $parBeginMatch = $line | Select-String -Pattern "([ \t]*)parameters:" -AllMatches
                if ($parBeginMatch -ne $null)
                {
                    $subParameters.Clear()
                    $parametersIndent = $parBeginMatch.matches.groups[1].value.Length + 1
                    $parsingState = 2
                }
            }
            2 {
                # 2 - passed parameters line (read parameters)
                $parBlockRegex = "[ \t]{$parametersIndent,}(.*)"
                $parBlockMatch = $line | Select-String -Pattern $parBlockRegex -AllMatches
                if ($parBlockMatch -ne $null)
                {
                    # Skip parameter child lines like in array values
                    $parLineRegex = "[ \t]{$parametersIndent,}(.*):[ \t]*(.*)"
                    $parLineMatch = $line | Select-String -Pattern $parLineRegex -AllMatches
                    if ($parLineMatch -ne $null)
                    {
                        $parName = $parLineMatch.matches.groups[1].value
                        $parValue = ResolveParameterExpression $parLineMatch.matches.groups[2].value $yamlFileParameters

                        $subParameter = New-Object PSObject -Property @{ Name = $parName; Value = $parValue }
                        $subParameters.Add($subParameter) > $null
                    }
                }
                else
                {
                    $subFile = New-Object PSObject -Property @{ FileName = $subFileName; Parameters = @( $subParameters ) }
                    Write-Output $subFile
                    $parsingState = 0
                }
            }
        }
    }

    if ($parsingState -ne 0)
    {
        # Write last element if there is not completed yet
        $subFile = New-Object PSObject -Property @{ FileName = $subFileName; Parameters = @( $subParameters ) }
        Write-Output $subFile
    }
}

function ResolveParameterExpression(
    [string] $expression,
    $parameters
) {
    # If $templateValue starts with '${' and contains 'parameters', try to replace with matching value from $yamlFileParameters
    $paramExpressionMatch = $expression | Select-String -Pattern "\$\{[ \t]*\{[ \t]*parameters\.(.*)[ \t]*\}" -AllMatches
    if ($paramExpressionMatch -ne $null)
    {
        foreach ($parameter in $parameters)
        {
            $parMatch = $expression | Select-String -Pattern $parameter.Name -SimpleMatch
            if ($parMatch -ne $null)
            {
                return $parameter.Value
                break
            }
        }
    }
    else
    {
        return $expression    
    }
}

function CheckAndAddProcessedFiles($yamlFilePath)
{
    $isFileNew = $false
    if (-not $processedFiles.Contains($yamlFilePath))
    {
        $processedFiles.Add($yamlFilePath)
        $isFileNew = $true
    }

    return $isFileNew
}


# Main

$processedFiles = New-Object -TypeName 'System.Collections.ArrayList';
$currentDirectory = (Get-Location).Path

$yamlRoot = ProcessYamlFiles $currentDirectory $YamlFile $RemoveDuplicates $null 0

# TODO function to walk yaml tree structure
#$isFileNew = CheckAndAddProcessedFiles $fullYamlPath
#if (($RemoveDuplicates -eq $false) -or ($isFileNew -eq $true))
#{
#}

exit 0
